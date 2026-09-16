import Foundation
import Testing
@testable import SeanceKit

@Suite("Décodage des réponses TMDB")
struct TMDBDecodageTests {
    private func decoder<T: Decodable>(_ type: T.Type, _ fixture: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Fixture.donnees(fixture))
    }

    @Test func pageDeFilms() throws {
        let page = try decoder(PageTMDB<FilmResume>.self, "discover_movie")
        #expect(page.page == 1)
        #expect(page.nombreResultats == 760_385)
        #expect(page.resultats.count == 20)
        let film = try #require(page.resultats.first)
        #expect(film.id == 640_146)
        #expect(film.titre == "Ant-Man and the Wasp: Quantumania")
        #expect(film.genres == [28, 12, 878])
        #expect(film.dateSortie == DateTMDB(annee: 2023, mois: 2, jour: 15))
        #expect(film.cheminAffiche == "/ngl2FKBlU4fhbdsrtdom9LVLBXw.jpg")
        #expect(film.nombreVotes == 1856)
    }

    @Test func pageDeSeries() throws {
        let serie = try #require(try decoder(PageTMDB<SerieResume>.self, "discover_tv").resultats.first)
        #expect(serie.id == 202_250)
        #expect(serie.nom == "Dirty Linen")
        #expect(serie.premiereDiffusion == DateTMDB(annee: 2023, mois: 1, jour: 23))
        #expect(serie.paysOrigine == ["PH"])
    }

    @Test func plateformesEnSuisse() throws {
        let fournisseurs = try decoder(FournisseursParPays.self, "movie_watch_providers")
        let suisse = try #require(fournisseurs.offres(region: "CH"))
        #expect(suisse.abonnement.map(\.id) == [119, 337, 622])
        #expect(suisse.abonnement.first?.nom == "Amazon Prime Video")
        #expect(suisse.location.count == 6)
        #expect(suisse.achat.count == 6)
        // Catégories absentes de la réponse : listes vides, pas d'erreur.
        #expect(suisse.gratuit.isEmpty)
        #expect(suisse.avecPublicite.isEmpty)
        #expect(suisse.lien == URL(string: "https://www.themoviedb.org/movie/550-fight-club/watch?locale=CH"))
        #expect(fournisseurs.offres(region: "JP") == nil)
    }

    @Test func datesDeSortieEnSuisse() throws {
        let dates = try decoder(DatesDeSortie.self, "movie_release_dates")
        let suisse = dates.sorties(region: "CH")
        #expect(suisse.count == 2)
        #expect(suisse.allSatisfy { $0.type == .salles && $0.ageLegal == "18" })
        #expect(suisse.first?.date == Date.iso("1999-11-04T00:00:00Z"))
        #expect(dates.sorties(region: "XX").isEmpty)
    }

    @Test func detailDeSerieSansProchainEpisode() throws {
        let serie = try decoder(SerieDetail.self, "tv_details")
        #expect(serie.id == 1399)
        #expect(serie.nom == "Game of Thrones")
        #expect(serie.statut == "Ended")
        #expect(serie.enProduction == false)
        #expect(serie.nombreSaisons == 8)
        #expect(serie.prochainEpisode == nil)
        let dernier = try #require(serie.dernierEpisode)
        #expect(dernier.saison == 8 && dernier.numero == 6)
        #expect(dernier.dureeMinutes == 80)
        #expect(dernier.dateDiffusion == DateTMDB(annee: 2019, mois: 5, jour: 19))
        #expect(serie.saisons.first?.numero == 0)
        #expect(serie.saisons.first?.nombreEpisodes == 272)
    }

    @Test func saison() throws {
        let saison = try decoder(SaisonDetail.self, "tv_season")
        #expect(saison.numero == 1)
        #expect(saison.episodes.map(\.numero) == [1, 2, 3])
        #expect(saison.episodes.map(\.dureeMinutes) == [62, 56, 58])
        #expect(saison.episodes.first?.nom == "Winter Is Coming")
    }

    @Test func referentiels() throws {
        let genres = try decoder(ListeGenres.self, "genre_movie_list").genres
        #expect(genres.count == 19)
        #expect(genres.first == Genre(id: 28, nom: "Action"))

        let catalogue = try decoder(ListeFournisseurs.self, "watch_providers_movie").resultats
        #expect(catalogue.map(\.id) == [2, 3, 7, 8, 9])
        #expect(catalogue.first?.priorites["CH"] == 4)
    }

    @Test(arguments: [
        ("2023-02-15", DateTMDB(annee: 2023, mois: 2, jour: 15)),
        ("", nil),
        ("2023-13-01", nil),
        ("bientôt", nil),
    ] as [(String, DateTMDB?)])
    func dateTMDB(texte: String, attendue: DateTMDB?) {
        #expect(DateTMDB(texte: texte) == attendue)
    }
}
