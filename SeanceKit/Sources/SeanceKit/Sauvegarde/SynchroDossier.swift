import Foundation

/// Synchronisation par un dossier partagé (iCloud Drive, ou n'importe quel dossier de Fichiers) : chaque appareil y
/// dépose **son** fichier, « Séance — iPhone 3F2A.json », et importe ceux des autres quand ils ont changé. Deux
/// appareils n'écrivent jamais le même fichier : aucun conflit à arbitrer, et le service de fichiers fait le transport.
public enum SynchroDossier {
    /// « Tester une alerte » depuis l'Apple TV, qui n'affiche pas de notification : elle dépose ce fichier, et l'iPhone
    /// qui le découvre à sa synchronisation prévient (l'Apple Watch suit l'iPhone). Hors des fichiers d'appareil.
    public static let fichierEssaiAlerte = "essai-alerte.json"

    /// Vrai si le dossier contient une demande d'essai plus récente que la dernière traitée, et de moins d'un jour.
    public static func essaiAlerteDemande(_ fichiers: [Fichier], derniereTraitee: Date?, maintenant: Date = .now) -> Date? {
        guard let demande = fichiers.first(where: { nomReel($0.nom) == fichierEssaiAlerte })?.modifieLe,
              maintenant.timeIntervalSince(demande) < 86_400, demande > (derniereTraitee ?? .distantPast) else { return nil }
        return demande
    }

    public static let prefixe = "Séance — "
    public static let suffixe = ".json"

    public struct Fichier: Sendable, Equatable {
        public var nom: String
        public var modifieLe: Date

        public init(nom: String, modifieLe: Date) {
            self.nom = nom
            self.modifieLe = modifieLe
        }
    }

    /// « Séance — iPhone 3F2A.json » : le genre d'appareil, et quatre caractères qui distinguent deux iPhone.
    public static func nomFichier(appareil: String) -> String {
        prefixe + appareil + suffixe
    }

    /// iCloud Drive montre un fichier pas encore téléchargé sous le nom « .Nom.json.icloud » : voici son vrai nom.
    public static func nomReel(_ nom: String) -> String {
        guard nom.hasPrefix("."), nom.hasSuffix(".icloud") else { return nom }
        return String(nom.dropFirst().dropLast(".icloud".count))
    }

    /// Les fichiers des autres appareils qui ont changé depuis leur dernier import, le plus ancien d'abord.
    /// Les sauvegardes exportées à la main (« Séance 2026-09-18.json ») ne sont pas des fichiers d'appareil.
    public static func aImporter(_ fichiers: [Fichier], propre: String, dejaImportes: [String: Date]) -> [Fichier] {
        var parNom: [String: Fichier] = [:]
        for fichier in fichiers {
            let nom = nomReel(fichier.nom)
            guard nom.hasPrefix(prefixe), nom.hasSuffix(suffixe), nom != propre else { continue }
            let candidat = Fichier(nom: nom, modifieLe: fichier.modifieLe)
            if let connu = parNom[nom], connu.modifieLe >= candidat.modifieLe { continue }
            parNom[nom] = candidat
        }
        return parNom.values
            .filter { fichier in dejaImportes[fichier.nom].map { fichier.modifieLe > $0 } ?? true }
            .sorted { ($0.modifieLe, $0.nom) < ($1.modifieLe, $1.nom) }
    }
}

/// Le dossier où les appareils déposent leurs fichiers, quel qu'il soit : un dossier d'iCloud Drive ou de Fichiers
/// (iPhone, iPad, Mac), ou un dossier du NAS lu en SMB (EF-144) — le seul que l'Apple TV puisse atteindre, elle qui
/// n'a ni Fichiers ni iCloud Drive. Le moteur de synchronisation ne connaît que ces trois gestes.
public protocol TransportSynchro: Sendable {
    /// Les fichiers à la racine du dossier, avec leur date de modification. Un dossier absent se lit comme vide.
    func lister() async throws -> [SynchroDossier.Fichier]
    func lire(_ nom: String) async throws -> Data
    /// Écrit, ou remplace, le fichier de ce nom ; crée le dossier s'il manque.
    func ecrire(_ donnees: Data, nom: String) async throws
}
