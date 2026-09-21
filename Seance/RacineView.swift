import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Barre d'onglets (UX, navigation) : Explorer est l'onglet de recherche d'iOS 26, en rond séparé.
struct RacineView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Environment(\.scenePhase) private var phase
    @Environment(\.horizontalSizeClass) private var classeTaille
    @AppStorage("bienvenue.terminee") private var bienvenueTerminee = false
    @State private var bienvenue = false
    @State private var onglet = OngletRacine.accueil
    @State private var survolConfirmation = false
    /// Mac : les Réglages s'ouvrent en feuille, depuis la roue dentée ou ⌘,.
    @State private var reglagesOuverts = false
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
        TabView(selection: $onglet) {
            Tab("Accueil", systemImage: "house.fill", value: .accueil) {
                AccueilView()
            }
            Tab("Ce soir", systemImage: "moon.stars", value: .ceSoir) {
                CeSoirView()
            }
            Tab("Mes listes", systemImage: "bookmark", value: .listes) {
                MesListesView()
            }
            Tab("Préférences", systemImage: "person.crop.circle", value: .profil) {
                ProfilView()
            }
            // Sur l'iPhone, un 6e onglet cacherait Explorer derrière « Autre » : Réglages s'ouvre depuis Profil.
            // Sur le Mac non plus : la roue dentée, en haut à droite de chaque page, y mène (comme sur l'Apple TV).
            if classeTaille != .compact, !Self.surMac {
                Tab("Réglages", systemImage: "gearshape", value: .reglages) {
                    NavigationStack {
                        ReglagesView()
                            .destinationsTitres()
                            .boutonBarreLaterale()
                    }
                }
            }
            Tab("Explorer", systemImage: "magnifyingglass", value: .explorer, role: .search) {
                ExplorerView()
            }
        }
        // iPhone : barre d'onglets en bas. iPad : onglets en haut, barre latérale à la demande. Mac : le menu en haut, comme
        // sur l'iPad et l'Apple TV (demande de Patrick, 20 septembre 2026) — plus de barre latérale.
        #if targetEnvironment(macCatalyst)
        .tabViewStyle(.tabBarOnly)
        #else
        .tabViewStyle(.sidebarAdaptable)
        #endif
        // Confirmation d'une action, au-dessus de la barre d'onglets.
        #if targetEnvironment(macCatalyst)
        .allowsHitTesting(!survolConfirmation)
        #endif
        #if targetEnvironment(macCatalyst)
        // Mac : la roue dentée des réglages, tout en haut à droite, à la hauteur du menu, la même sur toutes les pages.
        .overlay(alignment: .topTrailing) {
            Button { reglagesOuverts = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accentClair)
                    .frame(width: 40, height: 40)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.trait))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Réglages (⌘,)")
            .accessibilityLabel("Réglages")
            // Sous la barre de titre de la fenêtre, et non dedans : `ignoresSafeArea` la plaçait dans la zone que
            // macOS se réserve, où le clic n'atteignait jamais le bouton.
            .padding(.top, 10)
            .padding(.trailing, 18)
        }
        .sheet(isPresented: $reglagesOuverts) {
            NavigationStack {
                ReglagesView()
                    .destinationsTitres()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { reglagesOuverts = false } } }
            }
            .frame(minWidth: 760, minHeight: 640)
        }
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
        .sheet(item: Binding { etat.titreADater } set: { etat.titreADater = $0 }) { titre in
            ChoixSoiree(titre: titre.titre, depart: .now) { jour in
                PrevoirSoiree.prevoir(titre, le: jour, etat: etat, contexte: contexte)
            }
        }
        .sheet(item: Binding { etat.titrePourListe } set: { etat.titrePourListe = $0 }) { titre in
            AjoutAListeView(titre: titre)
        }
        .modifier(ReceptionEtSynchro())
        .fullScreenCover(isPresented: $bienvenue) {
            BienvenueView(mode: .premierLancement) {
                bienvenueTerminee = true
                bienvenue = false
            }
        }
        // Relancé quand la clé TMDB arrive : sans elle, rien ne peut être rattaché.
        .task(id: etat.tmdb == nil) {
            // Le magasin s'est ouvert par la voie de secours : à savoir, même si rien n'est perdu.
            if let erreur = EntrepotSeance.derniereErreurDuPlan {
                etat.journal.noter(.general, "Le plan de migration des données n'a pas pu s'appliquer : le magasin a été ouvert par la migration automatique.",
                                   conseil: "Rien n'est perdu. Détail : \(erreur.prefix(200))")
                EntrepotSeance.derniereErreurDuPlan = nil
            }
            etat.ou.actualiserLocal(contexte: contexte)
            await etat.demarrer(contexte: contexte)
            etat.ou.actualiserLocal(contexte: contexte)
            await etat.alertes.programmerRappelExpiration(etat.expirationInstallation)
            await PublicationWidgets.actualiser(contexte: contexte, tmdb: etat.tmdb, force: true)
            // Siri apprend les titres de tes listes pour « Ajoute … à ma soirée ».
            RaccourcisSeance.updateAppShortcutParameters()
        }
        // Retour dans l'app : programmes et alertes remis à jour s'ils datent.
        .onChange(of: phase) { _, nouvelle in
            switch nouvelle {
            case .active:
                etat.nas.verifierRetour()
                etat.ou.actualiserLocal(contexte: contexte)
                Task {
                    await etat.revenirAuPremierPlan(contexte: contexte)
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
            if demande == .reglages, Self.surMac {
                reglagesOuverts = true
            } else {
                onglet = demande == .reglages && classeTaille == .compact ? .profil : demande
            }
            etat.ongletDemande = nil
        }
        // Fenêtre rétrécie (iPad) : l'onglet Réglages disparaît, Profil le remplace.
        .onChange(of: classeTaille) { _, classe in
            if classe == .compact, onglet == .reglages { onglet = .profil }
        }
        // « Dans Explorer » depuis une fiche acteur.
        .onChange(of: etat.filtreExplorerDemande) { _, demande in
            if demande != nil { onglet = .explorer }
        }
        // Une alerte touchée demande une fiche : elle s'ouvre dans l'accueil.
        .onChange(of: etat.ficheDemandee) { _, demande in
            if demande != nil { onglet = .accueil }
        }
        .onOpenURL { url in
            // Un fichier : une sauvegarde reçue par AirDrop ou ouverte depuis Fichiers.
            if url.isFileURL {
                etat.sauvegardeRecue = url
                return
            }
            switch LienProfond.onglet(url) {
            case .ceSoir:
                onglet = .ceSoir
                return
            case .aVenir:
                etat.listeDemandee = .aVenir
                onglet = .listes
                return
            case .tele:
                onglet = .accueil
                etat.programmeTeleDemande = true
                return
            case nil:
                break
            }
            guard let reference = LienProfond.reference(url) else { return }
            onglet = .accueil
            etat.ficheDemandee = reference
        }
    }
}

enum OngletRacine: Hashable {
    case accueil, ceSoir, listes, profil, reglages, explorer
}

/// Destination commune : toucher une affiche ouvre sa fiche (UX-10).
extension View {
    func destinationsTitres() -> some View {
        navigationDestination(for: ReferenceTitre.self) { reference in
            FicheView(reference: reference)
        }
        .navigationDestination(for: ReferencePersonne.self) { personne in
            PersonneView(personne: personne)
        }
        .navigationDestination(for: DestinationReglage.self) { destination in
            PageReglage(destination: destination)
        }
        .navigationDestination(for: DossierVideosPerso.self) { dossier in
            VideosPersoView(dossier: dossier)
        }
    }
}
