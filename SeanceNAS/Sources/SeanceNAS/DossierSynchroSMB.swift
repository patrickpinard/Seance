import AMSMB2
import Foundation
import SeanceKit

/// Le dossier de synchronisation sur le NAS (EF-144) : « Séance », à la racine du partage des films. Chaque appareil y
/// dépose son fichier et y lit ceux des autres — c'est ainsi que les listes de l'iPhone arrivent sur l'Apple TV, qui
/// n'a ni Fichiers ni iCloud Drive. Le compte du NAS doit pouvoir **écrire** dans le partage.
public struct DossierSynchroSMB: TransportSynchro {
    public static let dossierParDefaut = "Séance"

    private let explorateur: ExplorateurSMB
    private let dossier: String

    public init(reglages: ReglagesNAS, motDePasse: String, dossier: String = DossierSynchroSMB.dossierParDefaut) {
        explorateur = ExplorateurSMB(reglages: reglages, motDePasse: motDePasse)
        self.dossier = dossier
    }

    public func lister() async throws -> [SynchroDossier.Fichier] {
        let dossier = dossier
        return try await explorateur.avecPartage { client in
            // Pas encore de dossier : personne n'a rien déposé, ce n'est pas une erreur.
            guard let elements = try? await client.contentsOfDirectory(atPath: dossier) else { return [] }
            return elements.compactMap { element in
                guard (element[.isDirectoryKey] as? Bool) != true, let nom = element[.nameKey] as? String else { return nil }
                // Le NAS peut rendre les accents décomposés : les noms se comparent composés, comme ceux de l'app.
                return SynchroDossier.Fichier(nom: nom.precomposedStringWithCanonicalMapping,
                                              modifieLe: (element[.contentModificationDateKey] as? Date) ?? .distantPast)
            }
        }
    }

    public func lire(_ nom: String) async throws -> Data {
        let dossier = dossier
        return try await explorateur.avecPartage { client in
            // Le nom réel, tel que le NAS l'écrit (accents composés ou non).
            let presents = ((try? await client.contentsOfDirectory(atPath: dossier)) ?? []).compactMap { $0[.nameKey] as? String }
            let reel = presents.first { $0.precomposedStringWithCanonicalMapping == nom } ?? nom
            return try await client.contents(atPath: "\(dossier)/\(reel)", range: Range<UInt64>?.none, progress: nil)
        }
    }

    public func ecrire(_ donnees: Data, nom: String) async throws {
        let dossier = dossier
        try await explorateur.avecPartage { client in
            if (try? await client.attributesOfItem(atPath: dossier)) == nil {
                try await client.createDirectory(atPath: dossier)
            }
            let presents = ((try? await client.contentsOfDirectory(atPath: dossier)) ?? []).compactMap { $0[.nameKey] as? String }
            let reel = presents.first { $0.precomposedStringWithCanonicalMapping == nom } ?? nom
            let cible = "\(dossier)/\(reel)"
            // Écrire à côté puis remplacer : un autre appareil ne lit jamais un fichier à moitié écrit.
            let provisoire = "\(dossier)/.\(UUID().uuidString.prefix(8)).tmp"
            try await client.write(data: donnees, toPath: provisoire, progress: nil)
            try? await client.removeItem(atPath: cible)
            try await client.moveItem(atPath: provisoire, toPath: cible)
        }
    }
}
