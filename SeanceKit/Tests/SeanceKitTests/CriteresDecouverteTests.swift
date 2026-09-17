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

    @Test func nouveautesDuJourEtDeLaSemaine() {
        let mercredi = Date.suisse("2026-09-16 22:30")
        let films = dictionnaire(CriteresDecouverte.nouveautes(.film, periode: .semaine, maintenant: mercredi).parametres(pour: .film))
        #expect(films["primary_release_date.gte"] == "2026-09-10")
        #expect(films["primary_release_date.lte"] == "2026-09-16")

        let series = dictionnaire(CriteresDecouverte.nouveautes(.serie, periode: .jour, maintenant: mercredi).parametres(pour: .serie))
        #expect(series["air_date.gte"] == "2026-09-16")
        #expect(series["air_date.lte"] == "2026-09-16")
        #expect(series["first_air_date.gte"] == nil)
        #expect(series["without_genres"] == "10763|10764|10766|10767")
    }

    @Test func top10DeLAnnee() {
        let mercredi = Date.suisse("2026-09-16 22:30")
        let films = dictionnaire(CriteresDecouverte.top(.film, maintenant: mercredi).parametres(pour: .film))
        #expect(films["sort_by"] == "vote_average.desc")
        #expect(films["vote_count.gte"] == "300")
        #expect(films["primary_release_date.gte"] == "2025-09-16")
        #expect(films["primary_release_date.lte"] == "2026-09-16")
        #expect(films["without_genres"] == "99|10770")

        let series = dictionnaire(CriteresDecouverte.top(.serie, maintenant: mercredi).parametres(pour: .serie))
        #expect(series["sort_by"] == "vote_average.desc")
        #expect(series["vote_count.gte"] == "150")
        #expect(series["air_date.gte"] == "2025-09-16")
        #expect(series["without_genres"] == "99|10763|10764|10766|10767")
    }

    @Test func episodeQuiFaitLaNouveaute() throws {
        let json = #"""
        {"id": 1, "name": "Reacher", "original_name": "Reacher", "original_language": "en", "overview": "", "status": "Returning Series",
         "in_production": true, "number_of_seasons": 3, "number_of_episodes": 24, "episode_run_time": [50], "seasons": [],
         "vote_average": 8, "vote_count": 3000, "genres": [], "first_air_date": "2022-02-03",
         "last_episode_to_air": {"id": 10, "name": "Épisode 5", "overview": "", "episode_number": 5, "season_number": 3, "air_date": "2026-09-14"},
         "next_episode_to_air": {"id": 11, "name": "Épisode 6", "overview": "", "episode_number": 6, "season_number": 3, "air_date": "2026-09-21"}}
        """#
        let serie = try JSONDecoder().decode(SerieDetail.self, from: Data(json.utf8))
        let semaine = PeriodeTendance.semaine.bornes(maintenant: Date.suisse("2026-09-16 22:30"))
        #expect(semaine.debut == DateTMDB(annee: 2026, mois: 9, jour: 10))
        #expect(serie.episodeNouveau(depuis: semaine.debut, jusqua: semaine.fin)?.numero == 5)
        #expect(!serie.commence(depuis: semaine.debut, jusqua: semaine.fin))
        let jour = PeriodeTendance.jour.bornes(maintenant: Date.suisse("2026-09-16 22:30"))
        #expect(serie.episodeNouveau(depuis: jour.debut, jusqua: jour.fin) == nil)
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
        // Sans date de sortie régionale, TMDB ignorerait le type de sortie.
        #expect(p["release_date.lte"] == "2100-12-31")
        #expect(p["primary_release_date.lte"] == nil)
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
