import CoreSpotlight
import Foundation
import SeanceDonnees
import SeanceKit
import SwiftData

/// Tes titres dans la recherche du système (Séance 6.0) : « Reacher » tapé dans Spotlight ouvre sa fiche dans Séance.
/// Seuls les titres de tes listes y entrent — ceux du profil actif de la famille —, sans rien envoyer nulle part :
/// l'index de Spotlight reste sur l'appareil.
@MainActor
enum IndexSpotlight {
    private static let domaine = "ch.patrick.seance.titres"

    /// Refait l'index : tes listes sont courtes, et un titre retiré doit en sortir.
    static func actualiser(contexte: ModelContext) {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        #if DEBUG
        // L'index est celui de la vraie app : la démonstration du Mac n'y met pas ses titres fictifs.
        if Demonstration.coupeeDuMonde { return }
        #endif
        let suivis = ((try? contexte.fetch(FetchDescriptor<Suivi>())) ?? []).filter { $0.statut != .exclu && !$0.titre.isEmpty }
        let elements = suivis.map { suivi -> CSSearchableItem in
            let attributs = CSSearchableItemAttributeSet(contentType: .content)
            attributs.title = suivi.titre
            attributs.contentDescription = [suivi.type == .film ? "Film" : "Série", libelle(suivi.statut), suivi.note.map { "★ \($0)/10" },
                                            suivi.acteursPrincipaux.prefix(3).joined(separator: ", ")]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            attributs.keywords = ["Séance"] + suivi.acteursPrincipaux
            return CSSearchableItem(uniqueIdentifier: "seance://\(suivi.type.rawValue)/\(suivi.tmdbID)", domainIdentifier: domaine, attributeSet: attributs)
        }
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domaine]) { _ in
            index.indexSearchableItems(elements) { _ in }
        }
    }

    /// Le titre touché dans Spotlight.
    static func reference(_ activite: NSUserActivity) -> ReferenceTitre? {
        guard activite.activityType == CSSearchableItemActionType,
              let identifiant = activite.userInfo?[CSSearchableItemActivityIdentifier] as? String, let url = URL(string: identifiant) else { return nil }
        return LienProfond.reference(url)
    }

    private static func libelle(_ statut: StatutSuivi) -> String {
        switch statut {
        case .aVoir: "À voir"
        case .enCours: "En cours"
        case .termine: "Terminé"
        case .exclu: ""
        }
    }
}
