import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Les onglets de la TV, en haut de l'écran : on y monte d'un geste, comme dans les apps d'Apple.
struct RacineTV: View {
    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Environment(\.scenePhase) private var phase

    @State private var onglet = DepartTV.onglet
    /// Un chemin générique : typé « titres seulement », il refusait en silence la fiche d'un acteur — choisir un visage
    /// du casting ne faisait rien depuis l'accueil ou l'étagère du haut (trouvé par `TelecommandeTests`, 6.0).
    @State private var cheminAccueil: NavigationPath = {
        var chemin = NavigationPath()
        if let fiche = DepartTV.fiche { chemin.append(fiche) }
        return chemin
    }()
    @State private var configuration = DepartTV.configurer

    var body: some View {
        TabView(selection: $onglet) {
            // Des noms seuls, sans icône, comme Netflix : les huit entrées tiennent ainsi sur une ligne, sans défiler.
            Tab(value: OngletTV.accueil) {
                NavigationStack(path: $cheminAccueil) {
                    AccueilTV().sousLaPastille().background { FondTV() }.navigationDestination(for: ReferenceTitre.self) { FicheTV(reference: $0).pageOuverte() }
                        .navigationDestination(for: PersonneTVRef.self) { PersonneTV(personne: $0).pageOuverte() }
                }
            } label: { Text("Accueil") }
            Tab(value: OngletTV.ceSoir) { pile { CeSoirTV() } } label: { Text("Ce soir") }
            Tab(value: OngletTV.listes) { pile { ListesTV() } } label: { Text("Mes listes") }
            Tab(value: OngletTV.explorer) { pile { ExplorerTV() } } label: { Text("Explorer") }
            Tab(value: OngletTV.tele) { pile { TeleTV() } } label: { Text("TV") }
            Tab(value: OngletTV.nas) { pile { NASTV() } } label: { Text("NAS") }
            Tab(value: OngletTV.profil) { pile { ProfilTV() } } label: { Text("Préférences") }
            // Les réglages : une roue dentée tout à droite, plutôt qu'un mot de plus dans le menu. Elle reste dans la barre :
            // un bouton posé par-dessus flotterait quand la barre se replie, et la télécommande s'y perdrait.
            Tab(value: OngletTV.reglages) { pile { ReglagesTV() } } label: {
                Image(systemName: "gearshape.fill").accessibilityLabel("Réglages")
            }
        }
        // Le menu en haut, à l'horizontale, comme Netflix (demande de Patrick, 20 septembre 2026) : la barre d'onglets
        // de tvOS, qui se replie quand on descend dans la page et revient quand on remonte.
        .tabViewStyle(.tabBarOnly)
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
        .fullScreenCover(isPresented: $configuration) { ConfigurationTV() }
        // Une affiche de l'étagère du haut : `seance://film/603` ouvre sa fiche.
        .onOpenURL { url in
            guard url.scheme == "seance", let hote = url.host(), let type = TypeTitre(rawValue: hote), let id = Int(url.lastPathComponent) else { return }
            onglet = .accueil
            cheminAccueil = NavigationPath([ReferenceTitre(type: type, tmdbID: id)])
        }
        // Retour de l'app de lecture : « Tu l'as regardé ? » (EF-118, sur la TV).
        .onChange(of: phase) { _, nouvelle in
            if nouvelle == .active {
                etat.revenir()
                Task { await etat.synchroniser(contexte: contexte) }
            }
            // En quittant l'app : ce qui a été fait ici part vers les autres appareils.
            if nouvelle == .background { Task { await etat.synchroniser(contexte: contexte) } }
            // En quittant l'app : l'étagère du haut reflète la soirée et le NAS du moment.
            if nouvelle == .background { PublicationEtagere.publier(contexte: contexte) }
        }
        .alert("Tu l'as regardé ?", isPresented: Binding { etat.lectureAConfirmer != nil } set: { if !$0 { etat.lectureAConfirmer = nil } },
               presenting: etat.lectureAConfirmer) { reference in
            Button("Oui, marquer vu") { marquerVu(reference) }
            Button("Pas encore", role: .cancel) {}
        } message: { _ in
            Text("Séance le range dans tes films vus ; tu pourras le noter depuis sa fiche.")
        }
        // La bibliothèque du NAS se relit au lancement : le magasin de la TV est un cache (EF-145).
        .task {
            // Les listes d'abord (quelques secondes), la bibliothèque ensuite (plus longue).
            await etat.synchroniser(contexte: contexte)
            if etat.nasPret, !etat.enDemonstration { await etat.analyserNAS(contexte: contexte) }
            PublicationEtagere.publier(contexte: contexte)
        }
    }

    private func marquerVu(_ reference: ReferenceTitre) {
        Task {
            guard let film = try? await etat.tmdb?.film(reference.tmdbID) else { return etat.dire("TMDB ne répond pas : marque-le vu depuis sa fiche.") }
            try? ServiceSuivi(contexte: contexte).marquerVu(film: film)
            try? ServiceSoiree(contexte: contexte).retirer(reference)
            etat.dire("« \(film.titre) » marqué vu")
        }
    }

    /// Chaque onglet a sa pile : toute affiche ouvre la fiche du titre, par valeur.
    private func pile(@ViewBuilder _ contenu: () -> some View) -> some View {
        NavigationStack {
            contenu()
                .sousLaPastille()
                .background { FondTV() }
                .navigationDestination(for: ReferenceTitre.self) { FicheTV(reference: $0).pageOuverte() }
                .navigationDestination(for: PersonneTVRef.self) { PersonneTV(personne: $0).pageOuverte() }
                .navigationDestination(for: DossierVideosTV.self) { VideosPersoTV(chemin: $0.chemin).pageOuverte() }
        }
    }
}

enum OngletTV: String, Hashable {
    case accueil, ceSoir, listes, explorer, tele, nas, profil, reglages
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

    /// `SEANCE_TV_CONFIGURER=1` ouvre l'écran du code au lancement, `SEANCE_TV_CODE=424242` impose le code : pour le test
    /// de bout en bout avec le simulateur d'iPhone (`EnvoiAppleTVTests`).
    static var configurer: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["SEANCE_TV_CONFIGURER"] != nil
        #else
        return false
        #endif
    }

    static var codeImpose: String? {
        #if DEBUG
        return ProcessInfo.processInfo.environment["SEANCE_TV_CODE"]
        #else
        return nil
        #endif
    }

    /// `SEANCE_TV_REGLAGE=nas` ouvre droit une page de réglage, pour la relire en capture.
    static var reglage: String? {
        #if DEBUG
        return ProcessInfo.processInfo.environment["SEANCE_TV_REGLAGE"]
        #else
        return nil
        #endif
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

extension View {
    /// Le menu est en haut de l'écran : les pages
    /// commencent un peu plus bas, pour que leur premier titre respire sous la barre.
    func sousLaPastille() -> some View {
        safeAreaPadding(.top, 40)
    }
}
