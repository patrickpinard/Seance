import Foundation
import Observation
import SeanceDonnees
import SeanceKit
import SeanceNAS
import SwiftData

/// L'état de l'app TV : les clés du trousseau, le client TMDB, les réglages du NAS et son analyse.
/// Volontairement petit : ce qui se règle finement se règle sur l'iPhone, l'iPad ou le Mac (EF-142).
@MainActor
@Observable
final class EtatTV {
    private let coffre: any CoffreCles = Trousseau()
    private static let cacheTMDB = CacheTMDB(dossier: URL.cachesDirectory.appending(path: "Seance-TMDB"))

    private(set) var tmdb: TMDBClient?
    /// Le second accès au NAS, facultatif : les vidéos personnelles (EF-157).
    let videosPerso: EtatVideosPerso
    private(set) var nas: ReglagesNAS
    private(set) var motDePasseNAS = false
    private(set) var analyseEnCours = false
    private(set) var rapport: ServiceBibliotheque.Rapport?
    private(set) var erreurNAS: String?
    /// Dit en bas de l'écran ce qui vient d'être fait, quelques secondes.
    var message: String?

    /// L'app qui lit les vidéos du NAS : « Lire » n'ouvre que celle-là.
    private(set) var lecteur: LecteurVideo
    /// Le film lancé dans l'app de lecture : au retour dans Séance, on demande s'il a été regardé.
    var lectureAConfirmer: ReferenceTitre?
    private var lectureLancee: ReferenceTitre?
    private(set) var teleEnCours = false
    private(set) var derniereLectureTele = UserDefaults.standard.object(forKey: Cle.derniereLectureTele) as? Date

    private enum Cle {
        static let nas = "nas.reglages"
        static let lecteur = "nas.lecteur"
        static let derniereLectureTele = "tele.derniereLecture"
        static let chainesLues = "tele.chainesLues"
    }

    init() {
        videosPerso = EtatVideosPerso(coffre: coffre)
        if let donnees = UserDefaults.standard.data(forKey: Cle.nas), let lus = try? JSONDecoder().decode(ReglagesNAS.self, from: donnees) {
            nas = lus
        } else {
            nas = ReglagesNAS()
        }
        lecteur = UserDefaults.standard.string(forKey: Cle.lecteur).flatMap(LecteurVideo.init(rawValue:)) ?? .infuse
        motDePasseNAS = ((try? coffre.lire(.nas)) ?? nil) != nil
        rechargerTMDB()
    }

    var nasPret: Bool { nas.estComplet && motDePasseNAS }
    var enDemonstration: Bool {
        #if DEBUG
        Demonstration.active
        #else
        false
        #endif
    }

    // MARK: TMDB

    private func rechargerTMDB() {
        tmdb = try? DepotCles(coffre: coffre).client(transport: Self.cacheTMDB)
        #if DEBUG
        if let dossier = FauxTMDB.dossierDemande {
            tmdb = TMDBClient(identifiants: .cleAPI("demonstration"), transport: FauxTMDB(dossier: dossier), tentativesMax: 1)
        }
        #endif
    }

    /// Enregistre la clé seulement si TMDB l'accepte : une faute de frappe à la télécommande se voit tout de suite.
    func enregistrerCleTMDB(_ texte: String) async -> String? {
        let propre = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty else { return "La clé est vide." }
        let essai = TMDBClient(identifiants: .depuis(propre), transport: URLSession.shared)
        do {
            _ = try await essai.genres(.film)
        } catch {
            return "TMDB refuse cette clé. Vérifie-la sur themoviedb.org, dans Paramètres › API."
        }
        do {
            try coffre.enregistrer(propre, pour: .tmdb)
        } catch {
            return "La clé n'a pas pu être rangée dans le trousseau de l'Apple TV."
        }
        rechargerTMDB()
        return nil
    }

    // MARK: Configuration reçue d'un iPhone

    /// Range ce qu'un iPhone vient d'envoyer : les clés au trousseau, le NAS dans les réglages, les données dans le
    /// magasin — l'import complète sans rien effacer. Rend une phrase qui dit ce qui est arrivé.
    func appliquer(_ configuration: ConfigurationTransferee, contexte: ModelContext) -> String {
        var recus: [String] = []
        if let cle = configuration.cleTMDB, !cle.isEmpty, (try? coffre.enregistrer(cle, pour: .tmdb)) != nil {
            rechargerTMDB()
            recus.append("la clé TMDB")
        }
        if let reglages = configuration.nas {
            enregistrerNAS(reglages, motDePasse: configuration.motDePasseNAS ?? "")
            recus.append(motDePasseNAS ? "le NAS" : "le NAS, sans son mot de passe")
        }
        if let choisi = configuration.lecteur { choisir(choisi) }
        if let videos = configuration.videosPerso {
            videosPerso.enregistrer(videos, motDePasse: configuration.motDePasseVideos ?? "")
            recus.append("l'accès à tes vidéos personnelles")
        }
        if let donnees = configuration.sauvegarde, let sauvegarde = try? Sauvegarde.decoder(donnees),
           let plan = try? ServiceSauvegarde(contexte: contexte).importer(sauvegarde) {
            recus.append(plan.estVide ? "tes données (déjà à jour)" : "tes listes et tes soirées")
        }
        guard !recus.isEmpty else { return "« \(configuration.expediteur) » n'avait rien à envoyer." }
        return "Reçu de « \(configuration.expediteur) » : " + recus.joined(separator: ", ") + "."
    }

