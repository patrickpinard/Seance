import SeanceDonnees
import SeanceKit
import SwiftData
import CoreSpotlight
import SwiftUI

/// Barre d'onglets (UX, navigation) : Explorer est l'onglet de recherche d'iOS 26, en rond séparé.
struct RacineView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Environment(\.scenePhase) private var phase
    @Environment(\.horizontalSizeClass) private var classeTaille
    @AppStorage("bienvenue.terminee") private var bienvenueTerminee = false
    @State private var bienvenue = false
    /// Famille (6.0) : « Qui regarde ? » à l'ouverture, quand la maison a plusieurs profils. Une fois par lancement.
    @State private var quiRegarde = RacineView.doitDemanderQuiRegarde
    private static var dejaDemande = false
    private static var doitDemanderQuiRegarde: Bool {
        let famille = ProfilsFamille()
        #if DEBUG
        if Demonstration.active { return false }
        #endif
        // Sur un appareil partagé (iPad de la maison, Mac), Séance demande qui regarde ; sur l'iPhone, non (6.4) —
        // sauf si Patrick l'a demandé dans Réglages › Famille.
        let partage = UIDevice.current.userInterfaceIdiom != .phone
        guard !dejaDemande, famille.aPlusieursProfils, famille.demanderAuLancement(parDefaut: partage) else { return false }
        return true
    }
    @State private var onglet = OngletRacine.accueil
    /// Le travail du retour dans l'app, annulé quand la racine disparaît (changement de personne).
    @State private var tachePremierPlan: Task<Void, Never>?
    @State private var survolConfirmation = false
    /// Spotlight se refait quand tes listes changent.
    @Query private var suivisPourSpotlight: [Suivi]
    private var nombreDeSuivis: Int { suivisPourSpotlight.count }
    /// Sur le Mac, le message de confirmation se centre sur le contenu, pas sur la fenêtre avec sa barre latérale.
    @AppStorage("mac.barreLaterale.masquee") private var barreMasquee = false

    static var surMac: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    var body: some View {
        // 8.0, charte commune : trois onglets partout — Accueil, Regarder, Mes listes — et la loupe. Regarder réunit la
        // soirée, le streaming, la TV et le NAS sous une rangée de jours. Le portrait (Préférences) et la roue dentée
        // (Réglages) sont en haut de chaque page, sur tous les appareils.
        TabView(selection: $onglet) {
            Tab("Accueil", systemImage: "house.fill", value: .accueil) {
                AccueilView()
            }
            Tab("Regarder", systemImage: "play.rectangle.on.rectangle.fill", value: .regarder) {
                RegarderView()
            }
            Tab("Mes listes", systemImage: "bookmark.fill", value: .listes) {
                MesListesView()
            }
            // iPad et Mac (demande de Patrick, 25 septembre 2026) : Préférences et Réglages sont des onglets du menu, en
            // pages complètes. L'iPhone, dont la barre du bas ne tient que cinq onglets, garde le portrait et la roue.
            // Des icônes seules sur l'iPad, comme sur l'Apple TV (en mots, le portrait les repoussait derrière une flèche) ;
            // des mots sur le Mac, dont le menu n'affiche pas d'icônes — les onglets y restaient vides.
            // 8.1 (demande de Patrick) : Préférences et Réglages ne sont plus des onglets, ni sur l'iPad ni sur le Mac — le
            // portrait (avec le prénom) et la roue en haut de chaque page, la même interface que l'iPhone.
            Tab("Recherche", systemImage: "magnifyingglass", value: .explorer, role: .search) {
                ExplorerView()
            }
        }
        // iPhone : barre d'onglets en bas. iPad et Mac : le menu en haut, comme sur l'Apple TV (charte 8.0) — plus de barre
        // latérale : iPadOS la rouvrait d'une session à l'autre, par-dessus les onglets.
        .tabViewStyle(.tabBarOnly)
        // Confirmation d'une action, au-dessus de la barre d'onglets.
        #if targetEnvironment(macCatalyst)
        .allowsHitTesting(!survolConfirmation)
        #endif
        .overlay(alignment: .bottom) {
            if let confirmation = etat.confirmation {
                BandeauConfirmation(confirmation: confirmation, survol: $survolConfirmation)
                    .padding(.bottom, 96)
                    #if targetEnvironment(macCatalyst)
                    .padding(.leading, 0)
                    #endif
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(confirmation.annuler != nil)
            }
        }
        .animation(.snappy, value: etat.confirmation)
        // Le sablier d'une ouverture au-dehors (6.3) : Netflix, Disney+, blue TV… Le temps d'y arriver — une requête
        // pour retrouver la page exacte du titre, puis l'app qui se lance —, l'écran dit ce qui se passe.
        .modifier(SablierOuverture.Calque())
        .tint(Theme.accent)
        .task { await etat.chargerGenres() }
        // Le contrôleur d'onglets n'existe qu'une fois la fenêtre montée, et prend ses dimensions avec un temps de retard.
        .task { await BarreLaterale.ouvrirSurIPadDesQuePossible() }
        // Lancé en portrait puis tourné : la barre s'ouvre quand la fenêtre s'élargit.
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { paysage in
            guard paysage else { return }
            Task { await BarreLaterale.ouvrirSurIPadDesQuePossible() }
        }
        #if targetEnvironment(macCatalyst)
        .task { BarreLaterale.restaurer() }
        // Sous cette taille, la barre latérale et la fiche en deux colonnes se serrent.
        .task {
            for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                scene.sizeRestrictions?.minimumSize = CGSize(width: 960, height: 680)
            }
        }
        #endif
        #if DEBUG
        // Captures et essais : SEANCE_ONGLET ouvre l'app sur une page (regarder, streaming, tele, nas, listes, recherche,
        // reglages, preferences) ; SEANCE_JOUR décale la rangée de Regarder de quelques jours.
        .task {
            let env = ProcessInfo.processInfo.environment
            defer {
                if let decalage = env["SEANCE_JOUR"].flatMap(Int.init), decalage > 0 {
                    etat.jourRegarder = Calendar.current.date(byAdding: .day, value: decalage,
                                                              to: Calendar.current.startOfDay(for: ServiceSoiree.jour(ServiceSoiree.soiree()) ?? .now))
                }
            }
            // SEANCE_LIRE_FICHIER=<chemin> : le lecteur VLC sur un fichier du Mac (le NAS monté), pour éprouver l'image.
            #if !targetEnvironment(macCatalyst)
            if let fichier = env["SEANCE_LIRE_FICHIER"] {
                etat.lecture = LectureEnCours(video: VideoPerso(chemin: fichier, taille: 0), acces: ReglagesNAS(), motDePasse: "")
            }
            #endif
            if let fiche = env["SEANCE_FICHE"]?.split(separator: ":"), fiche.count == 2,
               let type = TypeTitre(rawValue: String(fiche[0])), let id = Int(fiche[1]) {
                etat.ficheDemandee = ReferenceTitre(type: type, tmdbID: id)
            }
            switch env["SEANCE_ONGLET"] {
            case "regarder": aller(a: .ceSoir)
            case "streaming": aller(a: .streaming)
            case "tele": aller(a: .tele)
            case "nas": aller(a: .nas)
            case "listes": onglet = .listes
            case "recherche": onglet = .explorer
            case "reglages": aller(a: .reglages)
            case "preferences": aller(a: .profil)
            default: break
            }
        }
        #endif
        // Premier lancement : le parcours de bienvenue, sauf si Séance connaît déjà des goûts.
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["SEANCE_BIENVENUE"] != nil { bienvenue = true; return }
            #endif
            guard !bienvenueTerminee else { return }
            if (try? ServiceGouts(contexte: contexte).dejaPersonnalise()) == true {
                bienvenueTerminee = true
            } else {
                bienvenue = true
            }
        }
        .modifier(FeuillesDeLApp())
        #if !targetEnvironment(macCatalyst)
        // Le lecteur (8.0), par-dessus l'app et non en feuille : en image dans l'image, il s'efface sans s'arrêter.
        .overlay {
            if let lecture = etat.lecture {
                LecteurVLC(lecture: lecture)
                    .id(lecture.id)
                    .opacity(etat.lectureEnImage ? 0 : 1)
                    .allowsHitTesting(!etat.lectureEnImage)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.snappy, value: etat.lecture?.id)
        .animation(.easeOut(duration: 0.2), value: etat.lectureEnImage)
        #endif
        .modifier(ReceptionEtSynchro())
        .fullScreenCover(isPresented: $quiRegarde) {
            QuiRegardeView { profil in
                Self.dejaDemande = true
                quiRegarde = false
                ConteneurApp.changerDeProfil(vers: profil)
            }
        }
        .fullScreenCover(isPresented: $bienvenue) {
            BienvenueView(mode: .premierLancement) {
                bienvenueTerminee = true
                bienvenue = false
            }
        }
        // Relancé quand la clé TMDB arrive : sans elle, rien ne peut être rattaché.
        .task(id: etat.tmdb == nil) {
            etat.nas.relirePositions()
            // Le magasin s'est ouvert par la voie de secours : à savoir, même si rien n'est perdu.
            if let erreur = EntrepotSeance.derniereErreurDuPlan {
                etat.journal.noter(.general, "Le plan de migration des données n'a pas pu s'appliquer : le magasin a été ouvert par la migration automatique.",
                                   conseil: "Rien n'est perdu. Détail : \(erreur.prefix(200))")
                EntrepotSeance.derniereErreurDuPlan = nil
            }
            // 8.2.11 : tant que « Qui regarde ? » est ouvert, rien ne démarre — la personne choisie va rouvrir un autre
            // magasin, et le travail commencé dans celui-ci y écrivait après coup (plantage au changement de personne).
            while quiRegarde {
                try? await Task.sleep(for: .milliseconds(300))
                if Task.isCancelled { return }
            }
            etat.ou.actualiserLocal(contexte: contexte)
            await etat.demarrer(contexte: contexte)
            guard !Task.isCancelled else { return }
            etat.ou.actualiserLocal(contexte: contexte)
            await etat.alertes.programmerRappelExpiration(etat.expirationInstallation)
            await PublicationWidgets.actualiser(contexte: contexte, tmdb: etat.tmdb, force: true)
            // Siri apprend les titres de tes listes pour « Ajoute … à ma soirée ».
            RaccourcisSeance.updateAppShortcutParameters()
        }
        // Retour dans l'app : programmes et alertes remis à jour s'ils datent.
        .onDisappear { tachePremierPlan?.cancel() }
        .onChange(of: phase) { _, nouvelle in
            switch nouvelle {
            case .active:
                etat.nas.verifierRetour()
                etat.ou.actualiserLocal(contexte: contexte)
                // Gardée pour être annulée si l'on change de personne (8.2.11) : détachée, elle écrivait ensuite dans le
                // magasin remplacé, et SwiftData plantait (rapport de l'iPad du 26.09.2026).
                tachePremierPlan?.cancel()
                tachePremierPlan = Task {
                    await etat.revenirAuPremierPlan(contexte: contexte)
                    guard !Task.isCancelled else { return }
                    await PublicationWidgets.actualiser(contexte: contexte, tmdb: etat.tmdb)
                }
            case .background:
                BarreLaterale.retenirSurIPad()
                // Soirée, épisodes cochés, alertes : les widgets relisent tout en quittant l'app.
                PublicationWidgets.recharger()
                // Un titre ajouté à tes listes doit pouvoir se dire à Siri sans relancer l'app.
                RaccourcisSeance.updateAppShortcutParameters()
            default:
                break
            }
        }
        // Retour d'Infuse, de VLC ou du lecteur du Mac : proposer de marquer la vidéo comme vue.
        .alert("As-tu regardé « \(etat.nas.lectureAConfirmer?.libelle ?? "") » ?",
               isPresented: Binding { etat.nas.lectureAConfirmer != nil } set: { if !$0 { etat.nas.lectureAConfirmer = nil } },
               presenting: etat.nas.lectureAConfirmer) { lecture in
            Button("Oui, marquer vu") {
                Task { await etat.nas.confirmerLecture(lecture, contexte: contexte, tmdb: etat.tmdb) }
            }
            Button("Pas encore", role: .cancel) {}
        } message: { lecture in
            Text(lecture.episode == nil
                 ? "Séance le marquera comme vu : il sortira des suggestions et comptera dans tes statistiques."
                 : "Séance cochera cet épisode et passera au suivant.")
        }
        .onChange(of: etat.rechercheDemandee) { _, demandee in
            if demandee { onglet = .explorer }
        }
        .onChange(of: etat.ongletDemande) { _, demande in
            guard let demande else { return }
            etat.ongletDemande = nil
            aller(a: demande)
        }
        // « Dans Explorer » depuis une fiche acteur.
        // 8.2 : depuis une feuille (les acteurs favoris des Préférences), elle se referme d'abord — l'onglet changeait
        // derrière elle, et le bouton semblait ne rien faire.
        .onChange(of: etat.filtreExplorerDemande) { _, demande in
            guard demande != nil else { return }
            let dansUneFeuille = etat.preferencesOuvertes || etat.reglagesOuverts
            etat.preferencesOuvertes = false
            etat.reglagesOuverts = false
            Task {
                if dansUneFeuille { try? await Task.sleep(for: .milliseconds(450)) }
                onglet = .explorer
            }
        }
        // Une alerte touchée demande une fiche : elle s'ouvre dans l'accueil.
        .onChange(of: etat.ficheDemandee) { _, demande in
            if demande != nil { onglet = .accueil }
        }
        // Un titre touché dans la recherche du système (Spotlight) : sa fiche s'ouvre.
        .onContinueUserActivity(CSSearchableItemActionType) { activite in
            if let reference = IndexSpotlight.reference(activite) {
                onglet = .accueil
                etat.ficheDemandee = reference
            }
        }
        .task(id: nombreDeSuivis) { IndexSpotlight.actualiser(contexte: contexte) }
        .onOpenURL { url in
            // Un fichier : une sauvegarde reçue par AirDrop ou ouverte depuis Fichiers.
            if url.isFileURL {
                etat.sauvegardeRecue = url
                return
            }
            // Le widget « Reprendre » (8.1) : la vidéo repart dans le lecteur, là où elle s'était arrêtée.
            if url.host() == "reprendre",
               let chemin = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "chemin" })?.value {
                #if !targetEnvironment(macCatalyst)
                if let fichier = try? contexte.fetch(FetchDescriptor<FichierNAS>(predicate: #Predicate { $0.chemin == chemin })).first {
                    etat.lire(fichier)
                }
                #endif
                return
            }
            switch LienProfond.onglet(url) {
            case .ceSoir:
                aller(a: .ceSoir)
                return
            case .aVenir:
                etat.listeDemandee = .aVenir
                onglet = .listes
                return
            case .tele:
                aller(a: .tele)
                return
            case nil:
                break
            }
            guard let reference = LienProfond.reference(url) else { return }
            onglet = .accueil
            etat.ficheDemandee = reference
        }
    }

    /// Un onglet demandé d'ailleurs : Ce soir et les sources ouvrent Regarder sur elles ; Réglages et Préférences, leur
    /// onglet sur l'iPad et le Mac, leur feuille sur l'iPhone.
    private func aller(a demande: OngletRacine) {
        // Toute demande referme d'abord les feuilles ouvertes par le haut de page.
        etat.preferencesOuvertes = false
        etat.reglagesOuverts = false
        switch demande {
        case .profil:
            etat.preferencesOuvertes = true
        case .reglages:
            etat.reglagesOuverts = true
        case .ceSoir:
            etat.sourceRegarder = .tout
            etat.jourRegarder = nil
            onglet = .regarder
        case .streaming: etat.sourceRegarder = .streaming; onglet = .regarder
        case .tele: etat.sourceRegarder = .tele; onglet = .regarder
        case .nas: etat.sourceRegarder = .nas; onglet = .regarder
        default:
            onglet = demande
        }
    }
}

