import Foundation
import Testing
@testable import SeanceKit

@Suite("Critères d'Explorer")
struct CriteresDecouverteTests {
    private func dictionnaire(_ items: [URLQueryItem]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    /// La maquette Explorer : Keanu Reeves, Action ou Thriller, 1990 à 2019, note 6,5 et plus.
    private var criteresMaquette: CriteresDecouverte {
        var c = CriteresDecouverte()
        c.genresInclus = [28, 53]
        c.genresExclus = [27]
        c.acteurs = [6384]
        c.sortieDepuis = DateTMDB(annee: 1990, mois: 1, jour: 1)
        c.sortieJusqua = DateTMDB(annee: 2019, mois: 12, jour: 31)
        c.noteMin = 6.5
        c.fournisseurs = [8, 119]
        c.monetisations = [.abonnement]
        return c
    }

    @Test func filmsTousLesCriteres() {
        let p = dictionnaire(criteresMaquette.parametres(pour: .film))
        #expect(p["with_genres"] == "28|53")
        #expect(p["without_genres"] == "27")
        #expect(p["with_cast"] == "6384")
        #expect(p["primary_release_date.gte"] == "1990-01-01")
        #expect(p["primary_release_date.lte"] == "2019-12-31")
        #expect(p["vote_average.gte"] == "6.5")
        #expect(p["with_watch_providers"] == "8|119")
        #expect(p["with_watch_monetization_types"] == "flatrate")
        #expect(p["watch_region"] == "CH")
        #expect(p["sort_by"] == "popularity.desc")
        #expect(p["include_adult"] == "false")
        #expect(p["region"] == nil)
    }

    @Test func seriesSansFiltrePersonneNiTypeDeSortie() {
        var c = criteresMaquette
        c.typesSortie = [.salles]
        c.tri = .titre
        c.decroissant = false
        let p = dictionnaire(c.parametres(pour: .serie))
        #expect(p["with_cast"] == nil)
        #expect(p["with_release_type"] == nil)
        #expect(p["first_air_date.gte"] == "1990-01-01")
        #expect(p["primary_release_date.gte"] == nil)
        #expect(p["sort_by"] == "name.asc")
    }

    @Test func personnesToutesOuAuMoinsUne() {
        var c = CriteresDecouverte()
        c.acteurs = [6384, 2975]
        c.realisateurs = [40644]
        #expect(dictionnaire(c.parametres(pour: .film))["with_cast"] == "6384,2975")
        c.combinaisonPersonnes = .auMoinsUn
        let p = dictionnaire(c.parametres(pour: .film))
        #expect(p["with_cast"] == "6384|2975")
        #expect(p["with_crew"] == "40644")
    }

    @Test func typesDeSortieAvecRegion() {
        var c = CriteresDecouverte()
        c.typesSortie = [.salles, .numerique]
        let p = dictionnaire(c.parametres(pour: .film))
        #expect(p["with_release_type"] == "3|4")
        #expect(p["region"] == "CH")
        #expect(p["watch_region"] == nil)
    }

    @Test func triParDate() {
        var c = CriteresDecouverte()
        c.tri = .date
        #expect(dictionnaire(c.parametres(pour: .film))["sort_by"] == "primary_release_date.desc")
        #expect(dictionnaire(c.parametres(pour: .serie))["sort_by"] == "first_air_date.desc")
    }

    @Test func enregistrableEnJSON() throws {
        let donnees = try JSONEncoder().encode(criteresMaquette)
        #expect(try JSONDecoder().decode(CriteresDecouverte.self, from: donnees) == criteresMaquette)
    }
}
