import SeanceDonnees
import SeanceKit
import SeanceNAS
import SwiftData
import SwiftUI

/// Le NAS vu par l'app (EF-71 à EF-79, EF-86, EF-87) : réglages, analyse de la bibliothèque et liens
/// de lecture. Le mot de passe ne quitte le trousseau qu'au moment d'une connexion ou d'une lecture.
@MainActor
@Observable
final class EtatNAS {
    private(set) var reglages: ReglagesNAS
    private(set) var motDePasseEnregistre: Bool
    private(set) var lecteur: LecteurVideo
    /// 7.0 : les films du NAS se lisent dans Séance, par VLCKit (par défaut) ; sinon dans l'app `lecteur` (Infuse).
    /// Sans effet sur le Mac, où VLCKit n'existe pas.
    private(set) var dansSeance: Bool
    private(set) var enCours = false
    private(set) var rapport: ServiceBibliotheque.Rapport?
    private(set) var erreur: String?
    private(set) var derniereAnalyse: Date?
    /// Réglages utilisés par la dernière analyse réussie : s'ils ont changé, la bibliothèque est à refaire.
    private(set) var reglagesAnalyses: ReglagesNAS?
    /// Vidéo confiée à une app de lecture ; gardée si Séance est fermée entre-temps.
    private(set) var lectureEnCours: LectureExterne?
    /// Question « As-tu regardé… ? » à poser au retour dans l'app.
    var lectureAConfirmer: LectureExterne?

    /// Une analyse par jour suffit : les films arrivent sur le NAS au compte-gouttes.
    static let intervalleAnalyse: TimeInterval = 24 * 3600

    private let coffre: any CoffreCles
    /// Renseigné par l'état de l'app : les problèmes vont au journal d'À propos.
    var journal: Journal?

    private enum Cle {
        static let reglages = "nas.reglages"
        static let lecteur = "nas.lecteur"
        static let dansSeance = "nas.dansSeance"
        static let derniereAnalyse = "nas.derniereAnalyse"
        static let reglagesAnalyses = "nas.reglagesAnalyses"
        static let lectureEnCours = "nas.lectureEnCours"
    }

    init(coffre: any CoffreCles) {
        self.coffre = coffre
        let defauts = UserDefaults.standard
        reglages = defauts.data(forKey: Cle.reglages).flatMap { try? JSONDecoder().decode(ReglagesNAS.self, from: $0) } ?? ReglagesNAS()
        lecteur = defauts.string(forKey: Cle.lecteur).flatMap(LecteurVideo.init(rawValue:)) ?? .infuse
        dansSeance = defauts.object(forKey: Cle.dansSeance) as? Bool ?? true
        derniereAnalyse = defauts.object(forKey: Cle.derniereAnalyse) as? Date
        reglagesAnalyses = defauts.data(forKey: Cle.reglagesAnalyses).flatMap { try? JSONDecoder().decode(ReglagesNAS.self, from: $0) }
        motDePasseEnregistre = ((try? coffre.lire(.nas)) ?? nil) != nil
        lectureEnCours = defauts.data(forKey: Cle.lectureEnCours).flatMap { try? JSONDecoder().decode(LectureExterne.self, from: $0) }
    }

    // MARK: Lecture puis « vu »

    /// La vidéo vient d'être confiée à l'app de lecture.
    /// Où l'on s'est arrêté dans chaque vidéo du NAS, films et souvenirs (8.0) : voyage avec les autres appareils,
    /// Apple TV comprise, par les réglages synchronisés.
    private(set) var positions = PositionsLecture(donnees: UserDefaults.standard.data(forKey: PositionsLecture.cle))

    /// Le nom de cet appareil, tel que « Tu t'es arrêté à 1:03:12, sur l'iPad » le dira ailleurs.
    static var nomAppareil: String {
        #if targetEnvironment(macCatalyst)
        "Mac"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }

    func noterPosition(_ chemin: String, secondes: Double, duree: Double) {
        positions.noter(chemin, secondes: secondes, duree: duree, appareil: Self.nomAppareil)
        enregistrerPositions()
    }

    /// « Depuis le début » : la position s'efface, pour tous les appareils.
    func oublierPosition(_ chemin: String) {
        positions.oublier(chemin)
        enregistrerPositions()
    }

