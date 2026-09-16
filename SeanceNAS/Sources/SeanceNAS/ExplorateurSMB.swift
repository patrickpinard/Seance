import AMSMB2
import Foundation
import SeanceKit

public enum ErreurNAS: LocalizedError, Equatable {
    case adresseInvalide
    case dossierAbsent(String)

    public var errorDescription: String? {
        switch self {
        case .adresseInvalide: "L'adresse du NAS n'est pas valide."
        case .dossierAbsent(let dossier): "Le dossier « \(dossier) » est introuvable sur le partage."
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
                let elements = try await client.contentsOfDirectory(atPath: dossier, recursive: true)
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
