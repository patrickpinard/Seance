import Foundation
import SeanceDonnees
import SeanceKit
import SeanceNAS
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension UTType {
    /// Une sauvegarde de Séance, « .seance » : reçue par AirDrop ou touchée dans Fichiers, elle s'ouvre dans l'app.
    /// Le contenu est le même JSON que les sauvegardes « .json ».
    static let sauvegardeSeance = UTType(exportedAs: "ch.patrick.seance.sauvegarde", conformingTo: .json)
}

/// Importer une sauvegarde, d'où qu'elle vienne — fichier choisi, AirDrop, dossier de synchronisation — et dire ce
/// qui est arrivé. L'import ajoute et complète, sans rien effacer.
@MainActor
enum ImportSauvegarde {
    struct Bilan {
        /// « 12 titres, 2 soirées prévues, 5 réglages » ; vide quand le fichier n'apportait rien.
        let parties: [String]

        var estVide: Bool { parties.isEmpty }
        var phrase: String { parties.joined(separator: ", ") }
    }

    static func importer(_ donnees: Data, etat: EtatApp, contexte: ModelContext) throws -> Bilan {
        let sauvegarde = try Sauvegarde.decoder(donnees)
        let plan = try ServiceSauvegarde(contexte: contexte).importer(sauvegarde)
        let reglages = PreferencesSauvegardees.appliquer(sauvegarde.preferences ?? [:], etat: etat)
        let bilan = Bilan(parties: parties(plan, reglages: reglages))
        if !bilan.estVide {
            etat.ou.actualiserLocal(contexte: contexte)
            Task { await etat.alertes.planifier(contexte: contexte, tmdb: etat.tmdb) }
        }
        return bilan
    }

    /// « 2 titres, 1 supprimé, 1 mis à jour » : ce qu'un fichier du dossier de synchronisation a changé ici.
    static func phrase(_ recu: ServiceSynchro.Recu) -> String {
        (parties(recu.ajouts, reglages: 0) + [(recu.misAJour, "mis à jour", "mis à jour"), (recu.supprimes, "supprimé", "supprimés")]
            .filter { $0.0 > 0 }.map { Format.pluriel($0.0, $0.1, $0.2) }).joined(separator: ", ")
    }

    private static func parties(_ plan: PlanImport, reglages: Int) -> [String] {
        let comptes: [(Int, String, String)] = [
            (plan.suivis.count, "titre", "titres"), (plan.suivisCompletes.count, "titre complété", "titres complétés"),
            (plan.visionnages.count, "visionnage", "visionnages"), (plan.soirees.count, "soirée prévue", "soirées prévues"),
            (plan.listes.count + plan.titresAjoutesAuxListes.count, "liste", "listes"), (plan.acteursSuivis.count, "acteur suivi", "acteurs suivis"),
            (plan.filtres.count, "filtre", "filtres"), (plan.interets.count, "goût", "goûts"),
            (plan.abonnements.count, "plateforme", "plateformes"), (plan.chaines.count, "chaîne", "chaînes"),
            (plan.reports.count, "idée reportée", "idées reportées"), (reglages, "réglage", "réglages"),
        ]
        return comptes.filter { $0.0 > 0 }.map { Format.pluriel($0.0, $0.1, $0.2) }
    }

    /// La sauvegarde de cet appareil, réglages compris, prête à être écrite ou envoyée.
    static func exporter(contexte: ModelContext, le date: Date = .now) throws -> Sauvegarde {
        var sauvegarde = try ServiceSauvegarde(contexte: contexte).exporter(le: date)
        sauvegarde.preferences = PreferencesSauvegardees.lire()
        return sauvegarde
    }

    /// Le fichier « .seance » à partager (AirDrop, Messages, Mail) : écrit dans le dossier temporaire.
    static func fichierAPartager(contexte: ModelContext) throws -> URL {
        let nom = Sauvegarde.nomFichier(pour: .now).replacingOccurrences(of: ".json", with: ".seance")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(nom)
        try exporter(contexte: contexte).encoder().write(to: url, options: .atomic)
        return url
    }
}