    // MARK: NAS

    func enregistrerNAS(_ reglages: ReglagesNAS, motDePasse: String) {
        nas = reglages
        UserDefaults.standard.set(try? JSONEncoder().encode(reglages), forKey: Cle.nas)
        if !motDePasse.isEmpty, (try? coffre.enregistrer(motDePasse, pour: .nas)) != nil { motDePasseNAS = true }
    }

    // MARK: Synchronisation par le NAS (EF-144)

    private(set) var synchroEnCours = false
    private(set) var derniereSynchro = UserDefaults.standard.object(forKey: "synchro.nas.derniere") as? Date
    /// Pourquoi la dernière synchronisation n'a pas abouti ; `nil` quand tout va bien.
    private(set) var erreurSynchro: String?

    /// « Apple TV 9C01 » : le nom du fichier que cette TV dépose sur le NAS.
    private var appareilSynchro: String {
        if let connu = UserDefaults.standard.string(forKey: "synchro.appareil") { return connu }
        let nom = "Apple TV \(UUID().uuidString.prefix(4))"
        UserDefaults.standard.set(nom, forKey: "synchro.appareil")
        return nom
    }

    /// Lit dans le dossier « Séance » du NAS ce que l'iPhone, l'iPad et le Mac y ont déposé — listes, soirées,
    /// plateformes, chaînes, goûts — et y dépose ce qui a été fait ici. Au lancement et à chaque retour dans l'app ;
    /// `bavard` : demandé depuis les Réglages, le résultat se dit même quand il n'y a rien.
    @ObservationIgnored private var derniereAVenir: Date?
    @ObservationIgnored private var aVenirEnCours = false

    func synchroniser(contexte: ModelContext, bavard: Bool = false) async {
        guard !enDemonstration, !synchroEnCours, nasPret, let motDePasse = (try? coffre.lire(.nas)) ?? nil else {
            if bavard { dire("Règle d'abord le NAS : la synchronisation passe par lui.") }
            return
        }
        synchroEnCours = true
        defer { synchroEnCours = false }
        // L'état de la synchronisation précédente vit à côté du magasin, dans le cache : si tvOS a fait le ménage,
        // les deux sont partis ensemble, et tout le dossier se relit.
        let fichierEtat = URL.cachesDirectory.appending(path: "Seance/synchro-etat.json")
        let moteur = MoteurSynchro(contexte: contexte, transport: DossierSynchroSMB(reglages: nas, motDePasse: motDePasse),
                                   appareil: appareilSynchro, espace: "synchro.nas", fichierEtat: fichierEtat)
        if !FileManager.default.fileExists(atPath: fichierEtat.path(percentEncoded: false)) { moteur.oublier() }
        do {
            let bilan = try await moteur.synchroniser()
            derniereSynchro = .now
            UserDefaults.standard.set(Date.now, forKey: "synchro.nas.derniere")
            erreurSynchro = nil
            let titres = bilan.recus.reduce(0) { $0 + $1.ajouts.suivis.count + $1.ajouts.soirees.count + $1.misAJour + $1.supprimes }
            if !bilan.recus.isEmpty {
                dire(titres > 0 ? "Synchronisé avec tes appareils : \(titres) changement\(titres > 1 ? "s" : "")" : "Synchronisé avec tes appareils")
            } else if bavard {
                dire("Tout est à jour.")
            }
        } catch {
            erreurSynchro = ErreurNAS.message(error)
            if bavard { dire("La synchronisation n'a pas abouti : \(ErreurNAS.message(error))") }
        }
    }

    /// « À venir » sur la TV (EF-142) : les rendez-vous de tes titres — nouvel épisode, sortie, passage télé — sont
    /// calculés ici comme sur l'iPhone, mais sans notification : tvOS n'en a pas. Une fois par heure suffit.
    func actualiserAVenir(contexte: ModelContext) async {
        guard !enDemonstration, let tmdb, !aVenirEnCours else { return }
        if let derniere = derniereAVenir, Date.now.timeIntervalSince(derniere) < 3600 { return }
        aVenirEnCours = true
        defer { aVenirEnCours = false }
        _ = try? await ServiceAlertes(contexte: contexte).calculer(source: tmdb, reglages: ReglagesAlertes())
        derniereAVenir = .now
    }