    /// Les positions d'un autre appareil, les plus récentes l'emportant ; vrai si quelque chose a changé.
    @discardableResult
    func recevoirPositions(_ donnees: Data) -> Bool {
        guard positions.fusionner(PositionsLecture(donnees: donnees)) else { return false }
        enregistrerPositions()
        return true
    }

    // MARK: Titres identifiés à la main (8.4)

    /// Des choix reçus d'un autre appareil, à poser sur la bibliothèque à la fin de la synchronisation.
    private var identificationsRecues = false

    /// Le titre choisi parmi les propositions de TMDB pour une vidéo que Séance n'a pas reconnue seule (nil : oublier le
    /// choix). Toute l'œuvre le reprend tout de suite — épisodes, copies —, sans relire le NAS.
    func identifier(chemin: String, titre: TitreResume?, contexte: ModelContext) throws {
        let modifies = try ServiceBibliotheque(contexte: contexte).identifier(chemin: chemin, titre: titre)
        guard titre != nil, var rapport else { return }
        let cle = IdentificationsTMDB.cleNAS(chemin: chemin)
        let avant = rapport.nonReconnues.count
        rapport.nonReconnues.removeAll { IdentificationsTMDB.cleNAS(chemin: $0) == cle }
        rapport.reconnues += avant - rapport.nonReconnues.count
        if modifies > 0 { self.rapport = rapport }
    }

    /// Les choix d'un autre appareil, les plus récents l'emportant ; vrai si quelque chose a changé.
    @discardableResult
    func recevoirIdentifications(_ donnees: Data) -> Bool {
        var identifications = IdentificationsTMDB.lues()
        guard identifications.fusionner(IdentificationsTMDB(donnees: donnees)) else { return false }
        identifications.enregistrer()
        identificationsRecues = true
        return true
    }

    /// Pose sur la bibliothèque les choix reçus pendant la synchronisation.
    func appliquerIdentificationsRecues(contexte: ModelContext) {
        guard identificationsRecues else { return }
        identificationsRecues = false
        _ = try? ServiceBibliotheque(contexte: contexte).appliquer(IdentificationsTMDB.lues())
    }

    /// Relit les positions : au lancement, après la démonstration qui les pose.
    /// Dans les réglages de l'app et dans ceux du groupe d'apps : le widget « Reprendre » (8.1) les lit là.
    private func enregistrerPositions() {
        let donnees = positions.encoder()
        UserDefaults.standard.set(donnees, forKey: PositionsLecture.cle)
        UserDefaults(suiteName: EntrepotSeance.groupeApp)?.set(donnees, forKey: PositionsLecture.cle)
        PublicationWidgets.recharger()
    }

    func relirePositions() {
        positions = PositionsLecture(donnees: UserDefaults.standard.data(forKey: PositionsLecture.cle))
        // Le widget « Reprendre » les reçoit aussi dès le lancement, sans attendre la prochaine lecture (8.2.7).
        UserDefaults(suiteName: EntrepotSeance.groupeApp)?.set(positions.encoder(), forKey: PositionsLecture.cle)
    }

    func noterLecture(_ fichier: FichierNAS) {
        guard let reference = fichier.reference else { return }
        let episode = fichier.saison.flatMap { saison in fichier.episode.map { NumeroEpisode(saison: saison, episode: $0) } }
        memoriserLecture(LectureExterne(reference: reference, titre: fichier.titre, episode: episode, debut: .now))
    }

    /// Au retour dans Séance : la question arrive après au moins 10 minutes de lecture.
    func verifierRetour(maintenant: Date = .now) {
        guard let lecture = lectureEnCours else { return }
        switch lecture.decision(maintenant: maintenant) {
        case .attendre: break
        case .demander:
            lectureAConfirmer = lecture
            memoriserLecture(nil)
        case .oublier:
            memoriserLecture(nil)
        }
    }

