import SwiftUI

/// Sur le Mac, le menu de gauche se masque pour laisser toute la place à la page : bouton dans la barre de chaque
/// onglet et commande Présentation › Masquer la barre latérale (⌃⌘S). Le choix est gardé d'un lancement à l'autre.
/// SwiftUI ne donne pas la main sur cette barre : c'est celle du `UITabBarController` qui porte le `TabView`.
enum BarreLaterale {
    private static let cleMasquee = "mac.barreLaterale.masquee"

    #if targetEnvironment(macCatalyst)
    @MainActor
    static func basculer() {
        guard let controleur = controleurOnglets() else { return }
        let masquee = !controleur.sidebar.isHidden
        controleur.sidebar.isHidden = masquee
        UserDefaults.standard.set(masquee, forKey: cleMasquee)
    }

    /// Au lancement : la barre reprend l'état choisi la dernière fois.
    @MainActor
    static func restaurer() {
        guard UserDefaults.standard.bool(forKey: cleMasquee), let controleur = controleurOnglets() else { return }
        controleur.sidebar.isHidden = true
    }

    @MainActor
    private static func controleurOnglets() -> UITabBarController? {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for fenetre in scene.windows {
                if let trouve = chercher(fenetre.rootViewController) { return trouve }
            }
        }
        return nil
    }

    @MainActor
    private static func chercher(_ controleur: UIViewController?) -> UITabBarController? {
        guard let controleur else { return nil }
        if let onglets = controleur as? UITabBarController, onglets.mode != .tabBar { return onglets }
        for enfant in controleur.children {
            if let trouve = chercher(enfant) { return trouve }
        }
        return chercher(controleur.presentedViewController)
    }
    #endif
}

/// Sur le Mac, le titre d'une feuille (« Personnaliser l'accueil ») devenait celui de la fenêtre et y restait.
/// Les feuilles portent leur titre dans leur barre, et la fenêtre reprend « Séance » à leur fermeture.
enum TitreFenetre {
    @MainActor
    static func retablir() {
        #if targetEnvironment(macCatalyst)
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.title = "Séance"
        }
        #endif
    }
}

extension View {
    /// Titre d'une feuille, dans sa barre et pas dans celle de la fenêtre.
    func titreDeFeuille(_ titre: String) -> some View {
        toolbar {
            ToolbarItem(placement: .principal) {
                Text(titre).font(.headline)
            }
        }
        .onDisappear { TitreFenetre.retablir() }
    }

    /// Le bouton qui masque ou affiche le menu de gauche, en tête de la barre d'un onglet ; rien sur l'iPhone.
    func boutonBarreLaterale() -> some View {
        #if targetEnvironment(macCatalyst)
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { BarreLaterale.basculer() } label: {
                    Label("Barre latérale", systemImage: "sidebar.left")
                }
                .help("Masquer ou afficher le menu de gauche (⌃⌘S)")
            }
        }
        #else
        self
        #endif
    }
}
