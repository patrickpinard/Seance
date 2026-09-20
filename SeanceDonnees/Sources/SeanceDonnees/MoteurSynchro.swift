import CryptoKit
import Foundation
import SeanceKit
import SwiftData

/// Une synchronisation de bout en bout par un dossier partagé, quel que soit le transport (iCloud Drive, NAS) et
/// l'appareil (iPhone, iPad, Mac, Apple TV) : lire les fichiers des autres qui ont changé, fusionner — suppressions et
/// retours en arrière compris, voir `ServiceSynchro` —, puis déposer le nôtre s'il a changé.
///
/// Plusieurs transports peuvent servir le même appareil (un dossier d'iCloud Drive **et** le NAS) : ils partagent le
/// nom de l'appareil et l'état de la synchronisation précédente, mais chacun retient sous son `espace` ce qu'il a déjà
/// importé et l'empreinte de ce qu'il a déposé.
@MainActor
public struct MoteurSynchro {
    public struct Bilan {
        public let recus: [ServiceSynchro.Recu]
        /// Les données déposées, quand notre fichier a changé ; `nil` s'il était déjà à jour.
        public let deposees: Data?
    }

    public let contexte: ModelContext
    public let transport: any TransportSynchro
    /// « iPhone 3F2A », « Apple TV 9C01 » : le nom du fichier de cet appareil en découle.
    public let appareil: String
    /// Préfixe des clés de réglage de ce transport : « synchro » pour le dossier, « synchro.nas » pour le NAS.
    public let espace: String
    /// L'état déposé à la synchronisation précédente, commun aux transports de l'appareil, hors du dossier partagé.
    public let fichierEtat: URL
    public let defauts: UserDefaults

    public init(contexte: ModelContext, transport: any TransportSynchro, appareil: String, espace: String, fichierEtat: URL,
                defauts: UserDefaults = .standard) {
        self.contexte = contexte
        self.transport = transport
        self.appareil = appareil
        self.espace = espace
        self.fichierEtat = fichierEtat
        self.defauts = defauts
    }

    private var cleImportes: String { "\(espace).importes" }
    private var cleEmpreinte: String { "\(espace).empreinte" }

    /// Le transport change de dossier, ou s'éteint : ce qu'il avait importé et déposé ne vaut plus.
    public func oublier() {
        defauts.removeObject(forKey: cleImportes)
        defauts.removeObject(forKey: cleEmpreinte)
    }

    /// `preferences` : les réglages actuels de l'app, relus après `appliquer` pour le fichier à déposer.
    /// `appliquer` : les réglages modifiés plus récemment ailleurs (à remplacer), puis ceux de chaque fichier reçu
    /// (à reprendre s'ils n'ont jamais été touchés ici). L'Apple TV, sans réglages partagés, laisse les deux vides.
    public func synchroniser(
        preferences: () -> [String: Sauvegarde.Preference] = { [:] },
        appliquer: (_ remplacees: [String: Sauvegarde.Preference], _ recues: [[String: Sauvegarde.Preference]]) -> Void = { _, _ in },
        maintenant: Date = .now
    ) async throws -> Bilan {
        // 1. Les fichiers des autres qui ont changé depuis leur dernier import.
        let propre = SynchroDossier.nomFichier(appareil: appareil)
        var importes = (defauts.dictionary(forKey: cleImportes) as? [String: Date]) ?? [:]
        let presents = try await transport.lister()
        var recues: [(nom: String, sauvegarde: Sauvegarde)] = []
        var datesLues: [String: Date] = [:]
        for fichier in SynchroDossier.aImporter(presents, propre: propre, dejaImportes: importes) {
            // Un fichier illisible (en cours d'écriture ailleurs) sera relu la prochaine fois.
            guard let donnees = try? await transport.lire(fichier.nom), let sauvegarde = try? Sauvegarde.decoder(donnees) else { continue }
            recues.append((fichier.nom, sauvegarde))
            datesLues[fichier.nom] = fichier.modifieLe
        }

        // 2. La fusion : le plus récent l'emporte.
        let precedente = (try? Data(contentsOf: fichierEtat)).flatMap { try? Sauvegarde.decoder($0) }
        let resultat = try ServiceSynchro(contexte: contexte)
            .fusionner(recues: recues, precedente: precedente, preferences: preferences(), maintenant: maintenant)
        appliquer(resultat.preferencesRemplacees, recues.map { $0.sauvegarde.preferences ?? [:] })
        importes.merge(datesLues) { _, recente in recente }
        defauts.set(importes, forKey: cleImportes)

        // 3. Notre fichier, seulement s'il a changé : y toucher pour rien réveillerait les autres appareils.
        var aDeposer = resultat.aDeposer
        let reglages = preferences()
        aDeposer.preferences = reglages.isEmpty ? nil : reglages
        let empreinte = try Self.empreinte(aDeposer)
        var deposees: Data?
        if empreinte != defauts.string(forKey: cleEmpreinte) {
            let donnees = try aDeposer.encoder()
            try await transport.ecrire(donnees, nom: propre)
            defauts.set(empreinte, forKey: cleEmpreinte)
            deposees = donnees
        }
        // Le point de comparaison de la prochaine synchronisation.
        try? FileManager.default.createDirectory(at: fichierEtat.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? aDeposer.encoder().write(to: fichierEtat, options: .atomic)
        return Bilan(recus: resultat.recus.filter { !$0.estVide }, deposees: deposees)
    }

    /// L'empreinte du contenu, hors date de création : deux exports des mêmes données ont la même.
    private static func empreinte(_ sauvegarde: Sauvegarde) throws -> String {
        var stable = sauvegarde
        stable.creeeLe = Date(timeIntervalSince1970: 0)
        return SHA256.hash(data: try stable.encoder()).map { String(format: "%02x", $0) }.joined()
    }
}
