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

    #endif

    /// Sur l'iPad, la barre d'onglets du haut ne montre que trois onglets : Profil et Réglages se cachent derrière « > ».
    /// La barre latérale, ouverte au lancement, les montre tous — mais seulement quand elle tient **à côté** de la page
    /// (iPad en paysage). En portrait, le système la pose par-dessus le contenu : ouverte d'office, elle masquerait
    /// l'accueil à chaque lancement. Et si tu l'as refermée en paysage, elle le reste, comme sur le Mac.
    @MainActor
    static func ouvrirSurIPad() {
        #if !targetEnvironment(macCatalyst)
        guard UIDevice.current.userInterfaceIdiom == .pad, !UserDefaults.standard.bool(forKey: cleMasqueeIPad),
              let controleur = controleurOnglets(), tientACote(controleur) else { return }
        controleur.sidebar.isHidden = false
        #endif
    }

    /// En quittant l'app : retient si la barre était refermée. En portrait elle l'est presque toujours (elle se referme
    /// dès qu'on choisit un onglet) : cela ne dit rien du choix de l'utilisateur, on ne retient donc rien.
    @MainActor
    static func retenirSurIPad() {
        #if !targetEnvironment(macCatalyst)
        guard UIDevice.current.userInterfaceIdiom == .pad, let controleur = controleurOnglets(), tientACote(controleur) else { return }
        UserDefaults.standard.set(controleur.sidebar.isHidden, forKey: cleMasqueeIPad)
        #endif
    }

    #if !targetEnvironment(macCatalyst)
    private static let cleMasqueeIPad = "ipad.barreLaterale.masquee"

    /// UIKit ne dit pas si la barre se posera à côté ou par-dessus ; il en décide à la largeur. Plus large que haute et
    /// au moins 1000 points : tous les iPad en paysage plein écran, pas en portrait ni en demi-écran.
    @MainActor
    private static func tientACote(_ controleur: UITabBarController) -> Bool {
        let taille = controleur.view.bounds.size
        return taille.width >= 1000 && taille.width > taille.height
    }
    #endif

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
