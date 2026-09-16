import SeanceKit
import SwiftUI

/// État partagé par tous les écrans : le client TMDB, présent seulement si une clé est enregistrée.
@MainActor
@Observable
final class EtatApp {
    private(set) var tmdb: TMDBClient?
    /// Fiche demandée par un lien profond ; l'accueil l'ouvre puis remet la demande à zéro.
    var ficheDemandee: ReferenceTitre?
    let depot = DepotCles()

    init() {
        #if DEBUG
        // Développement : `SIMCTL_CHILD_SEANCE_CLE_TMDB=… xcrun simctl launch …` enregistre la clé
        // dans le trousseau du simulateur, sans qu'elle soit écrite dans le code ni dans le dépôt.
        if let cle = ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"], (try? depot.coffre.lire(.tmdb)) == nil {
            try? depot.coffre.enregistrer(cle, pour: .tmdb)
        }
        #endif
        tmdb = try? depot.client()
    }

    /// Teste la clé contre TMDB avant de l'enregistrer : une clé refusée ne remplace pas la précédente.
    func enregistrerCle(_ texte: String) async throws {
        let propre = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = TMDBClient(identifiants: .depuis(propre))
        _ = try await client.genres(.film)
        try depot.coffre.enregistrer(propre, pour: .tmdb)
        tmdb = client
    }

    func supprimerCle() throws {
        try depot.coffre.supprimer(.tmdb)
        tmdb = nil
    }
}
