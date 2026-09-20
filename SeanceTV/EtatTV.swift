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

    // MARK: Programme télé

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
