import Foundation
import SeanceDonnees
import SeanceKit

/// Dossiers propres à Séance. Sur le Mac, l'app n'a pas de conteneur à elle : ses fichiers vont dans
/// un sous-dossier à son nom, jamais à la racine de la bibliothèque de l'utilisateur.
enum DossiersSeance {
    static let identifiant = "ch.patrick.seance"

    static var reglages: URL {
        #if targetEnvironment(macCatalyst)
        URL.applicationSupportDirectory.appending(path: identifiant)
        #else
        URL.applicationSupportDirectory
        #endif
    }

    static var images: URL {
        URL.cachesDirectory.appending(path: identifiant).appending(path: "Images")
    }

    /// Les réponses de TMDB gardées sur disque (voir `CacheTMDB`).
    static var reponsesTMDB: URL {
        URL.cachesDirectory.appending(path: identifiant).appending(path: "TMDB")
    }
}

/// Place occupée par Séance sur l'appareil, pour À propos.
struct Volumetrie: Equatable, Sendable {
    /// L'app elle-même, widgets compris.
    var application: Int64 = 0
    /// Listes, épisodes vus, notes, goûts, soirée : ce que la sauvegarde contient.
    var donnees: Int64 = 0
    /// Fiches, programmes TV, bibliothèque du NAS, alertes et échéances : se reconstruit tout seul.
    var cache: Int64 = 0
    /// Affiches et images de fond déjà téléchargées.
    var images: Int64 = 0
    /// Vignettes et liste des prochains épisodes pour les widgets, journal.
    var divers: Int64 = 0

    var total: Int64 {
        application + donnees + cache + images + divers
    }

    static func mesurer() async -> Volumetrie {
        await Task.detached(priority: .utility) { calculer() }.value
    }

    private static func calculer() -> Volumetrie {
        var volumetrie = Volumetrie()
        volumetrie.application = taille(Bundle.main.bundleURL)
        volumetrie.images = taille(DossiersSeance.images)
        volumetrie.cache += taille(DossiersSeance.reponsesTMDB)
        volumetrie.divers = taille(DossiersSeance.reglages.appending(path: "journal.json"))
        if let partage = EntrepotSeance.dossierPartage {
            let magasins = partage.appending(path: "Library/Application Support")
            volumetrie.donnees = fichiers(commencantPar: "Utilisateur.store", dans: magasins)
            volumetrie.cache += fichiers(commencantPar: "Cache.store", dans: magasins)
            volumetrie.divers += taille(partage.appending(path: "Vignettes")) + taille(partage.appending(path: InstantaneWidgets.nomFichier))
        }
        return volumetrie
    }

    /// Un magasin SwiftData et ses fichiers compagnons (`-wal`, `-shm`).
    private static func fichiers(commencantPar prefixe: String, dans dossier: URL) -> Int64 {
        let noms = (try? FileManager.default.contentsOfDirectory(atPath: dossier.path(percentEncoded: false))) ?? []
        return noms.filter { $0.hasPrefix(prefixe) }.reduce(0) { $0 + taille(dossier.appending(path: $1)) }
    }

    /// Taille sur le disque d'un fichier, ou d'un dossier et de tout son contenu.
    static func taille(_ url: URL) -> Int64 {
        let cles: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let valeurs = try? url.resourceValues(forKeys: cles) else { return 0 }
        if valeurs.isRegularFile == true {
            return Int64(valeurs.totalFileAllocatedSize ?? valeurs.fileAllocatedSize ?? 0)
        }
        guard let parcours = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(cles)) else { return 0 }
        var total: Int64 = 0
        while let fichier = parcours.nextObject() as? URL {
            guard let v = try? fichier.resourceValues(forKeys: cles), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }
}
