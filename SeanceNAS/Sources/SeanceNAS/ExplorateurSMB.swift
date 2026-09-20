import AMSMB2
import Foundation
import SeanceKit

public enum ErreurNAS: LocalizedError, Equatable {
    case adresseInvalide
    case dossierAbsent(String, presents: [String])
    case motDePasseManquant
    case reseauLocalRefuse
    case injoignable(String)

    public var errorDescription: String? {
        switch self {
        case .adresseInvalide: "L'adresse du NAS n'est pas valide."
        case .dossierAbsent(let dossier, let presents):
            presents.isEmpty
                ? "Le dossier « \(dossier) » est introuvable sur le partage."
                : "Le dossier « \(dossier) » est introuvable sur le partage. Dossiers présents : \(presents.joined(separator: ", "))."
        case .motDePasseManquant: "Enregistre d'abord le mot de passe du NAS."
        case .reseauLocalRefuse:
            "iOS bloque l'accès au réseau local. Active Séance dans Réglages › Confidentialité et sécurité › Réseau local, puis réessaie."
        case .injoignable(let detail):
            "NAS injoignable (\(detail)). Vérifie que l'iPhone est sur le Wi-Fi de la maison et que l'adresse du NAS est la bonne."
        }
    }

    /// Traduit les erreurs réseau et SMB en une phrase qui dit quoi faire.
    public static func message(_ erreur: any Error) -> String {
        if let nas = erreur as? ErreurNAS { return nas.errorDescription ?? "" }
        // libsmb2 garde la vraie cause dans le texte et renvoie parfois un code générique.
        let texte = erreur.localizedDescription.lowercased()
        if texte.contains("no route to host") || texte.contains("network is unreachable") || texte.contains("host is down") {
            return ErreurNAS.reseauLocalRefuse.errorDescription ?? ""
        }
        if texte.contains("logon_failure") || texte.contains("logon failure") || texte.contains("access_denied") || texte.contains("access denied") {
            return "Le NAS refuse l'utilisateur ou le mot de passe."
        }
        if texte.contains("bad_network_name") || texte.contains("bad network name") {
            return "Partage introuvable sur le NAS : vérifie son nom."
        }
        guard let posix = erreur as? POSIXError else { return erreur.localizedDescription }
        switch posix.code {
        case .EACCES, .EPERM, .EAUTH, .ENEEDAUTH:
            return "Le NAS refuse l'utilisateur ou le mot de passe."
        case .EHOSTUNREACH, .ENETUNREACH, .EHOSTDOWN:
            return ErreurNAS.reseauLocalRefuse.errorDescription ?? ""
        case .ETIMEDOUT, .ECONNREFUSED, .ENOTCONN, .ENETDOWN:
            return "NAS injoignable. Vérifie que l'iPhone est sur le Wi-Fi de la maison et que le NAS est allumé."
        case .ENOENT, .ENODEV:
            return "Partage ou dossier introuvable sur le NAS."
        default:
            return "Erreur du NAS : \(posix.localizedDescription)"
        }
    }
}

/// Lit le NAS en SMB direct : sur iPhone, aucune app ne peut monter un partage comme le fait macOS.
/// Chaque opération ouvre puis referme sa connexion ; seuls les dossiers déclarés sont lus.
public struct ExplorateurSMB: ExplorateurFichiers {
    public let reglages: ReglagesNAS
    private let motDePasse: String

    public init(reglages: ReglagesNAS, motDePasse: String) {
        self.reglages = reglages
        self.motDePasse = motDePasse
    }

    public func listerVideos(dossiers: [String]) async throws -> [FichierDistant] {
        try await avecPartage { client in
            var fichiers: [FichierDistant] = []
            for dossier in try await Self.resoudre(dossiers, client: client) {
                fichiers += try await Self.parcourir(dossier, client: client)
            }
            return fichiers
        }
    }

    /// Les vidéos personnelles : les dossiers donnés, ou tout le partage s'il n'y en a aucun, avec la date de chaque fichier.
    public func listerVideosPerso(dossiers: [String]) async throws -> [VideoPerso] {
        try await avecPartage { client in
            var fichiers: [FichierDistant] = []
            if dossiers.isEmpty {
                fichiers = try await Self.parcourir("", client: client)
            } else {
                for dossier in try await Self.resoudre(dossiers, client: client) { fichiers += try await Self.parcourir(dossier, client: client) }
            }
            return fichiers.map { VideoPerso(chemin: $0.chemin, taille: $0.taille, modifieLe: $0.modifieLe) }
        }
    }

    /// Profondeur maximale : `Séries/Nom/Saison 01` en demande trois ; au-delà, sans doute une boucle.
    static let profondeurMax = 6

