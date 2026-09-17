import SeanceDonnees
import SwiftData
import SwiftUI

@main
struct SeanceApp: App {
    private let conteneur = ConteneurApp.resultat
    @State private var etat = EtatApp()

    var body: some Scene {
        WindowGroup {
            switch conteneur {
            case .success(let conteneur):
                RacineView()
                    .environment(etat)
                    .modelContainer(conteneur)
                    .preferredColorScheme(.dark)
            case .failure(let erreur):
                ContentUnavailableView(
                    "Données inaccessibles",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(erreur.localizedDescription)
                )
            }
        }
        // Mac : Séance › Réglages… (⌘,) ouvre l'onglet Réglages.
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Réglages…") { etat.ongletDemande = .reglages }
                    .keyboardShortcut(",")
            }
            #if targetEnvironment(macCatalyst)
            CommandGroup(replacing: .sidebar) {
                Button("Afficher ou masquer la barre latérale") { BarreLaterale.basculer() }
                    .keyboardShortcut("s", modifiers: [.control, .command])
            }
            #endif
        }
        // Réveil accordé par iOS de temps en temps : les alertes restent à jour sans ouvrir l'app.
        .backgroundTask(.appRefresh(EtatAlertes.tacheFond)) {
            guard case .success(let conteneur) = conteneur else { return }
            await etat.rafraichirEnFond(conteneur: conteneur)
        }
    }
}