    /// « Oui, marquer vu » : le film, ou l'épisode précis, rejoint l'historique (`ActionsCommunes`, comme sur la TV).
    func confirmerLecture(_ lecture: LectureExterne, contexte: ModelContext, tmdb: TMDBClient?) async {
        guard let tmdb else { return }
        do {
            try await ActionsCommunes.marquerVu(lecture, contexte: contexte, tmdb: tmdb)
        } catch {
            journal?.noter(.lecture, "« \(lecture.libelle) » n'a pas pu être marqué comme vu.", erreur: error)
        }
    }

    /// Une plateforme s'ouvre sur ce titre (8.2) : au retour, après dix minutes au moins, Séance demande s'il a été
    /// regardé — le film, ou le prochain épisode de la série.
    func noterLecture(_ lecture: LectureExterne) {
        memoriserLecture(lecture)
    }

    private func memoriserLecture(_ lecture: LectureExterne?) {
        lectureEnCours = lecture
        UserDefaults.standard.set(lecture.flatMap { try? JSONEncoder().encode($0) }, forKey: Cle.lectureEnCours)
    }

    var estConfigure: Bool {
        reglages.estComplet && motDePasseEnregistre
    }

    /// Vrai si la bibliothèque correspond aux réglages actuels (dossiers, partage, adresse).
    var analyseAJour: Bool {
        derniereAnalyse != nil && reglagesAnalyses == reglages
    }

    func enregistrer(_ nouveaux: ReglagesNAS) {
        reglages = nouveaux
        if let donnees = try? JSONEncoder().encode(nouveaux) {
            UserDefaults.standard.set(donnees, forKey: Cle.reglages)
        }
    }

    func enregistrerMotDePasse(_ texte: String) throws {
        guard !texte.isEmpty else { return }
        try coffre.enregistrer(texte, pour: .nas)
        motDePasseEnregistre = true
    }

    func supprimerMotDePasse() throws {
        try coffre.supprimer(.nas)
        motDePasseEnregistre = false
    }

    func choisir(_ nouveau: LecteurVideo) {
        lecteur = nouveau
        UserDefaults.standard.set(nouveau.rawValue, forKey: Cle.lecteur)
        lireDansSeance(false)
    }

    func lireDansSeance(_ oui: Bool) {
        dansSeance = oui
        UserDefaults.standard.set(oui, forKey: Cle.dansSeance)
    }

    /// Le lecteur tel que les réglages le nomment.
    var nomLecteur: String {
        #if targetEnvironment(macCatalyst)
        lecteur.nom
        #else
        dansSeance ? "Séance (VLCKit)" : lecteur.nom
        #endif
    }

    /// EF-87 : ouvre le partage et compte les éléments de chaque dossier déclaré.
    func tester() async throws -> [String: Int] {
        try await explorateur().tester()
    }

    /// Le mot de passe du NAS des films, pour le lecteur de Séance (6.6).
    var motDePasse: String? { (try? coffre.lire(.nas)) ?? nil }

    /// Les dossiers présents à la racine du partage (6.4), pour les cocher au lieu de les taper.
    func dossiersDuPartage() async throws -> [String] {
        try await explorateur().dossiersDuPartage()
    }

    /// Lit les dossiers déclarés, rattache les vidéos à TMDB et remplace la bibliothèque.
    /// `automatique` : lancée au démarrage, seulement si la dernière analyse date d'hier.
    func analyser(contexte: ModelContext, tmdb: TMDBClient?, automatique: Bool = false) async {
        guard !enCours, let tmdb, estConfigure else { return }
        if automatique, analyseAJour, let derniereAnalyse, Date.now.timeIntervalSince(derniereAnalyse) < Self.intervalleAnalyse { return }

        enCours = true
        erreur = nil
        defer { enCours = false }
        do {
            rapport = try await ServiceBibliotheque(contexte: contexte).actualiser(
                explorateur: try explorateur(), recherche: tmdb, dossiers: reglages.dossiers
            )
            let maintenant = Date.now
            derniereAnalyse = maintenant
            reglagesAnalyses = reglages
            UserDefaults.standard.set(maintenant, forKey: Cle.derniereAnalyse)
            UserDefaults.standard.set(try? JSONEncoder().encode(reglages), forKey: Cle.reglagesAnalyses)
        } catch is CancellationError {
            return
        } catch {
            self.erreur = ErreurNAS.message(error)
            journal?.noter(.nas, Self.injoignable(error) ? "Le NAS n'est pas joignable." : "L'analyse du NAS a échoué.",
                           erreur: error, conseil: ErreurNAS.message(error))
        }
    }

