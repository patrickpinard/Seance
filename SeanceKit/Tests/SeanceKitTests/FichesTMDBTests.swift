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
