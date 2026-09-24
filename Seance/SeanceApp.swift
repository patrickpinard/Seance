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
            // ⌘1 à ⌘9 pour les onglets, ⌘F pour chercher : au clavier du Mac comme de l'iPad.
            CommandMenu("Aller") {
                // Dans l'ordre du menu (7.0).
                Button("Accueil") { etat.ongletDemande = .accueil }.keyboardShortcut("1")
                Button("Ce soir") { etat.ongletDemande = .ceSoir }.keyboardShortcut("2")
                Button("Streaming") { etat.ongletDemande = .streaming }.keyboardShortcut("3")
                Button("TV") { etat.ongletDemande = .tele }.keyboardShortcut("4")
                Button("NAS") { etat.ongletDemande = .nas }.keyboardShortcut("5")
                Button("Mes listes") { etat.ongletDemande = .listes }.keyboardShortcut("6")
                Button("Réglages") { etat.ongletDemande = .reglages }.keyboardShortcut("7")
                Button("Explorer") { etat.ongletDemande = .explorer }.keyboardShortcut("8")
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
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated {
            guard UIDevice.current.userInterfaceIdiom == .phone else { return .all }
            return OrientationLecture.ouverte ? .allButUpsideDown : .portrait
        }
    }
}

/// Le lecteur ouvert laisse tourner l'iPhone, et se met de lui-même à l'horizontale ; refermé, retour au portrait.
@MainActor
enum OrientationLecture {
    static var ouverte = false

    static func ouvrir() { changer(ouverte: true, vers: .landscapeRight) }
    static func fermer() { changer(ouverte: false, vers: .portrait) }

    private static func changer(ouverte: Bool, vers orientation: UIInterfaceOrientationMask) {
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
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { _ in }
        }
    }
}