/// Synchronisation entre tes appareils par un dossier d'iCloud Drive (ou de Fichiers), sans CloudKit : tu choisis le
/// même dossier sur chaque appareil, une fois. Chacun y dépose son fichier et fusionne ceux des autres quand ils ont
/// changé (voir `SynchroDossier` et `ServiceSynchro`) : ajouts, mais aussi suppressions et retours en arrière, le plus
/// récent l'emportant. Une sauvegarde importée à la main, elle, ne supprime jamais rien.
@MainActor
@Observable
final class EtatSynchro {
    /// Famille (6.0) : chaque profil synchronise dans son sous-dossier (« Famille/Anne »), avec ses propres repères ; le
    /// profil principal reste à la racine, comme avant. Un changement de profil recrée cet état.
    let profil = ProfilsFamille().actif
    private var suffixe: String { profil.estPrincipal ? "" : ".p.\(profil.id)" }
    private var espaceDossier: String { "synchro" + suffixe }
    private var espaceNAS: String { "synchro.nas" + suffixe }

    private(set) var nomDossier: String?
    private(set) var derniereSynchro: Date?
    private(set) var dernierMessage: String?
    private(set) var enCours = false

    var automatique: Bool {
        didSet { UserDefaults.standard.set(automatique, forKey: Cle.automatique) }
    }

    /// Synchroniser aussi par le dossier « Séance » du NAS (EF-144) : le seul chemin jusqu'à l'Apple TV.
    var parLeNAS: Bool {
        didSet {
            UserDefaults.standard.set(parLeNAS, forKey: Cle.parLeNAS)
            // Éteint puis rallumé, le NAS se relit en entier.
            if !parLeNAS { ["synchro.nas.importes", "synchro.nas.empreinte", Cle.derniereNAS].forEach(UserDefaults.standard.removeObject); derniereSynchroNAS = nil; messageNAS = nil }
        }
    }
    private(set) var derniereSynchroNAS: Date?
    /// Pourquoi le NAS n'a pas répondu à la dernière tentative ; `nil` quand tout va bien.
    private(set) var messageNAS: String?

    private enum Cle {
        static let signet = "synchro.dossier"
        static let nomDossier = "synchro.nomDossier"
        static let automatique = "synchro.automatique"
        static let appareil = "synchro.appareil"
        static let importes = "synchro.importes"
        static let empreinte = "synchro.empreinte"
        static let derniere = "synchro.derniere"
        static let parLeNAS = "synchro.nas.actif"
        static let derniereNAS = "synchro.nas.derniere"
    }

    /// Pas plus d'une synchronisation automatique toutes les deux minutes.
    private static let intervalleMinimal: TimeInterval = 120

    init() {
        let defauts = UserDefaults.standard
        nomDossier = defauts.data(forKey: Cle.signet) == nil ? nil : defauts.string(forKey: Cle.nomDossier)
        automatique = defauts.object(forKey: Cle.automatique) == nil ? true : defauts.bool(forKey: Cle.automatique)
        derniereSynchro = defauts.object(forKey: Cle.derniere) as? Date
        // D'office dès que le NAS est réglé (4.9) : l'Apple TV n'a que lui, et un interrupteur oublié la laissait sans
        // nouvelles de l'iPhone. Qui l'a éteint exprès le retrouve éteint.
        parLeNAS = defauts.object(forKey: Cle.parLeNAS) == nil ? true : defauts.bool(forKey: Cle.parLeNAS)
        derniereSynchroNAS = defauts.object(forKey: Cle.derniereNAS) as? Date
        #if DEBUG
        // Tests d'interface : le dossier est imposé au lancement, sans sélecteur de fichiers ni iCloud Drive.
        if let chemin = ProcessInfo.processInfo.environment["SEANCE_SYNCHRO_DOSSIER"] {
            try? choisir(URL(fileURLWithPath: chemin, isDirectory: true))
        }
        #endif
    }

    var estConfiguree: Bool { nomDossier != nil || parLeNAS }

    /// Un dossier choisi, ou le NAS réglé et « Par le NAS » allumé : il y a de quoi synchroniser.
    func estPrete(nas nasRegle: Bool) -> Bool { nomDossier != nil || (parLeNAS && nasRegle) }

