import Foundation
import SeanceDonnees
import SeanceKit
import SwiftData
import WidgetKit

/// Prépare ce que les widgets ne peuvent pas lire seuls : les prochains épisodes des séries en cours,
/// qui demandent TMDB. Ma soirée et À venir, eux, sont lus directement dans le magasin partagé.
@MainActor
enum PublicationWidgets {
    private static var derniere: Date?
    private static var seriesPubliees: Set<Int> = []

    /// Recalcule la liste des prochains épisodes, au plus une fois par demi-heure sauf `force`.
    static func actualiser(contexte: ModelContext, tmdb: TMDBClient?, force: Bool = false) async {
        guard let tmdb, let dossier = EntrepotSeance.dossierPartage else { return }
        #if DEBUG
        if Demonstration.active { return }
        #endif
        let suivis = (try? contexte.fetch(FetchDescriptor<Suivi>())) ?? []
        let series = suivis.filter { $0.type == .serie && $0.statut == .enCours }.prefix(12)
        // Une série commencée ou terminée depuis la dernière fois passe outre le délai.
        let identifiants = Set(series.map(\.tmdbID))
        if !force, identifiants == seriesPubliees, let derniere, Date.now.timeIntervalSince(derniere) < 30 * 60 { return }
        derniere = .now
        seriesPubliees = identifiants
        let suivi = ServiceSuivi(contexte: contexte)
        let vus = Dictionary(series.map { ($0.tmdbID, (try? suivi.episodesVus($0.reference)) ?? []) }, uniquingKeysWith: { premier, _ in premier })
        let affiches = Dictionary(series.map { ($0.tmdbID, $0.cheminAffiche) }, uniquingKeysWith: { premier, _ in premier })
        let aujourdhui = DateTMDB(.now, fuseau: .suisse)

        let resultat = await withTaskGroup(of: InstantaneWidgets.Serie?.self) { groupe in
            for (id, dejaVus) in vus {
                let affiche = affiches[id] ?? nil
                groupe.addTask {
                    await serie(id, vus: dejaVus, affiche: affiche, aujourdhui: aujourdhui, client: tmdb)
                }
            }
            var series: [InstantaneWidgets.Serie] = []
            while let serie = await groupe.next() {
                if let serie { series.append(serie) }
            }
            return series.sorted { $0.nom < $1.nom }
        }

        try? InstantaneWidgets(series: resultat).ecrire(dossier: dossier)
        recharger()
    }

    /// Les widgets relisent le magasin : après une soirée modifiée, un épisode coché, des alertes recalculées.
    static func recharger() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    nonisolated private static func serie(
        _ id: Int, vus: Set<NumeroEpisode>, affiche: String?, aujourdhui: DateTMDB, client: TMDBClient
    ) async -> InstantaneWidgets.Serie? {
        guard let detail = try? await client.serie(id),
              let prochain = ProgressionSerie.suivant(vus: vus, saisons: detail.saisons, dernierDiffuse: detail.dernierEpisode),
              prochain.disponible,
              let saison = try? await client.saison(prochain.numero.saison, serie: id)
        else { return nil }
        let duree = detail.dureesEpisode.first ?? 45
        let episodes = InstantaneWidgets.episodes(saison.episodes, depuis: prochain.numero, aujourdhui: aujourdhui, dureeParDefaut: duree)
        guard !episodes.isEmpty else { return nil }
        return InstantaneWidgets.Serie(id: id, nom: detail.nom, cheminAffiche: affiche ?? detail.cheminAffiche, episodes: episodes)
    }
}
