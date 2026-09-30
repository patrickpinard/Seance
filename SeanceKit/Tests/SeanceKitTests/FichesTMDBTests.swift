import Foundation
import Testing
@testable import SeanceKit

@Suite("Fiches complètes TMDB")
struct FichesTMDBTests {
    @Test func ficheFilmEnUnAppel() throws {
        let film = try JSONDecoder().decode(FicheFilm.self, from: Fixture.donnees("fiche_film"))
        #expect(film.reference == ReferenceTitre(type: .film, tmdbID: 11))
        #expect(film.dureeMinutes == 121)
        #expect(film.genres.map(\.id) == [12, 28, 878])
        #expect(film.dateSortie == DateTMDB(annee: 1977, mois: 5, jour: 25))

        let casting = try #require(film.casting)
        #expect(casting.principaux(3).map(\.nom) == ["Edward Norton", "Brad Pitt", "Helena Bonham Carter"])
        #expect(casting.realisateurs.map(\.nom) == ["David Fincher"])
        #expect(film.datesDeSortie?.sorties(region: "CH").isEmpty == false)
        #expect(film.fournisseurs?.offres(region: "CH")?.abonnement.map(\.id) == [119, 337, 622])
        // La bande-annonce officielle passe devant.
        #expect(film.videos?.bandesAnnonces.first?.officielle == true)
        #expect(film.videos?.bandesAnnonces.first?.urlYouTube?.host() == "www.youtube.com")
    }

    @Test func ficheSerieAvecCastingCumule() throws {
        let serie = try JSONDecoder().decode(SerieDetail.self, from: Fixture.donnees("fiche_serie"))
        #expect(serie.genres.map(\.id) == [10765, 18, 10759])
        #expect(serie.casting?.acteurs.first?.nom == "Emilia Clarke")
        #expect(serie.casting?.acteurs.first?.nombreEpisodes == 78)
        #expect(serie.fournisseurs?.offres(region: "CH")?.abonnement.map(\.nom) == ["Sky"])
    }

    @Test func filmographieDuPlusRecentAuPlusAncien() throws {
        let filmographie = try JSONDecoder().decode(Filmographie.self, from: Fixture.donnees("person_combined_credits"))
        #expect(filmographie.roles.map(\.titre) == [
            "The Da Vinci Code", "Life with Bonnie", "The Green Mile", "Apollo 13", "Forrest Gump", "LIVE with Kelly and Mark",
        ])
        #expect(filmographie.roles.filter { $0.type == .serie }.map(\.tmdbID) == [2103, 1900])
        #expect(filmographie.roles.last?.date == DateTMDB(annee: 1988, mois: 9, jour: 5))
    }

    @Test func complementsDansLaRequete() async throws {
        let transport = TransportSimule([
            .init(code: 200, corps: try Fixture.donnees("fiche_film")),
            .init(code: 200, corps: try Fixture.donnees("fiche_serie")),
        ])
        let client = TMDBClient(identifiants: .jetonLecture("t"), transport: transport)
        _ = try await client.film(11)
        _ = try await client.serie(1399, complements: [.casting, .fournisseurs, .datesDeSortie])

        let requetes = await transport.requetes
        func complements(_ r: URLRequest) -> String? {
            URLComponents(url: r.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "append_to_response" }?.value
        }
        #expect(complements(requetes[0]) == "credits,release_dates,watch/providers,videos,keywords")
        // Pas de dates de sortie pour une série ; casting cumulé de toutes les saisons.
        #expect(complements(requetes[1]) == "aggregate_credits,watch/providers")
    }
}

/// La tête de l'accueil (8.7) choisit ses images parmi celles du titre : sans texte, assez grandes, le logo en PNG.
@Suite("Images d'un titre")
struct ImagesTitreTests {
    @Test func choisitLesImagesSansTexteEtLeLogo() async throws {
        let transport = TransportSimule([.init(code: 200, corps: try Fixture.donnees("movie_images"))])
        let client = TMDBClient(identifiants: .jetonLecture("t"), transport: transport)
        let images = try await client.images(.film, id: 640146)

        // Le mieux noté sans texte, parmi ceux assez grands pour l'écran entier.
        #expect(images.fondSansTexte == "/fondPropre.jpg")
        #expect(images.afficheSansTexte == "/afficheSansTexte.jpg")
        // Le français d'abord, en PNG seulement.
        #expect(images.logo == "/logoFrancais.png")

        let requete = try #require(await transport.requetes.first)
        #expect(requete.url?.path == "/3/movie/640146/images")
        #expect(URLComponents(url: requete.url!, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "include_image_language" }?.value == "fr,en,null")
    }
}