    /// « iPhone 3F2A » : le genre d'appareil et quatre caractères tirés une fois pour toutes.
    private var appareil: String {
        if let connu = UserDefaults.standard.string(forKey: Cle.appareil) { return connu }
        let genre = ProcessInfo.processInfo.isMacCatalystApp ? "Mac" : UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        let nom = "\(genre) \(UUID().uuidString.prefix(4))"
        UserDefaults.standard.set(nom, forKey: Cle.appareil)
        return nom
    }

    /// Le dossier choisi dans le sélecteur de fichiers : l'app en garde l'accès par un signet.
    func choisir(_ url: URL) throws {
        let acces = url.startAccessingSecurityScopedResource()
        defer { if acces { url.stopAccessingSecurityScopedResource() } }
        let signet = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let defauts = UserDefaults.standard
        defauts.set(signet, forKey: Cle.signet)
        defauts.set(url.lastPathComponent, forKey: Cle.nomDossier)
        // Un autre dossier : tout ce qu'il contient est nouveau, et notre fichier n'y est pas encore.
        defauts.removeObject(forKey: Cle.importes)
        defauts.removeObject(forKey: Cle.empreinte)
        try? FileManager.default.removeItem(at: fichierEtat)
        nomDossier = url.lastPathComponent
        dernierMessage = nil
    }

    func oublier() {
        let defauts = UserDefaults.standard
        [Cle.signet, Cle.nomDossier, Cle.importes, Cle.empreinte, Cle.derniere].forEach(defauts.removeObject)
        try? FileManager.default.removeItem(at: fichierEtat)
        nomDossier = nil
        derniereSynchro = nil
        dernierMessage = nil
    }

    /// Importe les fichiers des autres appareils qui ont changé, puis dépose le nôtre s'il a changé — dans le dossier
    /// choisi (iCloud Drive, Fichiers), puis dans celui du NAS s'il est activé : c'est par lui que l'Apple TV reçoit tout.
    /// `automatique` : au retour dans l'app ; silencieuse s'il n'y a rien, et pas plus d'une fois toutes les deux minutes.
    func synchroniser(etat: EtatApp, contexte: ModelContext, automatique declenchementAuto: Bool = false) async {
        let signet = UserDefaults.standard.data(forKey: Cle.signet)
        guard !enCours, signet != nil || parLeNAS else { return }
        if declenchementAuto {
            guard automatique else { return }
            if let derniere = derniereSynchro, Date.now.timeIntervalSince(derniere) < Self.intervalleMinimal { return }
        }
        enCours = true
        defer { enCours = false }

        var recus: [String] = []
        var depose = false
        var echecs: [String] = []
        let preferences = { PreferencesSauvegardees.lire() }
        let appliquer: ([String: Sauvegarde.Preference], [[String: Sauvegarde.Preference]]) -> Void = { remplacees, recues in
            _ = PreferencesSauvegardees.appliquer(remplacees, etat: etat, remplacer: true)
            // Les réglages jamais touchés ici se reprennent aussi, comme à l'import d'un fichier.
            for reglages in recues { _ = PreferencesSauvegardees.appliquer(reglages, etat: etat) }
        }
        func noter(_ bilan: MoteurSynchro.Bilan) {
            for recu in bilan.recus { recus.append("\(ImportSauvegarde.phrase(recu)) (\(Self.nomAppareil(recu.nom)))") }
            if bilan.deposees != nil { depose = true }
        }

        // 1. Le dossier d'iCloud Drive ou de Fichiers.
        if let signet {
            do {
                var perime = false
                let dossier = try URL(resolvingBookmarkData: signet, options: [], relativeTo: nil, bookmarkDataIsStale: &perime)
                let acces = dossier.startAccessingSecurityScopedResource()
                defer { if acces { dossier.stopAccessingSecurityScopedResource() } }
                if perime, let neuf = try? dossier.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(neuf, forKey: Cle.signet)
                }
                let transportLocal = DossierLocal(dossier: profil.dossierSynchro.map { dossier.appending(path: $0, directoryHint: .isDirectory) } ?? dossier)
                let moteur = MoteurSynchro(contexte: contexte, transport: transportLocal, appareil: appareil,
                                           espace: espaceDossier, fichierEtat: fichierEtat)
                let bilan = try await moteur.synchroniser(preferences: preferences, appliquer: appliquer)
                noter(bilan)
                await traiterEssaiAlerte(bilan.presents, transport: transportLocal, espace: espaceDossier, etat: etat)
                // Un filet de sécurité : l'état du jour, daté, à côté ; les cinq derniers de cet appareil sont gardés.
                if let donnees = bilan.deposees {
                    let nomAppareil = appareil
                    let jour = DateTMDB(.now).description
                    try? await Task.detached { try Self.archiver(donnees, dossier: dossier, appareil: nomAppareil, jour: jour) }.value
                }
            } catch {
                echecs.append("le dossier est-il toujours là, et iCloud Drive disponible ?")
                etat.journal.noter(.general, "La synchronisation par le dossier n'a pas abouti.", erreur: error)
            }
        }