    /// Parcourt un dossier et ses sous-dossiers en assemblant les chemins avec les noms exacts du NAS.
    /// La lecture récursive d'AMSMB2 reconstruit les chemins par une URL, qui peut réécrire les accents
    /// (« Séries ») : le NAS ne retrouvait alors plus les sous-dossiers. Un sous-dossier illisible est
    /// ignoré plutôt que de faire échouer toute l'analyse.
    static func parcourir(_ dossier: String, client: SMB2Manager, profondeur: Int = 0) async throws -> [FichierDistant] {
        var fichiers: [FichierDistant] = []
        for element in try await client.contentsOfDirectory(atPath: dossier) {
            guard let nom = element[.nameKey] as? String, retenu(nom) else { continue }
            let chemin = dossier.isEmpty ? nom : dossier + "/" + nom   // la racine du partage n'a pas de nom
            if (element[.isDirectoryKey] as? Bool) == true {
                guard profondeur < profondeurMax else { continue }
                do {
                    fichiers += try await parcourir(chemin, client: client, profondeur: profondeur + 1)
                } catch let erreur as POSIXError where [.ENOENT, .EACCES, .EPERM, .ENOTDIR].contains(erreur.code) {
                    continue
                }
            } else if AnalyseNomFichier.extensionsVideo.contains((nom as NSString).pathExtension.lowercased()) {
                let taille = (element[.fileSizeKey] as? Int64) ?? Int64((element[.fileSizeKey] as? Int) ?? 0)
                fichiers.append(FichierDistant(chemin: chemin, taille: taille, modifieLe: element[.contentModificationDateKey] as? Date))
            }
        }
        return fichiers
    }

    /// Écarte les fichiers cachés et les dossiers techniques du Synology (`@eaDir`, `#recycle`).
    static func retenu(_ nom: String) -> Bool {
        !nom.hasPrefix(".") && !nom.hasPrefix("@") && !nom.hasPrefix("#") && nom != "Thumbs.db"
    }

    /// EF-87 : ouvre le partage et compte les éléments de premier niveau de chaque dossier déclaré.
    public func tester() async throws -> [String: Int] {
        try await avecPartage { client in
            var comptes: [String: Int] = [:]
            let reels = try await Self.resoudre(reglages.dossiers, client: client)
            for (declare, reel) in zip(reglages.dossiers, reels) {
                comptes[declare] = try await client.contentsOfDirectory(atPath: reel).count
            }
            return comptes
        }
    }

    /// Retrouve le nom exact de chaque dossier déclaré à la racine du partage. Un dossier créé depuis
    /// un Mac s'écrit souvent « e » + accent combinant : « Séries » tapé sur l'iPhone ne lui est égal
    /// qu'après normalisation. La casse est ignorée aussi.
    static func resoudre(_ dossiers: [String], client: SMB2Manager) async throws -> [String] {
        let racine = try await client.contentsOfDirectory(atPath: "")
        let presents = racine
            .filter { ($0[.isDirectoryKey] as? Bool) == true }
            .compactMap { $0[.nameKey] as? String }
            .filter(retenu)
        return try dossiers.map { dossier in
            guard let reel = correspondance(dossier, parmi: presents) else {
                throw ErreurNAS.dossierAbsent(dossier, presents: presents.map(\.precomposedStringWithCanonicalMapping).sorted())
            }
            return reel
        }
    }

    static func correspondance(_ dossier: String, parmi presents: [String]) -> String? {
        func cle(_ nom: String) -> String {
            nom.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespaces).lowercased()
        }
        let voulu = cle(dossier.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        return presents.first { cle($0) == voulu }
    }

    /// Ouvre le partage, fait le travail, referme. Sert aussi au dossier de synchronisation (`DossierSynchroSMB`).
    func avecPartage<Resultat: Sendable>(_ travail: (SMB2Manager) async throws -> Resultat) async throws -> Resultat {
        guard let url = URL(string: "smb://\(reglages.hote)"),
              let client = SMB2Manager(
                  url: url,
                  credential: URLCredential(user: reglages.utilisateur, password: motDePasse, persistence: .forSession)
              )
        else { throw ErreurNAS.adresseInvalide }
        // Hors de la maison, mieux vaut un échec rapide que 60 secondes d'attente.
        client.timeout = 15

        // Déclenche l'autorisation « Réseau local » d'iOS et vérifie le port SMB avant libsmb2.
        switch await SondeReseauLocal.tester(hote: reglages.hote) {
        case .joignable: break
        case .autorisationRefusee: throw ErreurNAS.reseauLocalRefuse
        case .injoignable(let detail): throw ErreurNAS.injoignable(detail)
        }

        try await client.connectShare(name: reglages.partage)
        do {
            let resultat = try await travail(client)
            try? await client.disconnectShare()
            return resultat
        } catch {
            try? await client.disconnectShare()
            throw error
        }
    }
}