@Suite("Tendances et recherche globale")
struct TitresMixtesTests {
    @Test func tendancesMelangentFilmsEtSeries() async throws {
        let transport = TransportSimule([.init(code: 200, corps: try Fixture.donnees("trending_all"))])
        let tendances = try await TMDBClient(identifiants: .jetonLecture("t"), transport: transport).tendances(.semaine)

        #expect(tendances.map(\.reference) == [
            ReferenceTitre(type: .film, tmdbID: 934_433), ReferenceTitre(type: .film, tmdbID: 868_759),
            ReferenceTitre(type: .film, tmdbID: 502_356), ReferenceTitre(type: .serie, tmdbID: 103_768),
            ReferenceTitre(type: .serie, tmdbID: 124_800),
        ])
        #expect(tendances[3].titre == "Sweet Tooth")
        #expect(await transport.requetes.first?.url?.path() == "/3/trending/all/week")
    }

    @Test func personnesEtTypesInconnus() throws {
        let json = #"""
        {"page": 1, "total_pages": 1, "total_results": 3, "results": [
          {"media_type": "person", "id": 6384, "name": "Keanu Reeves", "profile_path": "/keanu.jpg", "known_for_department": "Acting"},
          {"media_type": "collection", "id": 1},
          {"media_type": "tv", "id": 108978, "name": "Reacher", "original_name": "Reacher", "original_language": "en",
           "overview": "", "genre_ids": [10759], "origin_country": ["US"], "vote_average": 8, "vote_count": 10, "popularity": 1,
           "first_air_date": "2022-02-04"}]}
        """#
        let page = try JSONDecoder().decode(PageTMDB<ElementMixte>.self, from: Data(json.utf8))
        #expect(page.resultats.compactMap(\.personne).map(\.nom) == ["Keanu Reeves"])
        #expect(page.resultats.compactMap(\.titre).map(\.date) == [DateTMDB(annee: 2022, mois: 2, jour: 4)])
        #expect(page.resultats[1] == .autre)
    }
}

@Suite("Fiche acteur")
struct FicheActeurTests {
    private func credit(_ id: Int, _ type: String, _ titre: String, _ date: String, genres: [Int] = [28], role: String = "Rôle", job: String? = nil) -> [String: Any] {
        var json: [String: Any] = ["id": id, "media_type": type, "genre_ids": genres, "character": role, "vote_average": 7, "vote_count": 100]
        if type == "tv" { json["name"] = titre; json["first_air_date"] = date } else { json["title"] = titre; json["release_date"] = date }
        if let job { json["job"] = job; json["character"] = nil }
        return json
    }

    @Test func compteFiltresEtRealisations() {
        let filmographie = Construire.decoder(Filmographie.self, [
            "cast": [
                credit(1, "movie", "John Wick", "2014-10-24"),
                credit(2, "movie", "Speed", "1994-06-10"),
                credit(3, "movie", "Something's Gotta Give", "2003-12-12", genres: [35, 18]),
                credit(4, "movie", "Documentaire", "2020-01-01", genres: [99], role: "Himself"),
                credit(5, "tv", "Talk-show", "2015-01-01", genres: [10767], role: "Self"),
                credit(6, "movie", "John Wick 5", "2030-01-01"),
                credit(7, "tv", "Swedish Dicks", "2016-08-01", genres: [35]),
            ],
            "crew": [credit(8, "movie", "Man of Tai Chi", "2013-07-05", job: "Director"), credit(1, "movie", "John Wick", "2014-10-24", job: "Producer")],
        ])
        let aujourdhui = DateTMDB(annee: 2026, mois: 9, jour: 17)
        let vus: Set<ReferenceTitre> = [ReferenceTitre(type: .film, tmdbID: 1)]

        // Documentaire, talk-show et film pas encore sorti ne comptent pas.
        #expect(AnalyseFilmographie.compte(filmographie.roles, type: .film, vus: vus, aujourdhui: aujourdhui) == .init(vus: 1, total: 3))
        #expect(AnalyseFilmographie.compte(filmographie.roles, type: .serie, vus: vus, aujourdhui: aujourdhui) == .init(vus: 0, total: 1))
        #expect(filmographie.realisations.map(\.titre) == ["Man of Tai Chi"])

        var filtres = AnalyseFilmographie.Filtres()
        filtres.actionSeulement = true
        filtres.pasVus = true
        #expect(AnalyseFilmographie.filtrer(filmographie.roles, filtres: filtres, vus: vus, regardables: []).map(\.titre) == ["John Wick 5", "Speed"])
        filtres = AnalyseFilmographie.Filtres()
        filtres.ceSoir = true
        #expect(AnalyseFilmographie.filtrer(filmographie.roles, filtres: filtres, vus: vus,
                                            regardables: [ReferenceTitre(type: .film, tmdbID: 2)]).map(\.titre) == ["Speed"])
    }

    @Test func ageAujourdhuiOuAuDeces() {
        let keanu = Construire.decoder(FichePersonne.self, ["id": 6384, "name": "Keanu Reeves", "biography": "", "birthday": "1964-09-02"])
        #expect(keanu.age(aujourdhui: DateTMDB(annee: 2026, mois: 9, jour: 17)) == 62)
        #expect(keanu.age(aujourdhui: DateTMDB(annee: 2026, mois: 9, jour: 1)) == 61)
        let decede = Construire.decoder(FichePersonne.self, ["id": 1, "name": "X", "biography": "", "birthday": "1940-05-10", "deathday": "2000-01-01"])
        #expect(decede.age(aujourdhui: DateTMDB(annee: 2026, mois: 9, jour: 17)) == 59)
    }
}

@Suite("Fiche reconstituée quand TMDB échoue")
struct FicheParMorceauxTests {
    @Test func erreur500SurLesComplementsGroupes() async throws {
        let base = #"{"id": 108978, "name": "Reacher", "original_name": "Reacher", "original_language": "en", "overview": "", "status": "Returning Series", "in_production": true, "number_of_seasons": 3, "number_of_episodes": 24, "episode_run_time": [50], "seasons": [], "vote_average": 8, "vote_count": 3000, "genres": []}"#
        let transport = TransportSimule([
            .init(code: 500, corps: Data(#"{"status_message": "Encoding::CompatibilityError"}"#.utf8)),
            .init(code: 200, corps: Data(base.utf8)),
            .init(code: 500, corps: Data()),
            .init(code: 200, corps: Data(#"{"results": {"CH": {"flatrate": [{"provider_id": 119, "provider_name": "Prime Video", "display_priority": 1}]}}}"#.utf8)),
        ])
        let client = TMDBClient(identifiants: .jetonLecture("t"), transport: transport)
        let serie = try await client.serie(108_978, complements: [.casting, .fournisseurs])
        #expect(serie.nom == "Reacher")
        // Le casting a encore échoué seul : il manque, mais la fiche et les plateformes sont là.
        #expect(serie.casting == nil)
        #expect(serie.fournisseurs?.offres()?.abonnement.first?.nom == "Prime Video")
        let chemins = await transport.requetes.map { $0.url!.path() }
        #expect(chemins == ["/3/tv/108978", "/3/tv/108978", "/3/tv/108978/aggregate_credits", "/3/tv/108978/watch/providers"])
    }
}

@Suite("Bandes-annonces")
struct BandesAnnoncesTests {
    @Test func francaisDabordPuisBandesAnnoncesAvantTeasers() throws {
        let json = #"""
        {"results": [
          {"key": "a", "site": "YouTube", "type": "Featurette", "name": "Making of", "official": true, "iso_639_1": "fr"},
          {"key": "b", "site": "YouTube", "type": "Teaser", "name": "Teaser", "official": true, "iso_639_1": "en"},
          {"key": "c", "site": "YouTube", "type": "Trailer", "name": "Official Trailer", "official": true, "iso_639_1": "en"},
          {"key": "d", "site": "Vimeo", "type": "Trailer", "name": "Vimeo", "official": true, "iso_639_1": "fr"},
          {"key": "e", "site": "YouTube", "type": "Teaser", "name": "Teaser [VF]", "official": false, "iso_639_1": "fr"},
          {"key": "f", "site": "YouTube", "type": "Trailer", "name": "Bande-annonce [VF]", "official": true, "iso_639_1": "fr"}
        ]}
        """#
        let liste = try JSONDecoder().decode(ListeVideos.self, from: Data(json.utf8))
        #expect(liste.bandesAnnonces.map(\.cle) == ["f", "e", "c", "b"])
        #expect(liste.bandesAnnonces.first?.urlIntegration?.host == "www.youtube-nocookie.com")
    }

    @Test func videosDemandeesEnFrancaisEtEnAnglais() {
        let items = TMDBClient.parametresComplements([.videos, .casting], type: .film)
        #expect(items.first { $0.name == "include_video_language" }?.value == "fr,en,null")
        #expect(TMDBClient.parametresComplements([.casting], type: .film).count == 1)
    }
}