        // 2. Le dossier « Séance » du NAS (EF-144), à la maison seulement : ailleurs, le NAS ne répond pas et ce n'est
        //    pas une panne — la synchronisation automatique se tait, la prochaine à la maison rattrapera.
        if parLeNAS {
            if let transport = etat.nas.dossierSynchro(sousDossier: profil.dossierSynchro) {
                do {
                    let moteur = MoteurSynchro(contexte: contexte, transport: transport, appareil: appareil,
                                               espace: espaceNAS, fichierEtat: fichierEtat)
                    let bilan = try await moteur.synchroniser(preferences: preferences, appliquer: appliquer)
                    noter(bilan)
                    await traiterEssaiAlerte(bilan.presents, transport: transport, espace: espaceNAS, etat: etat)
                    derniereSynchroNAS = .now
                    UserDefaults.standard.set(Date.now, forKey: Cle.derniereNAS)
                    messageNAS = nil
                } catch {
                    messageNAS = ErreurNAS.message(error)
                    if !declenchementAuto { echecs.append("NAS : \(ErreurNAS.message(error))") }
                    if !EtatNAS.injoignable(error) {
                        etat.journal.noter(.nas, "La synchronisation par le NAS n'a pas abouti.", erreur: error,
                                           conseil: "Le compte du NAS doit pouvoir écrire dans le partage : Séance y crée le dossier « \(DossierSynchroSMB.dossierParDefaut) ».")
                    }
                }
            } else {
                messageNAS = "Complète d'abord Réglages › NAS (adresse, partage, mot de passe)."
            }
        }

