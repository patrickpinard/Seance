import Foundation
import SeanceKit
import SwiftData
import Testing
@testable import SeanceDonnees

/// Fiches TMDB minimales, construites par décodage comme en production.
private enum TMDB {
    static func film() throws -> FicheFilm {
        try decoder(#"""
        {"id": 267860, "title": "La Chute de Londres", "original_title": "London Has Fallen", "original_language": "en",
         "overview": "", "runtime": 99, "genres": [{"id": 28, "name": "Action"}, {"id": 53, "name": "Thriller"}],
         "vote_average": 6.3, "vote_count": 5000, "poster_path": "/chute.jpg", "release_date": "2016-03-02",
         "credits": {"cast": [
            {"id": 17276, "name": "Gerard Butler", "order": 0},
            {"id": 2176, "name": "Aaron Eckhart", "order": 1},
            {"id": 192, "name": "Morgan Freeman", "order": 2}], "crew": []}}
        """#)
    }

    static func serie() throws -> SerieDetail {
        try decoder(#"""
        {"id": 108978, "name": "Reacher", "original_name": "Reacher", "original_language": "en", "overview": "",
         "status": "Returning Series", "in_production": true, "number_of_seasons": 3, "number_of_episodes": 24,
         "episode_run_time": [50], "seasons": [], "vote_average": 8.0, "vote_count": 1500,
         "genres": [{"id": 10759, "name": "Action & Adventure"}], "poster_path": "/reacher.jpg",
         "aggregate_credits": {"cast": [{"id": 1, "name": "Alan Ritchson", "order": 0}], "crew": []}}
        """#)
    }

    static func episodes(saison: Int, nombre: Int) throws -> [EpisodeTMDB] {
        try (1...nombre).map { n in
            try decoder(#"{"id": \#(saison * 100 + n), "name": "E\#(n)", "overview": "", "episode_number": \#(n), "season_number": \#(saison), "runtime": \#(n == 2 ? "null" : "48"), "air_date": "2022-02-04"}"#)
        }
    }

    private static func decoder<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}

@Suite("Services SwiftData")
@MainActor
struct ServicesTests {
    @Test func suivrePuisMarquerUnFilmVu() throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let service = ServiceSuivi(contexte: conteneur.mainContext)
        let film = try TMDB.film()

        try service.suivre(film: film)
        let suivi = try #require(try service.suivi(film.reference))
        #expect(suivi.statut == .aVoir)
        #expect(suivi.acteursPrincipaux == ["Gerard Butler", "Aaron Eckhart", "Morgan Freeman"])
        #expect(suivi.genres == [28, 53])

        try service.marquerVu(film: film, note: 7, le: Date(timeIntervalSince1970: 1_789_000_000))
        #expect(suivi.statut == .termine)
        #expect(suivi.note == 7)
        #expect(try service.visionnages(film.reference).map(\.dureeMinutes) == [99])
        #expect(try service.estVu(film.reference))

        // Un nouvel ajout ne remet pas un film vu « à voir ».
        try service.suivre(film: film)
        #expect(suivi.statut == .termine)
        #expect(try conteneur.mainContext.fetchCount(FetchDescriptor<Suivi>()) == 1)
    }

    @Test func cocherDesEpisodesSansDoublon() throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let service = ServiceSuivi(contexte: conteneur.mainContext)
        let serie = try TMDB.serie()
        let saison1 = try TMDB.episodes(saison: 1, nombre: 3)

        #expect(try service.cocher(Array(saison1.prefix(2)), serie: serie) == 2)
        #expect(try service.cocher(saison1, serie: serie) == 1)
        #expect(try service.episodesVus(serie.reference) == [
            NumeroEpisode(saison: 1, episode: 1), NumeroEpisode(saison: 1, episode: 2), NumeroEpisode(saison: 1, episode: 3),
        ])
        // Épisode sans durée TMDB : la durée type de la série.
        #expect(try service.visionnages(serie.reference).map(\.dureeMinutes).sorted() == [48, 48, 50])
        #expect(try service.suivi(serie.reference)?.statut == .enCours)

        try service.noter(NumeroEpisode(saison: 1, episode: 3), serie: serie.reference, note: 9)
        try service.decocher(NumeroEpisode(saison: 1, episode: 1), serie: serie.reference)
        #expect(try service.episodesVus(serie.reference).count == 2)
        #expect(try service.visionnages(serie.reference).compactMap(\.note) == [9])
    }

    @Test func exclusionDeLangue() throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let service = ServiceSuivi(contexte: conteneur.mainContext)
        let reference = ReferenceTitre(type: .film, tmdbID: 496_243)
        try service.exclureLangue(reference, titre: "Parasite")
        #expect(try service.suivi(reference)?.exclusionLangue == true)
    }

    @Test func sauvegardeAllerRetourSansDoublon() throws {
        let source = try EntrepotSeance.conteneur(.memoire)
        let suivi = ServiceSuivi(contexte: source.mainContext)
        try suivi.marquerVu(film: try TMDB.film(), note: 8)
        try suivi.cocher(try TMDB.episodes(saison: 1, nombre: 3), serie: try TMDB.serie())
        let liste = ListePerso(nom: "Soirées Statham")
        liste.titres = [ReferenceTitre(type: .film, tmdbID: 267_860)]
        source.mainContext.insert(liste)
        source.mainContext.insert(Abonnement(providerID: 8, nom: "Netflix"))
        source.mainContext.insert(Chaine(identifiantGuide: "M6.fr", nom: "M6", source: .xmltvfr))
        try source.mainContext.save()

        let fichier = try ServiceSauvegarde(contexte: source.mainContext).exporter().encoder()

        let cible = try EntrepotSeance.conteneur(.memoire)
        let importeur = ServiceSauvegarde(contexte: cible.mainContext)
        let plan = try importeur.importer(try Sauvegarde.decoder(fichier))
        #expect(plan.suivis.count == 2)
        #expect(plan.visionnages.count == 4)
        #expect(try cible.mainContext.fetch(FetchDescriptor<ListePerso>()).first?.titres.count == 1)
        #expect(try cible.mainContext.fetchCount(FetchDescriptor<Chaine>()) == 1)

        // Réimporter le même fichier n'ajoute rien.
        #expect(try importeur.importer(try Sauvegarde.decoder(fichier)).estVide)
        #expect(try cible.mainContext.fetchCount(FetchDescriptor<Visionnage>()) == 4)
    }

    @Test func purgeDuCache() throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let contexte = conteneur.mainContext
        let maintenant = Date(timeIntervalSince1970: 1_789_000_000)
        let ancien = TitreCache(reference: ReferenceTitre(type: .film, tmdbID: 1), donnees: Data(), majLe: maintenant.addingTimeInterval(-200 * 86_400))
        let recent = TitreCache(reference: ReferenceTitre(type: .film, tmdbID: 2), donnees: Data(), majLe: maintenant.addingTimeInterval(-10 * 86_400))
        var passe = ProgrammeTV(chaine: "M6.fr", debut: maintenant.addingTimeInterval(-7200), fin: maintenant.addingTimeInterval(-600), titre: "Heat")
        passe.categories = ["Film"]
        var aVenir = passe
        aVenir.fin = maintenant.addingTimeInterval(3600)
        [ancien, recent].forEach(contexte.insert)
        contexte.insert(Diffusion(programme: passe, rattachement: nil))
        contexte.insert(Diffusion(programme: aVenir, rattachement: nil))
        try contexte.save()

        let rapport = try EntretienCache(contexte: contexte).purger(maintenant: maintenant)
        #expect(rapport == EntretienCache.Rapport(fichesSupprimees: 1, diffusionsSupprimees: 1))
        #expect(try contexte.fetch(FetchDescriptor<TitreCache>()).map(\.tmdbID) == [2])
    }
}

@Suite("Ma soirée")
@MainActor
struct ServiceSoireeTests {
    @Test func retenirSansDoublonEtSoireeDeSixHeureASixHeure() throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let service = ServiceSoiree(contexte: conteneur.mainContext)
        let heat = ReferenceTitre(type: .film, tmdbID: 949)
        let soir = Date(timeIntervalSince1970: 1_789_588_800) // 16.09.2026 22:00 en Suisse

        try service.retenir(heat, titre: "Heat", cheminAffiche: nil, maintenant: soir)
        try service.retenir(heat, titre: "Heat", cheminAffiche: nil, maintenant: soir)
        #expect(try service.selection(maintenant: soir).count == 1)

        // À 1 h du matin, c'est encore la même soirée ; le lendemain à midi, une nouvelle.
        #expect(try service.estRetenu(heat, maintenant: soir.addingTimeInterval(3 * 3600)))
        #expect(try service.selection(maintenant: soir.addingTimeInterval(14 * 3600)).isEmpty)

        try service.retirer(heat, maintenant: soir)
        #expect(try service.selection(maintenant: soir).isEmpty)
    }
}
