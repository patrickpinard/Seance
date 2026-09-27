import SeanceDonnees
import SwiftData
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
    /// Appelée au lancement et chaque fois que la fenêtre devient large : un iPad lancé en portrait puis tourné, ou
    /// encore en train de pivoter au lancement, l'obtient aussi.
    /// Rend `true` quand il n'y a plus rien à tenter : barre ouverte, ou pas concerné (iPhone, Mac, barre refermée par
    /// choix, déjà ouverte cette session). `false` : pas encore de contrôleur, ou fenêtre pas (encore) assez large.
    @MainActor
    @discardableResult
    static func ouvrirSurIPad() -> Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        // Une seule fois par session : ensuite, la barre est à l'utilisateur, qui l'ouvre et la ferme comme il veut.
        guard !ouverteCetteSession, UIDevice.current.userInterfaceIdiom == .pad,
              !UserDefaults.standard.bool(forKey: cleMasqueeIPad) else { return true }
        guard let controleur = controleurOnglets(), tientACote(controleur) else { return false }
        controleur.sidebar.isHidden = false
        ouverteCetteSession = true
        return true
        #endif
    }

    /// Au lancement, le contrôleur d'onglets n'existe pas tout de suite ; pendant une rotation, la fenêtre change de
    /// taille en cours de route. Plutôt qu'un essai unique à heure fixe, on réessaie quelques fois, pendant trois
    /// secondes, et on s'arrête dès que c'est fait ou sans objet.
    @MainActor
    static func ouvrirSurIPadDesQuePossible() async {
        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(400))
            if ouvrirSurIPad() { return }
        }
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
    @MainActor private static var ouverteCetteSession = false

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
            // À côté des boutons de la fenêtre, à hauteur du menu : l'app, et qui regarde quand la maison a plusieurs profils.
            scene.title = QuiRegardeActuel.nom.map { "Séance · \($0)" } ?? "Séance"
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

    /// En tête de la barre de chaque onglet : le portrait des Préférences (7.0) et, quand la maison a plusieurs profils,
    /// qui regarde. (Le bouton du menu de gauche, qui donnait son nom au modificateur, a disparu en 5.1.)
    func boutonBarreLaterale(preferences: Bool = true, reglages: Bool = true) -> some View {
        modifier(PastilleQuiRegardeModifier(preferences: preferences, reglages: reglages))
    }
}

/// Qui regarde, en ce moment (Famille) : `nil` tant que la maison n'a qu'un profil — inutile de le dire.
@MainActor
enum QuiRegardeActuel {
    static var nom: String? {
        let famille = ProfilsFamille()
        guard famille.aPlusieursProfils else { return nil }
        let actif = famille.actif
        if !actif.prenom.isEmpty { return actif.prenom }
        return Prenom.lire() ?? "Moi"
    }

    /// Le nom d'une personne de la famille, tel que « Qui regarde ? » le montre.
    static func nomDe(_ profil: ProfilFamille) -> String {
        ProfilFamille.nomAffiche(profil, actif: ProfilsFamille().actif, prenomDeLAppareil: UserDefaults.standard.string(forKey: Prenom.cle) ?? "")
    }
}

/// En haut de chaque page (7.0) : à gauche, un seul bonhomme avec ton prénom, qui ouvre les Préférences (changer de
/// personne s'y fait aussi) ; à droite, la roue dentée des Réglages, sur tous les appareils.
private struct PastilleQuiRegardeModifier: ViewModifier {
    let preferences: Bool
    let reglages: Bool
    @Environment(EtatApp.self) private var etat
    @Query(filter: #Predicate<AlertePlanifiee> { $0.envoyee }) private var envoyees: [AlertePlanifiee]
    @AppStorage(AlertesALire.cleEffaceesAvant) private var effaceesAvant: Double = 0
    @AppStorage(AlertesALire.cleEffacees) private var effaceesBrut = ""
    @AppStorage(AlertesALire.cleLuesAvant) private var luesAvant: Double = 0
    @AppStorage(AlertesALire.cleLues) private var luesBrut = ""

    private var nonLues: Int {
        AlertesALire.recues(envoyees, effaceesAvant: effaceesAvant, effacees: effaceesBrut)
            .filter { !AlertesALire.estLue($0, luesAvant: luesAvant, lues: luesBrut) }.count
    }

    private var nom: String? {
        QuiRegardeActuel.nom ?? Prenom.lire()
    }

    private var portrait: some View {
        HStack(spacing: 6) {
            Image(systemName: ProfilsFamille().actif.symbole == "person.fill" ? "person.crop.circle" : ProfilsFamille().actif.symbole)
            if let nom { Text(nom).lineLimit(1) }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.accentClair)
        .padding(.horizontal, 6)
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                if preferences {
                    ToolbarItem(placement: .topBarLeading) {
                        // Pas un `Label` : dans la barre d'iOS 26, il se réduit à son icône et le prénom disparaît.
                        // Sur le Mac (8.2.13), une page poussée ici même : une feuille y devient une fenêtre à part.
                        Group {
                            if EtatApp.enPages {
                                NavigationLink(value: PagePreferences()) { portrait }
                            } else {
                                Button { etat.preferencesOuvertes = true } label: { portrait }
                            }
                        }
                        .help("Préférences : tes goûts, tes notes, tes statistiques")
                        .accessibilityLabel(nom.map { "Préférences de \($0)" } ?? "Préférences")
                        .accessibilityIdentifier("preferences")
                    }
                }
                // Les alertes à lire (8.2.14) : un bouton à part, à côté de la roue, avec leur nombre en pastille.
                if reglages, nonLues > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: DestinationReglage.alertesRecues) {
                            Image(systemName: "bell.fill")
                                .overlay(alignment: .topTrailing) {
                                    Text(nonLues > 99 ? "99+" : "\(nonLues)")
                                        .font(.caption2.weight(.heavy))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 4)
                                        .frame(minWidth: 16, minHeight: 16)
                                        .background(Theme.accent, in: Capsule())
                                        .offset(x: 9, y: -8)
                                }
                        }
                        .help("Alertes à lire")
                        .accessibilityLabel(Format.pluriel(nonLues, "alerte à lire", "alertes à lire"))
                        .accessibilityIdentifier("alertesALire")
                    }
                }
                if reglages {
                    ToolbarItem(placement: .topBarTrailing) {
                        Group {
                            // Sur le Mac (8.2.13) et l'iPad (8.2.17), une page poussée ici même, en deux colonnes.
                            if EtatApp.enPages {
                                NavigationLink(value: PageReglagesMac()) { Image(systemName: "gearshape") }
                            } else {
                                Button { etat.ongletDemande = .reglages } label: { Image(systemName: "gearshape") }
                            }
                        }
                        .help("Réglages")
                        .accessibilityLabel("Réglages")
                        .accessibilityIdentifier("reglages")
                    }
                }
            }
            .onAppear { TitreFenetre.retablir() }
    }
}
