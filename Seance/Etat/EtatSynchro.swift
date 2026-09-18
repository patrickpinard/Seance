import CryptoKit
import Foundation
import SeanceDonnees
import SeanceKit
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
    private(set) var nomDossier: String?
    private(set) var derniereSynchro: Date?
    private(set) var dernierMessage: String?
    private(set) var enCours = false

    var automatique: Bool {
        didSet { UserDefaults.standard.set(automatique, forKey: Cle.automatique) }
    }

    private enum Cle {
        static let signet = "synchro.dossier"
        static let nomDossier = "synchro.nomDossier"
        static let automatique = "synchro.automatique"
        static let appareil = "synchro.appareil"
        static let importes = "synchro.importes"
        static let empreinte = "synchro.empreinte"
        static let derniere = "synchro.derniere"
    }

    /// Pas plus d'une synchronisation automatique toutes les deux minutes.
    private static let intervalleMinimal: TimeInterval = 120

    init() {
        let defauts = UserDefaults.standard
        nomDossier = defauts.data(forKey: Cle.signet) == nil ? nil : defauts.string(forKey: Cle.nomDossier)
        automatique = defauts.object(forKey: Cle.automatique) == nil ? true : defauts.bool(forKey: Cle.automatique)
        derniereSynchro = defauts.object(forKey: Cle.derniere) as? Date
        #if DEBUG
        // Tests d'interface : le dossier est imposé au lancement, sans sélecteur de fichiers ni iCloud Drive.
        if let chemin = ProcessInfo.processInfo.environment["SEANCE_SYNCHRO_DOSSIER"] {
            try? choisir(URL(fileURLWithPath: chemin, isDirectory: true))
        }
        #endif
    }

    var estConfiguree: Bool { nomDossier != nil }

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
        try? FileManager.default.removeItem(at: Self.fichierEtat)
        nomDossier = url.lastPathComponent
        dernierMessage = nil
    }

    func oublier() {
        let defauts = UserDefaults.standard
        [Cle.signet, Cle.nomDossier, Cle.importes, Cle.empreinte, Cle.derniere].forEach(defauts.removeObject)
        try? FileManager.default.removeItem(at: Self.fichierEtat)
        nomDossier = nil
        derniereSynchro = nil
        dernierMessage = nil
    }

    /// Importe les fichiers des autres appareils qui ont changé, puis dépose le nôtre s'il a changé.
    /// `automatique` : au retour dans l'app ; silencieuse s'il n'y a rien, et pas plus d'une fois toutes les deux minutes.
    func synchroniser(etat: EtatApp, contexte: ModelContext, automatique declenchementAuto: Bool = false) async {
        guard !enCours, let signet = UserDefaults.standard.data(forKey: Cle.signet) else { return }
        if declenchementAuto {
            guard automatique else { return }
            if let derniere = derniereSynchro, Date.now.timeIntervalSince(derniere) < Self.intervalleMinimal { return }
        }
        enCours = true
        defer { enCours = false }

        do {
            var perime = false
            let dossier = try URL(resolvingBookmarkData: signet, options: [], relativeTo: nil, bookmarkDataIsStale: &perime)
            let acces = dossier.startAccessingSecurityScopedResource()
            defer { if acces { dossier.stopAccessingSecurityScopedResource() } }
            if perime, let neuf = try? dossier.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(neuf, forKey: Cle.signet)
            }

            // 1. Les fichiers des autres qui ont changé depuis leur dernier import.
            let propre = SynchroDossier.nomFichier(appareil: appareil)
            var importes = (UserDefaults.standard.dictionary(forKey: Cle.importes) as? [String: Date]) ?? [:]
            let presents = try await Task.detached { try Self.lister(dossier) }.value
            var recues: [(nom: String, sauvegarde: Sauvegarde)] = []
            var datesLues: [String: Date] = [:]
            for fichier in SynchroDossier.aImporter(presents, propre: propre, dejaImportes: importes) {
                let url = dossier.appendingPathComponent(fichier.nom)
                // Un fichier illisible (en cours d'écriture ailleurs) sera relu la prochaine fois.
                guard let donnees = try? await Task.detached(operation: { try Self.lire(url) }).value,
                      let sauvegarde = try? Sauvegarde.decoder(donnees) else { continue }
                recues.append((fichier.nom, sauvegarde))
                datesLues[fichier.nom] = fichier.modifieLe
            }

            // 2. La fusion : suppressions et retours en arrière compris, le plus récent l'emporte.
            let resultat = try ServiceSynchro(contexte: contexte)
                .fusionner(recues: recues, precedente: etatPrecedent(), preferences: PreferencesSauvegardees.lire())
            _ = PreferencesSauvegardees.appliquer(resultat.preferencesRemplacees, etat: etat, remplacer: true)
            // Les réglages jamais touchés ici se reprennent aussi, comme à l'import d'un fichier.
            for (_, sauvegarde) in recues { _ = PreferencesSauvegardees.appliquer(sauvegarde.preferences ?? [:], etat: etat) }
            importes.merge(datesLues) { _, recente in recente }
            UserDefaults.standard.set(importes, forKey: Cle.importes)
            var recus: [String] = []
            for recu in resultat.recus where !recu.estVide {
                recus.append("\(ImportSauvegarde.phrase(recu)) (\(Self.nomAppareil(recu.nom)))")
            }
            if !recus.isEmpty {
                etat.ou.actualiserLocal(contexte: contexte)
                Task { await etat.alertes.planifier(contexte: contexte, tmdb: etat.tmdb) }
            }

            // 3. Notre fichier, seulement s'il a changé : y toucher pour rien réveillerait les autres appareils.
            //    Il devient aussi le point de comparaison de la prochaine synchronisation.
            var aDeposer = resultat.aDeposer
            aDeposer.preferences = PreferencesSauvegardees.lire()
            let empreinte = try Self.empreinte(aDeposer)
            var depose = false
            if empreinte != UserDefaults.standard.string(forKey: Cle.empreinte) {
                let donnees = try aDeposer.encoder()
                let cible = dossier.appendingPathComponent(propre)
                try await Task.detached { try Self.ecrire(donnees, cible) }.value
                UserDefaults.standard.set(empreinte, forKey: Cle.empreinte)
                depose = true
                // Un filet de sécurité : l'état du jour, daté, à côté ; les cinq derniers de cet appareil sont gardés.
                let nomAppareil = appareil
                let jour = DateTMDB(.now).description
                try? await Task.detached { try Self.archiver(donnees, dossier: dossier, appareil: nomAppareil, jour: jour) }.value
            }
            enregistrerEtat(aDeposer)

            derniereSynchro = .now
            UserDefaults.standard.set(Date.now, forKey: Cle.derniere)
            if !recus.isEmpty {
                dernierMessage = "Reçu : \(recus.joined(separator: " ; "))."
                etat.confirmer("Synchronisé : \(recus.joined(separator: " ; "))", symbole: "arrow.triangle.2.circlepath")
                AccessibilityNotification.Announcement("Synchronisé : \(recus.joined(separator: ", "))").post()
            } else if !declenchementAuto {
                dernierMessage = depose ? "Tes données ont été déposées dans le dossier. Rien de nouveau des autres appareils."
                                        : "Tout est à jour."
            }
        } catch {
            dernierMessage = "La synchronisation n'a pas abouti : le dossier est-il toujours là, et iCloud Drive disponible ?"
            etat.journal.noter(.general, "La synchronisation par le dossier n'a pas abouti.", erreur: error)
        }
    }

    /// L'état déposé à la synchronisation précédente : c'est en s'y comparant que l'appareil sait ce qu'il a modifié
    /// ou supprimé depuis. Gardé hors du dossier partagé, qu'un autre appareil pourrait avoir vidé.
    private static var fichierEtat: URL {
        let dossier = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        return dossier.appendingPathComponent("synchro-etat.json")
    }

    private func etatPrecedent() -> Sauvegarde? {
        (try? Data(contentsOf: Self.fichierEtat)).flatMap { try? Sauvegarde.decoder($0) }
    }

    private func enregistrerEtat(_ sauvegarde: Sauvegarde) {
        try? sauvegarde.encoder().write(to: Self.fichierEtat, options: .atomic)
    }

    /// « Séance — iPad 77C1.json » → « iPad ».
    private static func nomAppareil(_ fichier: String) -> String {
        let nom = fichier.dropFirst(SynchroDossier.prefixe.count).dropLast(SynchroDossier.suffixe.count)
        return nom.split(separator: " ").first.map(String.init) ?? String(nom)
    }

    /// L'empreinte du contenu, hors date de création : deux exports des mêmes données ont la même.
    private static func empreinte(_ sauvegarde: Sauvegarde) throws -> String {
        var stable = sauvegarde
        stable.creeeLe = Date(timeIntervalSince1970: 0)
        return SHA256.hash(data: try stable.encoder()).map { String(format: "%02x", $0) }.joined()
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
