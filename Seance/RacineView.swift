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
            Tab("Profil", systemImage: "person.crop.circle", value: .profil) {
                ProfilView()
            }
            // Sur l'iPhone, un 6e onglet cacherait Explorer derrière « Autre » : Réglages s'ouvre depuis Profil.
            if classeTaille != .compact {
                Tab("Réglages", systemImage: "gearshape", value: .reglages) {
                    NavigationStack {
                        ReglagesView()
                            .destinationsTitres()
                    }
                }
            }
            Tab("Explorer", systemImage: "magnifyingglass", value: .explorer, role: .search) {
                ExplorerView()
            }
        }
        // iPhone : barre d'onglets ; Mac et grandes fenêtres : barre latérale.
        .tabViewStyle(.sidebarAdaptable)
        .tint(Theme.accent)
        .task { await etat.chargerGenres() }
        #if targetEnvironment(macCatalyst)
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
        .fullScreenCover(isPresented: $bienvenue) {
            BienvenueView(mode: .premierLancement) {
                bienvenueTerminee = true
                bienvenue = false
            }
        }
        // Relancé quand la clé TMDB arrive : sans elle, rien ne peut être rattaché.
        .task(id: etat.tmdb == nil) {
            await etat.demarrer(contexte: contexte)
            await PublicationWidgets.actualiser(contexte: contexte, tmdb: etat.tmdb, force: true)
            // Siri apprend les titres de tes listes pour « Ajoute … à ma soirée ».
            RaccourcisSeance.updateAppShortcutParameters()
        }
        // Retour dans l'app : programmes et alertes remis à jour s'ils datent.
        .onChange(of: phase) { _, nouvelle in
            switch nouvelle {
            case .active:
                etat.nas.verifierRetour()
                Task {
                    await etat.revenirAuPremierPlan(contexte: contexte)
                    await PublicationWidgets.actualiser(contexte: contexte, tmdb: etat.tmdb)
                }
            case .background:
                // Soirée, épisodes cochés, alertes : les widgets relisent tout en quittant l'app.
                PublicationWidgets.recharger()
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
        .onChange(of: etat.ongletDemande) { _, demande in
            guard let demande else { return }
            onglet = demande == .reglages && classeTaille == .compact ? .profil : demande
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
            switch LienProfond.onglet(url) {
            case .ceSoir:
                onglet = .ceSoir
                return
            case .aVenir:
                etat.listeDemandee = .aVenir
                onglet = .listes
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
    }
}