/// Les panneaux que l'app peut ouvrir de partout : prévoir un soir, dire avec qui on a vu, ranger dans une liste.
/// Ils vivent ici plutôt que dans le corps de `RacineView` : empilés là-bas, ils faisaient renoncer le vérificateur
/// de types de Swift — l'empilement de modificateurs devient un type trop grand pour être vérifié d'un coup.
private struct FeuillesDeLApp: ViewModifier {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding { etat.titreADater } set: { etat.titreADater = $0 }) { titre in
                ChoixSoiree(titre: titre.titre, depart: .now) { jour in
                    PrevoirSoiree.prevoir(titre, le: jour, etat: etat, contexte: contexte)
                }
            }
            .sheet(item: Binding { etat.avecQui } set: { etat.avecQui = $0 }) { demande in
                FeuilleAvecQui(demande: demande)
            }
            .sheet(item: Binding { etat.titrePourListe } set: { etat.titrePourListe = $0 }) { titre in
                AjoutAListeView(titre: titre)
            }
            .modifier(ProposerUnAbonnement())
            // Les Préférences (7.0) : ouvertes par le portrait, en haut à gauche de chaque page.
            .sheet(isPresented: Binding { etat.preferencesOuvertes } set: { etat.preferencesOuvertes = $0 }) {
                ProfilView(enFeuille: true)
            }
            // Réglages sur l'iPhone (7.0) : la roue dentée de chaque page les ouvre en feuille.
            .sheet(isPresented: Binding { etat.reglagesOuverts } set: { etat.reglagesOuverts = $0 }) {
                FeuilleReglages()
            }

    }
}

