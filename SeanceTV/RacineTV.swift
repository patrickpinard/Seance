import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Les onglets de la TV, en haut de l'écran : on y monte d'un geste, comme dans les apps d'Apple.
struct RacineTV: View {
    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte

    @State private var onglet = DepartTV.onglet
    @State private var cheminAccueil = DepartTV.fiche.map { [$0] } ?? []

    var body: some View {
        TabView(selection: $onglet) {
            Tab("Accueil", systemImage: "house.fill", value: OngletTV.accueil) {
                NavigationStack(path: $cheminAccueil) {
                    AccueilTV().navigationDestination(for: ReferenceTitre.self) { FicheTV(reference: $0) }
                }
            }
            Tab("Ce soir", systemImage: "moon.stars.fill", value: OngletTV.ceSoir) { pile { CeSoirTV() } }
            Tab("Mes listes", systemImage: "bookmark.fill", value: OngletTV.listes) { pile { ListesTV() } }
            Tab("NAS", systemImage: "externaldrive.fill", value: OngletTV.nas) { pile { NASTV() } }
            Tab("Réglages", systemImage: "gearshape.fill", value: OngletTV.reglages) { pile { ReglagesTV() } }
        }
        .background(Theme.fond.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if let message = etat.message {
                Text(message)
                    .font(.system(size: 28, weight: .semibold))
                    .padding(.horizontal, 36)
                    .padding(.vertical, 18)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 60)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: etat.message)
        // La bibliothèque du NAS se relit au lancement : le magasin de la TV est un cache (EF-145).
        .task {
            if etat.nasPret, !etat.enDemonstration { await etat.analyserNAS(contexte: contexte) }
        }
    }

    /// Chaque onglet a sa pile : toute affiche ouvre la fiche du titre, par valeur.
    private func pile(@ViewBuilder _ contenu: () -> some View) -> some View {
        NavigationStack {
            contenu()
                .navigationDestination(for: ReferenceTitre.self) { FicheTV(reference: $0) }
        }
    }
}

enum OngletTV: String, Hashable {
    case accueil, ceSoir, listes, nas, reglages
}

/// Où l'app s'ouvre. Toujours l'accueil — sauf dans une version de test, où `SEANCE_TV_ONGLET=nas` ou
/// `SEANCE_TV_FICHE=film:245891` mènent droit à un écran : la télécommande du simulateur ne se pilote pas en ligne
/// de commande, et il faut bien relire chaque écran.
enum DepartTV {
    static var onglet: OngletTV {
        #if DEBUG
        if let demande = ProcessInfo.processInfo.environment["SEANCE_TV_ONGLET"], let onglet = OngletTV(rawValue: demande) { return onglet }
        #endif
        return .accueil
    }

    static var fiche: ReferenceTitre? {
        #if DEBUG
        let morceaux = (ProcessInfo.processInfo.environment["SEANCE_TV_FICHE"] ?? "").split(separator: ":")
        if morceaux.count == 2, let type = TypeTitre(rawValue: String(morceaux[0])), let id = Int(morceaux[1]) {
            return ReferenceTitre(type: type, tmdbID: id)
        }
        #endif
        return nil
    }
}
