import SeanceKit
import SwiftUI

/// Barre d'onglets (UX, navigation) : Explorer est l'onglet de recherche d'iOS 26, en rond séparé.
struct RacineView: View {
    @Environment(EtatApp.self) private var etat
    @State private var onglet = "accueil"

    var body: some View {
        TabView(selection: $onglet) {
            Tab("Accueil", systemImage: "house.fill", value: "accueil") {
                AccueilView()
            }
            Tab("Ce soir", systemImage: "sparkles", value: "ceSoir") {
                CeSoirView()
            }
            Tab("Mes listes", systemImage: "bookmark", value: "listes") {
                MesListesView()
            }
            Tab("Moi", systemImage: "person", value: "moi") {
                MoiView()
            }
            Tab("Explorer", systemImage: "magnifyingglass", value: "explorer", role: .search) {
                ExplorerView()
            }
        }
        .tint(Theme.accent)
        .onOpenURL { url in
            guard let reference = LienProfond.reference(url) else { return }
            onglet = "accueil"
            etat.ficheDemandee = reference
        }
    }
}

/// Destination commune : toucher une affiche ouvre sa fiche (UX-10).
extension View {
    func destinationsTitres() -> some View {
        navigationDestination(for: ReferenceTitre.self) { reference in
            FicheView(reference: reference)
        }
    }
}