enum OngletRacine: Hashable {
    /// Trois onglets et la recherche (8.0) : `accueil`, `regarder`, `listes`, `explorer`. Les autres valeurs sont des
    /// demandes : `ceSoir`, `streaming`, `tele`, `nas` ouvrent Regarder sur leur source, `profil` et `reglages` leur feuille.
    case accueil, ceSoir, streaming, tele, nas, regarder, listes, profil, reglages, explorer
}

/// Destination commune : toucher une affiche ouvre sa fiche (UX-10).
extension View {
    func destinationsTitres() -> some View {
        // Charte 8.0 : la roue des réglages en haut à droite de chaque page, y compris celles qu'on ouvre d'une autre.
        navigationDestination(for: ReferenceTitre.self) { reference in
            FicheView(reference: reference).boutonBarreLaterale(preferences: false)
        }
        .navigationDestination(for: ReferencePersonne.self) { personne in
            // Pas de roue sur la page d'un acteur (8.2, demande de Patrick) : la cloche et la recherche suffisent.
            PersonneView(personne: personne).boutonBarreLaterale(preferences: false, reglages: false)
        }
        .navigationDestination(for: DestinationReglage.self) { destination in
            PageReglage(destination: destination)
        }
        .navigationDestination(for: DossierVideosPerso.self) { dossier in
            VideosPersoView(dossier: dossier).boutonBarreLaterale(preferences: false)
        }
    }
}

