import SeanceDonnees
import SwiftData
import SwiftUI

@main
struct SeanceApp: App {
    @UIApplicationDelegateAdaptor(DelegueApp.self) private var delegue
    @State private var conteneur = ConteneurApp.resultat
    @State private var etat = EtatApp()
    /// Change avec le profil de la famille : tous les écrans se reconstruisent sur le nouveau magasin.
    @State private var generation = 0

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
                    .preferredColorScheme(.dark)
            case .failure(let erreur):
                ContentUnavailableView(
                    "Données inaccessibles",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(erreur.localizedDescription)
                )
            }
        }
        // Mac : Séance › Réglages… (⌘,) ouvre les Réglages, comme la roue dentée de chaque page.
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Réglages…") { etat.ongletDemande = .reglages }
                    .keyboardShortcut(",")
            }
            // ⌘1 à ⌘3 pour les onglets, dans l'ordre du menu (8.0), ⌘F pour chercher : au clavier du Mac comme de l'iPad.
            CommandMenu("Aller") {
                Button("Accueil") { etat.ongletDemande = .accueil }.keyboardShortcut("1")
                Button("Regarder") { etat.ongletDemande = .regarder }.keyboardShortcut("2")
                Button("Mes listes") { etat.ongletDemande = .listes }.keyboardShortcut("3")
                Divider()
                Button("Ce soir") { etat.ongletDemande = .ceSoir }.keyboardShortcut("4")
                Button("Streaming") { etat.ongletDemande = .streaming }.keyboardShortcut("5")
                Button("TV") { etat.ongletDemande = .tele }.keyboardShortcut("6")
                Button("NAS") { etat.ongletDemande = .nas }.keyboardShortcut("7")
                Divider()
                Button("Préférences") { etat.ongletDemande = .profil }.keyboardShortcut("9")
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

/// Les orientations permises (7.0) : l'iPhone reste en portrait, sauf pendant la lecture d'une vidéo, qui se regarde
/// aussi à l'horizontale ; l'iPad et le Mac tournent librement.
final class DelegueApp: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Le jour et l'heure d'arrivée de cette version (8.1), pour À propos › Versions.
        InstallationsVersions.noter()
        // Comment s'est terminée la séance précédente (8.2) : un arrêt brusque va dans Réglages › Journal.
        Plantages.demarrer()
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated {
            guard UIDevice.current.userInterfaceIdiom == .phone else { return .all }
            return OrientationLecture.ouverte ? .allButUpsideDown : .portrait
        }
    }
}

/// Le lecteur ouvert laisse tourner l'iPhone ; refermé, retour au portrait.
@MainActor
enum OrientationLecture {
    static var ouverte = false

    /// 8.2.7 (demande de Patrick) : le lecteur s'ouvre dans l'orientation du moment, sans basculer d'office à
    /// l'horizontale ; il suit ensuite l'iPhone si on le tourne.
    static func ouvrir() { changer(ouverte: true, vers: nil) }
    static func fermer() { changer(ouverte: false, vers: .portrait) }

    private static func changer(ouverte: Bool, vers orientation: UIInterfaceOrientationMask?) {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        Self.ouverte = ouverte
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for fenetre in scene.windows {
                fenetre.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                var presente = fenetre.rootViewController?.presentedViewController
                while let vue = presente {
                    vue.setNeedsUpdateOfSupportedInterfaceOrientations()
                    presente = vue.presentedViewController
                }
            }
            if let orientation { scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { _ in } }
        }
    }
}
