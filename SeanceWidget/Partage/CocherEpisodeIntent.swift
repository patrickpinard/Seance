import AppIntents
import SeanceDonnees
import SeanceKit
import SwiftData
import WidgetKit

/// Le ✓ du widget « Prochains épisodes » : coche l'épisode sans ouvrir l'app.
struct CocherEpisodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Marquer un épisode comme vu"
    static let description = IntentDescription("Coche un épisode d'une série suivie dans Séance.")
    static let isDiscoverable = false

    @Parameter(title: "Série") var serieID: Int
    @Parameter(title: "Saison") var saison: Int
    @Parameter(title: "Épisode") var episode: Int
    @Parameter(title: "Durée en minutes") var dureeMinutes: Int

    init() {}

    init(_ prochain: EpisodeWidget) {
        serieID = prochain.serieID
        saison = prochain.saison
        episode = prochain.numero
        dureeMinutes = prochain.dureeMinutes
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let conteneur = ConteneurPartage.conteneur else { return .result() }
        try ServiceSuivi(contexte: conteneur.mainContext).cocher(
            NumeroEpisode(saison: saison, episode: episode),
            serie: ReferenceTitre(type: .serie, tmdbID: serieID),
            dureeMinutes: dureeMinutes
        )
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
