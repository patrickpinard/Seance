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
    private(set) var enCours = false
    private(set) var rapport: ServiceBibliotheque.Rapport?
    private(set) var erreur: String?
    private(set) var derniereAnalyse: Date?
    /// Réglages utilisés par la dernière analyse réussie : s'ils ont changé, la bibliothèque est à refaire.
    private(set) var reglagesAnalyses: ReglagesNAS?

    /// Une analyse par jour suffit : les films arrivent sur le NAS au compte-gouttes.
    static let intervalleAnalyse: TimeInterval = 24 * 3600

    private let coffre: any CoffreCles

    private enum Cle {
        static let reglages = "nas.reglages"
        static let lecteur = "nas.lecteur"
        static let derniereAnalyse = "nas.derniereAnalyse"
        static let reglagesAnalyses = "nas.reglagesAnalyses"
    }

    init(coffre: any CoffreCles) {
        self.coffre = coffre
        let defauts = UserDefaults.standard
        reglages = defauts.data(forKey: Cle.reglages).flatMap { try? JSONDecoder().decode(ReglagesNAS.self, from: $0) } ?? ReglagesNAS()
        lecteur = defauts.string(forKey: Cle.lecteur).flatMap(LecteurVideo.init(rawValue:)) ?? .infuse
        derniereAnalyse = defauts.object(forKey: Cle.derniereAnalyse) as? Date
        reglagesAnalyses = defauts.data(forKey: Cle.reglagesAnalyses).flatMap { try? JSONDecoder().decode(ReglagesNAS.self, from: $0) }
        motDePasseEnregistre = ((try? coffre.lire(.nas)) ?? nil) != nil
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
    }

    /// EF-87 : ouvre le partage et compte les éléments de chaque dossier déclaré.
    func tester() async throws -> [String: Int] {
        try await explorateur().tester()
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
        }
    }

    /// Lien qui ouvre la vidéo dans l'app de lecture ; `nil` sans mot de passe.
    func lien(pour fichier: FichierNAS, avec lecteur: LecteurVideo) -> URL? {
        guard let motDePasse = try? coffre.lire(.nas),
              let video = reglages.url(chemin: fichier.chemin, motDePasse: motDePasse)
        else { return nil }
        return lecteur.lien(pour: video)
    }

    private func explorateur() throws -> ExplorateurSMB {
        guard let motDePasse = try coffre.lire(.nas) else { throw ErreurNAS.motDePasseManquant }
        return ExplorateurSMB(reglages: reglages, motDePasse: motDePasse)
    }
}