        if !recus.isEmpty {
            etat.ou.actualiserLocal(contexte: contexte)
            Task { await etat.alertes.planifier(contexte: contexte, tmdb: etat.tmdb) }
        }
        derniereSynchro = .now
        UserDefaults.standard.set(Date.now, forKey: Cle.derniere)
        if !recus.isEmpty {
            dernierMessage = "Reçu : \(recus.joined(separator: " ; "))."
            etat.confirmer("Synchronisé : \(recus.joined(separator: " ; "))", symbole: "arrow.triangle.2.circlepath")
            AccessibilityNotification.Announcement("Synchronisé : \(recus.joined(separator: ", "))").post()
        } else if !echecs.isEmpty {
            dernierMessage = "La synchronisation n'a pas abouti : \(echecs.joined(separator: " ; "))"
        } else if !declenchementAuto {
            dernierMessage = depose ? "Tes données ont été déposées. Rien de nouveau des autres appareils." : "Tout est à jour."
        }
    }

    // MARK: Essai d'alerte entre appareils

    /// Une demande d'essai déposée par un autre appareil (l'Apple TV, le Mac, l'iPad) : celui-ci prévient — et l'Apple
    /// Watch avec l'iPhone. Une demande ne sert qu'une fois par dossier, et jamais à celui qui l'a faite.
    private func traiterEssaiAlerte(_ presents: [SynchroDossier.Fichier], transport: any TransportSynchro, espace: String, etat: EtatApp) async {
        let cle = "\(espace).essaiAlerte"
        guard let demande = SynchroDossier.essaiAlerteDemande(presents, derniereTraitee: UserDefaults.standard.object(forKey: cle) as? Date) else { return }
        UserDefaults.standard.set(demande, forKey: cle)
        guard let donnees = try? await transport.lire(SynchroDossier.fichierEssaiAlerte),
              let essai = SynchroDossier.EssaiAlerte.decoder(donnees), essai.de != appareil else { return }
        await etat.alertes.envoyerEssai(de: essai.de)
    }

    /// « Tester sur mes autres appareils » : dépose la demande dans chaque dossier configuré. Renvoie où elle est partie.
    func demanderEssaiAilleurs(etat: EtatApp) async -> [String] {
        guard let demande = try? SynchroDossier.EssaiAlerte(de: appareil).encoder() else { return [] }
        var depots: [String] = []
        if let signet = UserDefaults.standard.data(forKey: Cle.signet) {
            var perime = false
            if let dossier = try? URL(resolvingBookmarkData: signet, options: [], relativeTo: nil, bookmarkDataIsStale: &perime) {
                let acces = dossier.startAccessingSecurityScopedResource()
                defer { if acces { dossier.stopAccessingSecurityScopedResource() } }
                if (try? await DossierLocal(dossier: dossier).ecrire(demande, nom: SynchroDossier.fichierEssaiAlerte)) != nil { depots.append("iCloud Drive") }
            }
        }
        if parLeNAS, let transport = etat.nas.dossierSynchro(),
           (try? await transport.ecrire(demande, nom: SynchroDossier.fichierEssaiAlerte)) != nil { depots.append("NAS") }
        return depots
    }

    /// L'état déposé à la synchronisation précédente : c'est en s'y comparant que l'appareil sait ce qu'il a modifié
    /// ou supprimé depuis. Gardé hors du dossier partagé, qu'un autre appareil pourrait avoir vidé.
    private var fichierEtat: URL {
        let dossier = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        return dossier.appendingPathComponent(profil.estPrincipal ? "synchro-etat.json" : "synchro-etat-\(profil.id).json")
    }

    /// « Séance — iPad 77C1.json » → « iPad ».
    private static func nomAppareil(_ fichier: String) -> String {
        let nom = fichier.dropFirst(SynchroDossier.prefixe.count).dropLast(SynchroDossier.suffixe.count)
        return nom.split(separator: " ").first.map(String.init) ?? String(nom)
    }

    /// Le dossier choisi dans Fichiers, vu comme un transport : lecture et écriture coordonnées, hors du fil principal.
    private struct DossierLocal: TransportSynchro {
        let dossier: URL

        func lister() async throws -> [SynchroDossier.Fichier] {
            // Le sous-dossier d'un profil de la famille n'existe pas avant son premier dépôt : il se lit comme vide.
            guard FileManager.default.fileExists(atPath: dossier.path(percentEncoded: false)) else { return [] }
            return try await Task.detached { try EtatSynchro.lister(dossier) }.value
        }

        func lire(_ nom: String) async throws -> Data {
            let url = dossier.appendingPathComponent(nom)
            return try await Task.detached { try EtatSynchro.lire(url) }.value
        }

        func ecrire(_ donnees: Data, nom: String) async throws {
            try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
            let url = dossier.appendingPathComponent(nom)
            try await Task.detached { try EtatSynchro.ecrire(donnees, url) }.value
        }
    }

    // MARK: Fichiers, hors du fil principal — iCloud Drive peut faire attendre un téléchargement.

    private nonisolated static func lister(_ dossier: URL) throws -> [SynchroDossier.Fichier] {
        let urls = try FileManager.default.contentsOfDirectory(at: dossier, includingPropertiesForKeys: [.contentModificationDateKey], options: [])
        return urls.map { url in
            // Pas encore téléchargé : on le demande, la lecture coordonnée attendra qu'il arrive.
            if url.lastPathComponent.hasSuffix(".icloud") { try? FileManager.default.startDownloadingUbiquitousItem(at: url) }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return SynchroDossier.Fichier(nom: url.lastPathComponent, modifieLe: date)
        }
    }

    private nonisolated static func lire(_ url: URL) throws -> Data {
        var erreurCoordination: NSError?
        var resultat: Result<Data, any Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &erreurCoordination) { lisible in
            resultat = Result { try Data(contentsOf: lisible) }
        }
        if let erreurCoordination { throw erreurCoordination }
        return try resultat.get()
    }

    nonisolated static let dossierArchives = "Sauvegardes datées"
    nonisolated static let archivesGardees = 5

    /// « Sauvegardes datées/Séance — iPhone 3F2A — 2026-09-18.json » : une par jour au plus (la dernière du jour la
    /// remplace), les cinq plus récentes de l'appareil. La synchronisation ne lit jamais ce sous-dossier.
    private nonisolated static func archiver(_ donnees: Data, dossier: URL, appareil: String, jour: String) throws {
        let archives = dossier.appendingPathComponent(dossierArchives, isDirectory: true)
        try FileManager.default.createDirectory(at: archives, withIntermediateDirectories: true)
        let prefixe = "\(SynchroDossier.prefixe)\(appareil) — "
        try ecrire(donnees, archives.appendingPathComponent("\(prefixe)\(jour).json"))
        let miennes = ((try? FileManager.default.contentsOfDirectory(atPath: archives.path)) ?? [])
            .filter { $0.hasPrefix(prefixe) && $0.hasSuffix(".json") }.sorted(by: >)
        for ancienne in miennes.dropFirst(archivesGardees) {
            try? FileManager.default.removeItem(at: archives.appendingPathComponent(ancienne))
        }
    }

    private nonisolated static func ecrire(_ donnees: Data, _ url: URL) throws {
        var erreurCoordination: NSError?
        var resultat: Result<Void, any Error> = .success(())
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &erreurCoordination) { inscriptible in
            resultat = Result { try donnees.write(to: inscriptible, options: .atomic) }
        }
        if let erreurCoordination { throw erreurCoordination }
        try resultat.get()
    }
}