    enum Lien {
        case pret(URL)
        case motDePasseManquant
        /// Infuse ne s'ouvre directement que sur un titre reconnu (et un épisode numéroté).
        case titreInconnu
    }

    /// Lien qui lance la vidéo dans l'app de lecture.
    func lien(pour fichier: FichierNAS, avec lecteur: LecteurVideo) -> Lien {
        #if targetEnvironment(macCatalyst)
        // Infuse installé sur le Mac et choisi dans Réglages › Lecture : le titre s'ouvre dans sa bibliothèque et démarre
        // aussitôt, comme sur l'iPhone et l'Apple TV. Monter le partage par le Finder, lui, n'ouvrait pas toujours le film.
        if lecteur == .infuse, let essai = URL(string: "infuse://"), UIApplication.shared.canOpenURL(essai), let reference = fichier.reference {
            let episode = fichier.saison.flatMap { saison in fichier.episode.map { NumeroEpisode(saison: saison, episode: $0) } }
            if let lien = lecteur.lienBibliotheque(reference, episode: episode) { return .pret(lien) }
        }
        // Sinon, le partage est souvent déjà monté : le fichier s'ouvre dans le lecteur par défaut.
        // Sinon, le Finder monte le partage (identifiants demandés ou repris du trousseau de macOS).
        let monte = URL(filePath: "/Volumes").appending(path: reglages.partage).appending(path: fichier.chemin)
        if FileManager.default.fileExists(atPath: monte.path(percentEncoded: false)) { return .pret(monte) }
        return reglages.url(chemin: fichier.chemin).map { .pret($0) } ?? .titreInconnu
        #else
        switch lecteur {
        case .infuse:
            // Le titre s'ouvre dans la bibliothèque d'Infuse et démarre aussitôt.
            let episode = fichier.saison.flatMap { saison in fichier.episode.map { NumeroEpisode(saison: saison, episode: $0) } }
            guard let reference = fichier.reference, let lien = lecteur.lienBibliotheque(reference, episode: episode) else { return .titreInconnu }
            return .pret(lien)
        case .vlc:
            guard let motDePasse = try? coffre.lire(.nas),
                  let video = reglages.url(chemin: fichier.chemin, motDePasse: motDePasse),
                  let lien = lecteur.lien(pour: video)
            else { return .motDePasseManquant }
            return .pret(lien)
        }
        #endif
    }

    /// Réseau local refusé, NAS éteint ou hors du Wi-Fi de la maison.
    static func injoignable(_ erreur: any Error) -> Bool {
        if let nas = erreur as? ErreurNAS {
            switch nas {
            case .reseauLocalRefuse, .injoignable: return true
            default: return false
            }
        }
        if let posix = erreur as? POSIXError {
            return [.EHOSTUNREACH, .ENETUNREACH, .EHOSTDOWN, .ETIMEDOUT, .ECONNREFUSED, .ENETDOWN].contains(posix.code)
        }
        let texte = erreur.localizedDescription.lowercased()
        return texte.contains("no route to host") || texte.contains("timed out") || texte.contains("host is down")
    }

    /// Le dossier « Séance » du NAS, pour la synchronisation (EF-144) ; `nil` tant que le NAS n'est pas réglé.
    /// `sousDossier` : « Famille/Anne », pour un autre profil que le principal.
    func dossierSynchro(sousDossier: String? = nil) -> DossierSynchroSMB? {
        guard reglages.estComplet, let motDePasse = (try? coffre.lire(.nas)) ?? nil, !motDePasse.isEmpty else { return nil }
        let dossier = [DossierSynchroSMB.dossierParDefaut, sousDossier].compactMap { $0 }.joined(separator: "/")
        return DossierSynchroSMB(reglages: reglages, motDePasse: motDePasse, dossier: dossier)
    }

    private func explorateur() throws -> ExplorateurSMB {
        guard let motDePasse = try coffre.lire(.nas) else { throw ErreurNAS.motDePasseManquant }
        return ExplorateurSMB(reglages: reglages, motDePasse: motDePasse)
    }
}
