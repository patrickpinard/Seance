import AMSMB2
import Foundation
import SeanceKit

/// Un fichier du NAS lu par tranches, pour le lecteur intégré de Séance (`RelaisVideo`). Rien n'est copié sur
/// l'appareil : chaque plage demandée par le lecteur devient une lecture SMB.
///
/// La connexion est gardée d'une tranche à l'autre — une vidéo en demande des centaines — et rouverte d'elle-même
/// si le NAS l'a laissée tomber.
public struct SourceVideoSMB: SourceVideo {
    private let session: SessionSMB
    private let chemin: String

    public init(reglages: ReglagesNAS, motDePasse: String, chemin: String) {
        session = SessionSMB(explorateur: ExplorateurSMB(reglages: reglages, motDePasse: motDePasse))
        self.chemin = chemin
    }

    /// Ouvre la connexion pour toute la lecture. À fermer avec `fermer()` quand le lecteur se referme.
    public func ouvrir() async {
        await session.ouvrir()
    }

    public func fermer() async {
        await session.fermer()
    }

    public func taille() async throws -> UInt64 {
        let chemin = chemin
        return try await session.avec { client in
            let attributs = try await client.attributesOfItem(atPath: chemin)
            if let taille = attributs[.fileSizeKey] as? Int64 { return UInt64(max(taille, 0)) }
            if let taille = attributs[.fileSizeKey] as? Int { return UInt64(max(taille, 0)) }
            return 0
        }
    }

    public func lire(_ plage: Range<UInt64>) async throws -> Data {
        let chemin = chemin
        return try await session.avec { client in
            try await client.contents(atPath: chemin, range: plage, progress: nil)
        }
    }
}
