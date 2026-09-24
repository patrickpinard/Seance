import Foundation
import SeanceKit
import Testing
@testable import SeanceNAS

/// Inventaire du NAS réel, pour un parcours de test : combien de vidéos, dans quels formats, et laquelle essayer.
/// Ne tourne que si le mot de passe est dans l'environnement — jamais en ligne de commande :
///
///   NAS_MDP=$(cat outils/.mdp-nas) swift test --filter InventaireReel
///
@Suite("Inventaire du NAS réel", .enabled(if: ProcessInfo.processInfo.environment["NAS_MDP"] != nil))
struct InventaireReelTests {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    private func explorateur(_ partage: String) -> ExplorateurSMB {
        let reglages = ReglagesNAS(hote: env["NAS_HOTE"] ?? "192.168.1.220", partage: partage,
                                   dossiers: [], utilisateur: env["NAS_COMPTE"] ?? "admin")
        return ExplorateurSMB(reglages: reglages, motDePasse: env["NAS_MDP"] ?? "")
    }

    @Test("Les formats des vidéos personnelles")
    func formatsVideosPerso() async throws {
        let videos = try await explorateur(env["NAS_PARTAGE_VIDEOS"] ?? "Videos").listerVideosPerso(dossiers: [])
        var parExtension: [String: [VideoPerso]] = [:]
        for video in videos {
            parExtension[(video.chemin as NSString).pathExtension.lowercased(), default: []].append(video)
        }
        print("VIDÉOS PERSONNELLES : \(videos.count)")
        for (ext, liste) in parExtension.sorted(by: { $0.value.count > $1.value.count }) {
            let petit = liste.min { $0.taille < $1.taille }!
            print("  \(ext.uppercased()) × \(liste.count) — plus petit : \(petit.chemin) (\(petit.taille / 1_048_576) Mo)")
        }
    }

    @Test("Les formats des films et des séries")
    func formatsFilms() async throws {
        let fichiers = try await explorateur(env["NAS_PARTAGE_FILMS"] ?? "Films").listerVideos(dossiers: ["Films", "Séries"])
        var parExtension: [String: Int] = [:]
        for fichier in fichiers {
            parExtension[(fichier.chemin as NSString).pathExtension.lowercased(), default: 0] += 1
        }
        print("FILMS ET SÉRIES : \(fichiers.count)")
        for (ext, nombre) in parExtension.sorted(by: { $0.value > $1.value }) { print("  \(ext.uppercased()) × \(nombre)") }
    }
}
