import Foundation
import Testing
@testable import SeanceKit

/// Vérifie le décodage contre l'API réelle. Ne tourne que si la clé est fournie dans
/// l'environnement : `SEANCE_CLE_TMDB=… outils/tester.sh`. La clé n'est jamais écrite dans le dépôt.
@Suite("TMDB réel", .enabled(if: ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] != nil))
struct IntegrationTMDBTests {
    private let client = TMDBClient(identifiants: .depuis(ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] ?? ""))

    @Test func tendancesEtRecherche() async throws {
        #expect(try await client.tendances(.jour).count >= 10)
        let resultats = try await client.rechercherTout("Keanu Reeves")
        #expect(resultats.contains { $0.personne?.id == 6384 })
    }

    @Test func ficheFilmComplete() async throws {
        let film = try await client.film(603_692)
        #expect(film.titre.contains("John Wick"))
        #expect((film.dureeMinutes ?? 0) > 150)
        #expect(film.casting?.acteurs.first?.nom == "Keanu Reeves")
        #expect(film.datesDeSortie?.sorties(region: "CH").isEmpty == false)
        #expect(film.fournisseurs != nil)
    }

    @Test func ficheSerieEtSaison() async throws {
        let serie = try await client.serie(108_978, complements: [.casting, .fournisseurs, .videos])
        #expect(serie.nom == "Reacher")
        #expect(serie.casting?.acteurs.isEmpty == false)
        let saison = try await client.saison(1, serie: 108_978)
        #expect(saison.episodes.count == 8)
    }

    @Test func plateformesSuissesEtDecouverte() async throws {
        let catalogue = try await client.catalogueFournisseurs(.film)
        #expect(catalogue.contains { $0.id == 691 && $0.nom == "Play Suisse" })
        var criteres = CriteresDecouverte()
        criteres.genresInclus = [28]
        criteres.acteurs = [6384]
        criteres.fournisseurs = [8, 119, 337, 350, 150, 691]
        criteres.monetisations = [.abonnement]
        let page = try await client.decouvrirFilms(criteres)
        #expect(page.nombreResultats >= 0)
    }

    @Test func filmographieEtDatesDeSortie() async throws {
        let filmographie = try await client.filmographie(personne: 6384)
        #expect(filmographie.roles.contains { $0.tmdbID == 603 && $0.type == .film })
        let dates = try await client.datesDeSortie(film: 603_692)
        #expect(!dates.pays.isEmpty)
    }
}