    /// « Tester une alerte » : l'Apple TV n'affiche pas de notification. Elle dépose une demande dans le dossier du NAS ;
    /// l'iPhone qui la découvre à sa prochaine synchronisation prévient, et l'Apple Watch avec lui.
    func demanderEssaiAlerte() async {
        guard nasPret, let motDePasse = (try? coffre.lire(.nas)) ?? nil else { return dire("Règle d'abord le NAS : l'essai passe par lui.") }
        do {
            let demande = try SynchroDossier.EssaiAlerte(de: appareilSynchro).encoder()
            try await DossierSynchroSMB(reglages: nas, motDePasse: motDePasse).ecrire(demande, nom: SynchroDossier.fichierEssaiAlerte)
            dire("Demande déposée. Ouvre Séance sur ton iPhone, puis verrouille-le : l'alerte arrive 20 secondes après, sur la montre aussi.")
        } catch {
            dire("L'essai n'a pas pu être déposé : \(ErreurNAS.message(error))")
        }
    }

    private func explorateur() -> ExplorateurSMB? {
        guard let motDePasse = (try? coffre.lire(.nas)) ?? nil else { return nil }
        return ExplorateurSMB(reglages: nas, motDePasse: motDePasse)
    }

    enum TestNAS {
        /// Nombre de vidéos par dossier.
        case reussi([String: Int])
        case echec(String)
    }

    func testerNAS() async -> TestNAS {
        guard let explorateur = explorateur() else { return .echec("Le mot de passe du NAS manque.") }
        do { return .reussi(try await explorateur.tester()) } catch { return .echec(ErreurNAS.message(error)) }
    }

    func analyserNAS(contexte: ModelContext) async {
        guard !analyseEnCours, let tmdb, let explorateur = explorateur() else { return }
        analyseEnCours = true
        erreurNAS = nil
        defer { analyseEnCours = false }
        do {
            rapport = try await ServiceBibliotheque(contexte: contexte).actualiser(explorateur: explorateur, recherche: tmdb, dossiers: nas.dossiers)
        } catch is CancellationError {
            return
        } catch {
            erreurNAS = ErreurNAS.message(error)
        }
    }

    // MARK: Lecture

    func choisir(_ nouveau: LecteurVideo) {
        lecteur = nouveau
        UserDefaults.standard.set(nouveau.rawValue, forKey: Cle.lecteur)
    }

    /// Le lien vers l'app de lecture choisie, et elle seule. Infuse ouvre le titre dans sa bibliothèque par son
    /// identifiant TMDB (le partage du NAS doit y être ajouté, sur l'Apple TV aussi) ; VLC reçoit l'adresse SMB.
    func lien(pour fichier: FichierNAS) -> URL? {
        switch lecteur {
        case .infuse:
            let episode = fichier.saison.flatMap { saison in fichier.episode.map { NumeroEpisode(saison: saison, episode: $0) } }
            return fichier.reference.flatMap { lecteur.lienBibliotheque($0, episode: episode) }
        case .vlc:
            guard let motDePasse = (try? coffre.lire(.nas)) ?? nil, let video = nas.url(chemin: fichier.chemin, motDePasse: motDePasse) else { return nil }
            return lecteur.lien(pour: video)
        }
    }

    /// Un film part dans l'app de lecture : on s'en souvient, pour demander au retour s'il a été regardé.
    func noterLecture(_ fichier: FichierNAS) {
        lectureLancee = fichier.reference.flatMap { $0.type == .film ? $0 : nil }
    }

    /// Retour dans Séance : « Tu l'as regardé ? »
    func revenir() {
        lectureAConfirmer = lectureLancee
        lectureLancee = nil
    }

    // MARK: Programme TV

    /// Relit le guide si la dernière lecture a plus de douze heures ou si les chaînes cochées ont changé.
    func actualiserTele(contexte: ModelContext, force: Bool = false) async {
        guard !enDemonstration, !teleEnCours, let tmdb, let actives = try? ServiceProgrammesTV.chainesActives(contexte) else { return }
        let lues = UserDefaults.standard.stringArray(forKey: Cle.chainesLues)
        guard force || ServiceProgrammesTV.doitActualiser(derniereLecture: derniereLectureTele, chainesLues: lues, chainesActives: actives) else { return }
        teleEnCours = true
        defer { teleEnCours = false }
        let service = ServiceProgrammesTV(contexte: contexte, guide: GuideTVClient(), rattachement: RattachementGuide(recherche: tmdb))
        guard (try? await service.actualiser()) != nil else { return }
        derniereLectureTele = .now
        UserDefaults.standard.set(Date.now, forKey: Cle.derniereLectureTele)
        UserDefaults.standard.set(actives, forKey: Cle.chainesLues)
    }

    func dire(_ texte: String) {
        message = texte
        Task {
            try? await Task.sleep(for: .seconds(3))
            if message == texte { message = nil }
        }
    }
}
