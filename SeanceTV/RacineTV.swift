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
    /// « Lire sur l'Apple TV » (8.1) : la vidéo envoyée par un iPhone, lue par-dessus la page où l'on était.
    @State private var lectureRecue: LectureRecueTV? = {
        #if DEBUG
        if let fichier = ProcessInfo.processInfo.environment["SEANCE_LIRE_FICHIER"] {
            return LectureRecueTV(video: VideoPerso(chemin: fichier, taille: 0), acces: ReglagesNAS(), motDePasse: "", depart: nil, fichier: nil)
        }
        #endif
        return nil
    }()
    /// Famille : « Qui regarde ? » à l'ouverture, une fois par lancement, dès que la maison a plusieurs profils.
    @State private var quiRegarde = RacineTV.doitDemander
    private static var dejaDemande = false
    private static var doitDemander: Bool { !dejaDemande && ConteneurTV.famille.aPlusieursProfils && DepartTV.fiche == nil }

    var body: some View {
        TabView(selection: $onglet) {
            // 8.0, charte commune, la même barre que sur l'iPhone, l'iPad et le Mac : le portrait des Préférences, puis
            // Accueil, Regarder, Mes listes, la loupe de la recherche et la roue dentée des Réglages. Des noms seuls pour
            // les pages, des icônes pour le reste.
            Tab(value: OngletTV.profil) { pile { ProfilTV() } } label: {
                Image(systemName: "person.crop.circle").accessibilityLabel("Préférences")
            }
            Tab(value: OngletTV.accueil) {
                NavigationStack(path: $cheminAccueil) {
                    AccueilTV().sousLaPastille().background { FondTV() }.destinationsTV()
                }
                .environment(\.ouvrirTV, OuvrirTV { cheminAccueil.append($0) })
            } label: { Text("Accueil") }
            Tab(value: OngletTV.regarder) { pile { RegarderTV() } } label: { Text("Regarder") }
            Tab(value: OngletTV.listes) { pile { ListesTV() } } label: { Text("Mes listes") }
            Tab(value: OngletTV.explorer) { pile { RechercheTV() } } label: {
                Image(systemName: "magnifyingglass").accessibilityLabel("Recherche")
            }
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
        // Qui regarde, en haut à gauche, à la hauteur du menu : seulement quand la maison a plusieurs profils. C'est un
        // bouton (6.1) : à gauche de « Accueil », la télécommande l'atteint et rouvre « Qui regarde ? », comme sur l'iPad.
        .overlay(alignment: .topLeading) {
            if ConteneurTV.famille.aPlusieursProfils {
                let actif = ConteneurTV.famille.actif
                Button { quiRegarde = true } label: {
                    Label(QuiRegardeTV.nom(actif), systemImage: actif.symbole)
                }
                .buttonStyle(PastilleQuiRegardeTV())
                .padding(.leading, MargesTV.bord)
                .padding(.top, 52)
                .ignoresSafeArea()
                .accessibilityLabel("Qui regarde : \(QuiRegardeTV.nom(actif))")
                .accessibilityHint("Change de personne")
            }
        }
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
        .fullScreenCover(item: $lectureRecue) { recue in
            LecteurVLCTV(video: recue.video, acces: recue.acces, motDePasse: recue.motDePasse,
                         surEchec: { texte in etat.dire(texte) },
                         depart: recue.depart,
                         surPosition: { secondes, duree in etat.noterPosition(recue.video.chemin, secondes: secondes, duree: duree) },
                         fichier: recue.fichier,
                         surSuivant: { prochain in lectureRecue = LectureRecueTV(fichier: prochain, etat: etat) })
        }
        // Tant que Séance est ouverte, la TV écoute les iPhone de la maison.
        .task(id: phase == .active) {
            guard phase == .active else { return }
            // Lu ici, sur le fil principal : l'écoute tourne sur sa propre file. Relu à chaque retour dans l'app.
            let secret = etat.motDePasseDuNAS
            let recepteur = RecepteurLecture { secret }
            for await commande in recepteur.demarrer(nom: UIDevice.current.name) {
                recevoir(commande)
            }
        }
        .fullScreenCover(isPresented: $quiRegarde) {
            QuiRegardeTV { profil in
                Self.dejaDemande = true
                quiRegarde = false
                ConteneurTV.changerDeProfil(vers: profil)
            }
        }
        // Une affiche de l'étagère du haut : `seance://film/603` ouvre sa fiche.
        .onOpenURL { url in
            guard url.scheme == "seance", let hote = url.host(), let type = TypeTitre(rawValue: hote), let id = Int(url.lastPathComponent) else { return }
            onglet = .accueil
            cheminAccueil = NavigationPath([ReferenceTitre(type: type, tmdbID: id)])
        }
        // « Tout voir » d'une étagère de l'accueil : Regarder prend la demande et l'efface.
        // La page à l'écran, pour dire où Séance s'est arrêtée si elle s'arrête (8.2).
        .onChange(of: onglet, initial: true) { _, choisi in Plantages.page(String(describing: choisi).capitalized) }
        .onChange(of: etat.demandeRegarder) { _, demande in
            if demande != nil { onglet = .regarder }
        }
        // Retour de l'app de lecture : « Tu l'as regardé ? » (EF-118, sur la TV).
        .onChange(of: phase) { _, nouvelle in
            Plantages.enFond(nouvelle != .active)
            if nouvelle == .active {
                etat.revenir()
                Task { await etat.synchroniser(contexte: contexte) }
            }
            // En quittant l'app : ce qui a été fait ici part vers les autres appareils.
            if nouvelle == .background { Task { await etat.synchroniser(contexte: contexte) } }
            // En quittant l'app : l'étagère du haut reflète la soirée et le NAS du moment.
            if nouvelle == .background { PublicationEtagere.publier(contexte: contexte) }
        }
        // Une fenêtre de Séance plutôt que celle du système (6.3), toujours lisible sur la TV.
        .fullScreenCover(isPresented: Binding { etat.lectureAConfirmer != nil } set: { if !$0 { etat.lectureAConfirmer = nil } }) {
            if let lecture = etat.lectureAConfirmer {
                DialogueTV(titre: "As-tu regardé « \(lecture.libelle) » ?",
                           message: lecture.episode == nil ? "Séance le range dans tes films vus ; tu pourras le noter depuis sa fiche."
                                                           : "Séance coche cet épisode et passe au suivant.",
                           choix: [DialogueTV.Choix(libelle: "Oui, terminé", principal: true) { marquerVu(lecture) },
                                   DialogueTV.Choix(libelle: "Pas encore") {}])
            }
        }
        // « Qui regarde avec toi ? » (8.2) : après « Terminé », au retour d'une plateforme. Le lecteur la pose lui-même.
        .fullScreenCover(item: Binding { etat.lecteurOuvert ? nil : etat.avecQui } set: { if $0 == nil { etat.avecQui = nil } }) { demande in
            ChoixAvecQuiTV(moment: .apres(demande)) { etat.avecQui = nil }
        }
        // La bibliothèque du NAS se relit au lancement : le magasin de la TV est un cache (EF-145).
        .task {
            // Les listes d'abord (quelques secondes), la bibliothèque ensuite (plus longue).
            etat.relirePositions()
            etat.ou.actualiserLocal(contexte: contexte)
            await etat.synchroniser(contexte: contexte)
            etat.ou.actualiserLocal(contexte: contexte)
            if etat.nasPret, !etat.enDemonstration { await etat.analyserNAS(contexte: contexte) }
            etat.ou.actualiserLocal(contexte: contexte)
            PublicationEtagere.publier(contexte: contexte)
        }
    }

    /// Une vidéo envoyée par l'iPhone : un film ou un épisode de la bibliothèque, ou une vidéo personnelle.
    private func recevoir(_ commande: CommandeLecture) {
        if commande.souvenir {
            guard let motDePasse = etat.videosPerso.motDePasse(films: etat.nas) else { return etat.dire("Les vidéos personnelles ne sont pas réglées sur cette TV.") }
            lectureRecue = LectureRecueTV(video: VideoPerso(chemin: commande.chemin, taille: 0), acces: etat.videosPerso.reglages.acces,
                                          motDePasse: motDePasse, depart: commande.depart, fichier: nil)
        } else {
            let chemin = commande.chemin
            guard let fichier = try? contexte.fetch(FetchDescriptor<FichierNAS>(predicate: #Predicate { $0.chemin == chemin })).first else {
                return etat.dire("Cette vidéo n'est pas encore dans la bibliothèque de la TV : relance l'analyse du NAS.")
            }
            lectureRecue = LectureRecueTV(fichier: fichier, etat: etat, depart: commande.depart)
        }
        etat.dire("Envoyé par \(commande.expediteur)")
    }

    private func marquerVu(_ lecture: LectureExterne) {
        Task {
            guard let tmdb = etat.tmdb, (try? await ActionsCommunes.marquerVu(lecture, contexte: contexte, tmdb: tmdb)) != nil else {
                return etat.dire("TMDB ne répond pas : marque-le vu depuis sa fiche.")
            }
            if lecture.reference.type == .film { try? ServiceSoiree(contexte: contexte).retirer(lecture.reference) }
            etat.dire("« \(lecture.libelle) » marqué vu")
            // Petit délai : la question précédente se referme d'abord.
            try? await Task.sleep(for: .milliseconds(600))
            etat.demanderAvecQui(lecture.reference, titre: lecture.libelle) { autre in
                try await ActionsCommunes.marquerVu(lecture, contexte: autre, tmdb: tmdb)
            }
        }
    }

    /// Chaque onglet a sa pile : toute affiche ouvre la fiche du titre, par valeur.
    private func pile(@ViewBuilder _ contenu: () -> some View) -> some View {
        PileTV { contenu() }
    }
}

enum OngletTV: String, Hashable {
    case accueil, regarder, listes, explorer, profil, reglages
}

/// Où l'app s'ouvre. Toujours l'accueil — sauf dans une version de test, où `SEANCE_TV_ONGLET=nas` ou
/// `SEANCE_TV_FICHE=film:245891` mènent droit à un écran : la télécommande du simulateur ne se pilote pas en ligne
/// de commande, et il faut bien relire chaque écran.
enum DepartTV {
    static var onglet: OngletTV {
        #if DEBUG
        if let demande = ProcessInfo.processInfo.environment["SEANCE_TV_ONGLET"] {
            if let onglet = OngletTV(rawValue: demande) { return onglet }
            // Les anciennes pages (7.0) sont des sources de Regarder : « nas », « tele », « streaming », « ceSoir ».
            if ["ceSoir", "tele", "nas", "streaming"].contains(demande) { return .regarder }
        }
        #endif
        return .accueil
    }

    /// La source de Regarder à l'ouverture : `SEANCE_TV_ONGLET=nas` ouvre Regarder › NAS.
    static var source: SourceTV {
        #if DEBUG
        if let demande = ProcessInfo.processInfo.environment["SEANCE_TV_ONGLET"], let source = SourceTV(rawValue: demande) { return source }
        #endif
        return .tout
    }

    /// `SEANCE_TV_RAYON=videos` ouvre Regarder › NAS sur ce rayon, pour le relire en capture.
    static var rayon: RayonNASTV {
        #if DEBUG
        if let demande = ProcessInfo.processInfo.environment["SEANCE_TV_RAYON"],
           let rayon = RayonNASTV.allCases.first(where: { String(describing: $0) == demande }) { return rayon }
        #endif
        return .films
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

/// Une pile d'onglet (8.0) : elle garde son chemin, pour que l'appui long sur une carte puisse ouvrir une fiche
/// (« Voir la fiche », « Regarder ») par `\.ouvrirTV`.
struct PileTV<Contenu: View>: View {
    @ViewBuilder let contenu: Contenu
    @State private var chemin = NavigationPath()

    var body: some View {
        NavigationStack(path: $chemin) {
            contenu
                .sousLaPastille()
                .background { FondTV() }
                .destinationsTV()
        }
        .environment(\.ouvrirTV, OuvrirTV { chemin.append($0) })
    }
}

/// Ouvre une page dans la pile de l'onglet : une fiche, ou une fiche qui lance aussitôt la lecture.
struct OuvrirTV {
    let pousser: (AnyHashable) -> Void
    func fiche(_ reference: ReferenceTitre) { pousser(reference) }
    func regarder(_ reference: ReferenceTitre) { pousser(LectureTVDemande(reference: reference)) }
    func callAsFunction(_ valeur: some Hashable) { pousser(AnyHashable(valeur)) }
}

/// « Regarder » depuis l'appui long : la fiche s'ouvre et lance son action principale.
struct LectureTVDemande: Hashable { let reference: ReferenceTitre }

extension EnvironmentValues {
    @Entry var ouvrirTV: OuvrirTV?
}

extension View {
    /// Les pages qu'une pile de la TV sait ouvrir.
    func destinationsTV() -> some View {
        self
            .navigationDestination(for: ReferenceTitre.self) { FicheTV(reference: $0).pageOuverte() }
            .navigationDestination(for: LectureTVDemande.self) { FicheTV(reference: $0.reference, lancerALOuverture: true).pageOuverte() }
            .navigationDestination(for: PersonneTVRef.self) { PersonneTV(personne: $0).pageOuverte() }
            .navigationDestination(for: DossierVideosTV.self) { VideosPersoTV(chemin: $0.chemin).pageOuverte() }
            .navigationDestination(for: FiltresTVDemande.self) { ExplorerTV(sourceImposee: $0.source).pageOuverte() }
            .navigationDestination(for: GoutsTVDemande.self) { _ in PageGoutsTV().pageOuverte() }
            .navigationDestination(for: StatistiquesTVDemande.self) { _ in StatistiquesTV().pageOuverte() }
            .destinationsPreferencesTV()
    }
}

/// Une lecture demandée par l'iPhone (8.1).
struct LectureRecueTV: Identifiable {
    let id = UUID()
    let video: VideoPerso
    let acces: ReglagesNAS
    let motDePasse: String
    let depart: Double?
    let fichier: FichierNAS?

    init(video: VideoPerso, acces: ReglagesNAS, motDePasse: String, depart: Double?, fichier: FichierNAS?) {
        self.video = video
        self.acces = acces
        self.motDePasse = motDePasse
        self.depart = depart
        self.fichier = fichier
    }

    @MainActor
    init(fichier: FichierNAS, etat: EtatTV, depart: Double? = nil) {
        self.init(video: VideoPerso(chemin: fichier.chemin, taille: fichier.tailleOctets), acces: etat.nas,
                  motDePasse: etat.motDePasseDuNAS ?? "", depart: depart ?? etat.positions.aReprendre(fichier.chemin)?.secondes,
                  fichier: fichier)
    }
}
