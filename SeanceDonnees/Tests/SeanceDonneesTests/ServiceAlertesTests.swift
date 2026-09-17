import Foundation
import SeanceKit
import SwiftData
import Testing
@testable import SeanceDonnees

/// TMDB simulé : Reacher a un épisode le 18 septembre, Heat sort en salle le 20 ; plateformes et saisons modifiables.
private actor SourceSimulee: SourceAlertes {
    var plateformes: [Int] = []
    var prochainEpisode = #"{"id": 11, "name": "Épisode 6", "overview": "", "episode_number": 6, "season_number": 3, "air_date": "2026-09-18"}"#

    func changerPlateformes(_ ids: [Int]) {
        plateformes = ids
    }

    /// Keanu Reeves : John Wick, puis Ballerina 2 annoncé.
    var filmsKeanu = [#"{"id": 245891, "media_type": "movie", "title": "John Wick", "character": "John", "release_date": "2014-10-24"}"#]

    func annoncerBallerina2() {
        filmsKeanu.append(#"{"id": 1, "media_type": "movie", "title": "Ballerina 2", "character": "John", "release_date": "2027-06-04"}"#)
    }

    func filmographie(personne id: Int) async throws -> Filmographie {
        try decoder(#"{"cast": [\#(filmsKeanu.joined(separator: ","))], "crew": []}"#)
    }

    func annoncerSaison4() {
        prochainEpisode = #"{"id": 20, "name": "Épisode 1", "overview": "", "episode_number": 1, "season_number": 4, "air_date": "2027-03-12"}"#
    }

    private func decoder<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private var fournisseursJSON: String {
        let liste = plateformes.map { #"{"provider_id": \#($0), "provider_name": "Prime Video", "display_priority": 1}"# }.joined(separator: ",")
        return #"{"results": {"CH": {"flatrate": [\#(liste)]}}}"#
    }

    func serie(_ id: Int, complements: Set<ComplementFiche>) async throws -> SerieDetail {
        try decoder(#"""
        {"id": 108978, "name": "Reacher", "original_name": "Reacher", "original_language": "en", "overview": "", "status": "Returning Series",
         "in_production": true, "number_of_seasons": 3, "number_of_episodes": 24, "episode_run_time": [50], "seasons": [],
         "vote_average": 8, "vote_count": 3000, "genres": [], "next_episode_to_air": \#(prochainEpisode),
         "watch/providers": \#(fournisseursJSON)}
        """#)
    }

    func film(_ id: Int, complements: Set<ComplementFiche>) async throws -> FicheFilm {
        try decoder(#"""
        {"id": 949, "title": "Heat", "original_title": "Heat", "original_language": "en", "overview": "", "genres": [],
         "vote_average": 7.9, "vote_count": 7000, "release_date": "1995-12-15",
         "release_dates": {"results": [{"iso_3166_1": "CH", "release_dates": [{"release_date": "2026-09-20T00:00:00.000Z", "type": 3}]}]},
         "watch/providers": \#(fournisseursJSON)}
        """#)
    }
}

@Suite("Alertes des titres surveillés")
@MainActor
struct ServiceAlertesTests {
    private let midi = Date(timeIntervalSince1970: 1_789_560_000) // 16.09.2026 14:00 en Suisse
    private let reacher = ReferenceTitre(type: .serie, tmdbID: 108_978)
    private let heat = ReferenceTitre(type: .film, tmdbID: 949)

    private func preparer() throws -> ModelContainer {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let contexte = conteneur.mainContext
        contexte.insert(Suivi(reference: reacher, titre: "Reacher", statut: .termine))
        contexte.insert(Suivi(reference: heat, titre: "Heat"))
        let ecarte = Suivi(reference: ReferenceTitre(type: .film, tmdbID: 1), titre: "Écarté", statut: .exclu)
        contexte.insert(ecarte)
        contexte.insert(Abonnement(providerID: 119, nom: "Prime Video"))
        contexte.insert(Chaine(identifiantGuide: "M6.fr", nom: "M6", source: .xmltvfr))
        var programme = ProgrammeTV(chaine: "M6.fr", debut: midi.addingTimeInterval(86_400 + 7 * 3600 + 600), fin: midi.addingTimeInterval(86_400 + 10 * 3600), titre: "Heat")
        programme.categories = ["Film"]
        contexte.insert(Diffusion(programme: programme, rattachement: CandidatRattachement(tmdbID: 949, type: .film, titre: "Heat", titreOriginal: "Heat", annee: 1995)))
        try contexte.save()
        return conteneur
    }

    private func motifs(_ notifications: [NotificationPrevue]) -> [MotifAlerte] {
        notifications.flatMap(\.alertes).map(\.motif)
    }

    private func corps(_ notifications: [NotificationPrevue]) -> [String] {
        notifications.flatMap { $0.corps.components(separatedBy: "\n") }
    }

    @Test func veilleJourJTeleEtEcheances() async throws {
        let conteneur = try preparer()
        let contexte = conteneur.mainContext
        let service = ServiceAlertes(contexte: contexte)
        let notifications = try await service.calculer(source: SourceSimulee(), reglages: ReglagesAlertes(), maintenant: midi)
        let liste = motifs(notifications)

        // Série terminée mais surveillée : veille puis jour de l'épisode.
        #expect(liste.contains(.veilleEpisode(NumeroEpisode(saison: 3, episode: 6))))
        #expect(liste.contains(.nouvelEpisode(NumeroEpisode(saison: 3, episode: 6))))
        #expect(liste.contains(.veilleSortie(salles: true)) && liste.contains(.sortieSalles))
        #expect(liste.contains { if case .diffusionTele = $0 { true } else { false } })
        #expect(liste.contains { if case .rappelDiffusion = $0 { true } else { false } })
        // Première vérification : ni annonce ni arrivée ; le titre écarté ne compte pas.
        #expect(!liste.contains { if case .annonceSaison = $0 { true } else { false } })
        #expect(notifications.flatMap(\.alertes).allSatisfy { $0.reference.tmdbID != 1 })

        let echeances = try contexte.fetch(FetchDescriptor<Echeance>(sortBy: [SortDescriptor(\.date)]))
        #expect(echeances.map(\.libelle).contains("Épisode S03E06"))
        #expect(echeances.map(\.libelle).contains("Au cinéma"))
        #expect(echeances.contains { $0.nature == .tele })
    }

    @Test func annonceDeSaisonEtArriveeSurPlateforme() async throws {
        let conteneur = try preparer()
        let contexte = conteneur.mainContext
        let source = SourceSimulee()
        let service = ServiceAlertes(contexte: contexte)
        _ = try await service.calculer(source: source, reglages: ReglagesAlertes(), maintenant: midi)

        await source.annoncerSaison4()
        await source.changerPlateformes([119])
        let lendemain = midi.addingTimeInterval(86_400)
        let suivantes = corps(try await service.calculer(source: source, reglages: ReglagesAlertes(), maintenant: lendemain))
        #expect(suivantes.contains("La saison 4 arrive le 12 mars 2027"))
        #expect(suivantes.contains("Maintenant sur Prime Video"))

        // Recalcul une heure plus tard, avant l'envoi de 18 h : l'annonce reste programmée, une seule fois.
        let apres = corps(try await service.calculer(source: source, reglages: ReglagesAlertes(), maintenant: lendemain.addingTimeInterval(3600)))
        #expect(apres.filter { $0 == "La saison 4 arrive le 12 mars 2027" }.count == 1)
        // Après l'envoi, elle ne revient plus.
        let soir = corps(try await service.calculer(source: source, reglages: ReglagesAlertes(), maintenant: lendemain.addingTimeInterval(6 * 3600)))
        #expect(!soir.contains("La saison 4 arrive le 12 mars 2027"))
    }

    @Test func nouveauFilmDUnActeurSuivi() async throws {
        let conteneur = try preparer()
        let contexte = conteneur.mainContext
        try ServiceActeurs(contexte: contexte).suivre(personneID: 6384, nom: "Keanu Reeves", cheminPortrait: nil)
        try ServiceActeurs(contexte: contexte).suivre(personneID: 6384, nom: "Keanu Reeves", cheminPortrait: "/k.jpg")
        #expect(try contexte.fetchCount(FetchDescriptor<ActeurSuivi>()) == 1)

        let source = SourceSimulee()
        let service = ServiceAlertes(contexte: contexte)
        // Première lecture de la filmographie : rien à signaler.
        #expect(!corps(try await service.calculer(source: source, reglages: ReglagesAlertes(), maintenant: midi)).contains { $0.contains("Keanu") })

        await source.annoncerBallerina2()
        let suivantes = try await service.calculer(source: source, reglages: ReglagesAlertes(), maintenant: midi.addingTimeInterval(3600))
        let annonce = try #require(suivantes.first { $0.corps == "Nouveau film avec Keanu Reeves, sortie prévue le 4 juin 2027" })
        #expect(annonce.titre == "Ballerina 2")
        #expect(annonce.reference == ReferenceTitre(type: .film, tmdbID: 1))

        // Ne plus le suivre : plus de nouvelle alerte.
        try ServiceActeurs(contexte: contexte).nePlusSuivre(6384)
        #expect(try ServiceActeurs(contexte: contexte).suivi(6384) == nil)
    }

    @Test func clocheDesactiveeEtModeSaisons() async throws {
        let conteneur = try preparer()
        let contexte = conteneur.mainContext
        for suivi in try contexte.fetch(FetchDescriptor<Suivi>()) {
            if suivi.reference == heat { suivi.alertesActives = false }
            if suivi.reference == reacher { suivi.modeAlertes = .saisons }
        }
        try contexte.save()
        let notifications = try await ServiceAlertes(contexte: contexte).calculer(source: SourceSimulee(), reglages: ReglagesAlertes(), maintenant: midi)
        // Heat n'est plus surveillé ; Reacher en mode saisons ignore l'épisode 6.
        #expect(notifications.isEmpty)
    }
}