/// Les Réglages en feuille, ouverts par la roue dentée de chaque page (8.0). Sur l'iPhone, une pile ; sur l'iPad et le
/// Mac, deux colonnes — la liste à gauche, la page choisie à droite — pour régler sans aller-retour.
private struct FeuilleReglages: View {
    /// `false` : l'onglet Réglages de l'iPad et du Mac, une page complète sans « OK ».
    var enFeuille = true
    @Environment(\.dismiss) private var fermer
    @Environment(\.horizontalSizeClass) private var classe

    var body: some View {
        Group {
            // En feuille sur un grand écran : deux colonnes. En onglet (iPad, Mac), une seule pile pleine page : deux colonnes
            // dans un onglet font se replier le menu du Mac en liste déroulante.
            if classe == .regular, enFeuille {
                NavigationSplitView {
                    ReglagesView()
                        .destinationsTitres()
                        .toolbar {
                            if enFeuille { ToolbarItem(placement: .confirmationAction) { Button("OK") { fermer() } } }
                        }
                        .navigationSplitViewColumnWidth(min: 380, ideal: 440, max: 500)
                } detail: {
                    NavigationStack {
                        EtatVide(symbole: "gearshape", titre: "Réglages", message: "Choisis un réglage dans la liste.")
                            .frame(maxWidth: 440)
                            .padding(24)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.fond)
                            .destinationsTitres()
                    }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack {
                    ReglagesView()
                        .destinationsTitres()
                        .toolbar {
                            if enFeuille { ToolbarItem(placement: .confirmationAction) { Button("OK") { fermer() } } }
                        }
                }
            }
        }
        .presentationSizing(.page)
    }
}