/// À la racine de l'app : la synchronisation au lancement et à chaque retour dans l'app, et la confirmation d'import
/// d'une sauvegarde « .seance » reçue par AirDrop ou ouverte depuis Fichiers.
struct ReceptionEtSynchro: ViewModifier {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content
            .task { await etat.synchro.synchroniser(etat: etat, contexte: contexte, automatique: true) }
            // L'e-mail de la semaine part d'ici, à la première ouverture après le jour et l'heure choisis.
            .task { await etat.lettre.envoyerSiDu(etat: etat, contexte: contexte) }
            .onChange(of: phase) { _, nouvelle in
                guard nouvelle == .active else { return }
                Task { await etat.synchro.synchroniser(etat: etat, contexte: contexte, automatique: true) }
            }
            .alert("Importer cette sauvegarde ?", isPresented: Binding { etat.sauvegardeRecue != nil } set: { if !$0 { etat.sauvegardeRecue = nil } },
                   presenting: etat.sauvegardeRecue) { url in
                Button("Importer") { importer(url) }
                Button("Annuler", role: .cancel) {}
            } message: { url in
                Text("« \(url.lastPathComponent) » : Séance ajoute ce qui manque et complète tes titres, sans rien effacer.")
            }
    }

    private func importer(_ url: URL) {
        let acces = url.startAccessingSecurityScopedResource()
        defer { if acces { url.stopAccessingSecurityScopedResource() } }
        do {
            let bilan = try ImportSauvegarde.importer(try Data(contentsOf: url), etat: etat, contexte: contexte)
            etat.confirmer(bilan.estVide ? "Rien de nouveau dans cette sauvegarde" : "Importé : \(bilan.phrase)", symbole: "square.and.arrow.down")
        } catch {
            etat.confirmer("Ce fichier n'est pas une sauvegarde de Séance", symbole: "exclamationmark.triangle")
            etat.journal.noter(.general, "Une sauvegarde reçue n'a pas pu être importée.", erreur: error)
        }
    }
}
