import AMSMB2
import Foundation
import SeanceKit

public enum ErreurNAS: LocalizedError, Equatable {
    case adresseInvalide
    case dossierAbsent(String)
    case motDePasseManquant
    case reseauLocalRefuse
    case injoignable(String)

    public var errorDescription: String? {
        switch self {
        case .adresseInvalide: "L'adresse du NAS n'est pas valide."
        case .dossierAbsent(let dossier): "Le dossier « \(dossier) » est introuvable sur le partage."
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
            for dossier in dossiers {
                let elements: [[URLResourceKey: Any]]
                do {
                    elements = try await client.contentsOfDirectory(atPath: dossier, recursive: true)
                } catch let erreur as POSIXError where erreur.code == .ENOENT {
                    throw ErreurNAS.dossierAbsent(dossier)
                }
                for element in elements {
                    guard (element[.isDirectoryKey] as? Bool) != true,
                          let chemin = element[.pathKey] as? String,
                          AnalyseNomFichier.extensionsVideo.contains((chemin as NSString).pathExtension.lowercased())
                    else { continue }
                    let taille = (element[.fileSizeKey] as? Int64) ?? Int64((element[.fileSizeKey] as? Int) ?? 0)
                    let relatif = chemin.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    fichiers.append(FichierDistant(chemin: relatif, taille: taille))
                }
            }
            return fichiers
        }
    }

    /// EF-87 : ouvre le partage et compte les éléments de premier niveau de chaque dossier déclaré.
    public func tester() async throws -> [String: Int] {
        try await avecPartage { client in
            var comptes: [String: Int] = [:]
            for dossier in reglages.dossiers {
                do {
                    comptes[dossier] = try await client.contentsOfDirectory(atPath: dossier).count
                } catch {
                    throw ErreurNAS.dossierAbsent(dossier)
                }
            }
            return comptes
        }
    }

    private func avecPartage<Resultat: Sendable>(_ travail: (SMB2Manager) async throws -> Resultat) async throws -> Resultat {
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
