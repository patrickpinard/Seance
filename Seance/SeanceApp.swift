import SeanceDonnees
import SwiftData
import SwiftUI

@main
struct SeanceApp: App {
    @State private var conteneur = ConteneurApp.resultat
    @State private var etat = EtatApp()
    /// Change avec le profil de la famille : tous les écrans se reconstruisent sur le nouveau magasin.
    @State private var generation = 0
    @AppStorage(Apparence.cle) private var apparence = Apparence.sombre.rawValue

    var body: some Scene {
        WindowGroup {
            switch conteneur {
            case .success(let conteneur):
                RacineView()
                    .id(generation)
                    .environment(etat)
                    .modelContainer(conteneur)
                    .onReceive(NotificationCenter.default.publisher(for: .profilChange)) { _ in
                        self.conteneur = ConteneurApp.resultat
                        etat = EtatApp()
                        generation += 1
                    }
                    .preferredColorScheme(Apparence.lire(apparence).schema)
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
            // ⌘1 à ⌘6 pour les onglets, ⌘F pour chercher : au clavier du Mac comme de l'iPad.
            CommandMenu("Aller") {
                Button("Accueil") { etat.ongletDemande = .accueil }.keyboardShortcut("1")
                Button("Ce soir") { etat.ongletDemande = .ceSoir }.keyboardShortcut("2")
                Button("Mes listes") { etat.ongletDemande = .listes }.keyboardShortcut("3")
                Button("Préférences") { etat.ongletDemande = .profil }.keyboardShortcut("4")
                Button("Réglages") { etat.ongletDemande = .reglages }.keyboardShortcut("5")
                Button("Explorer") { etat.ongletDemande = .explorer }.keyboardShortcut("6")
                Divider()
                Button("Rechercher un film, une série, un acteur") { etat.rechercheDemandee = true }.keyboardShortcut("f")
                // ⌘[ : revenir en arrière, comme partout sur le Mac. Il manquait (parcours du 23 septembre).
                Button("Retour") { etat.retourDemande += 1 }.keyboardShortcut("[", modifiers: .command)
            }
        }
        // Réveil accordé par iOS de temps en temps : les alertes restent à jour sans ouvrir l'app.
        .backgroundTask(.appRefresh(EtatAlertes.tacheFond)) {
            guard let conteneur = await MainActor.run(body: { ConteneurApp.conteneur }) else { return }
            await etat.rafraichirEnFond(conteneur: conteneur)
        }
    }
}
