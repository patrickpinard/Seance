import Foundation
import Testing
@testable import SeanceKit

@Suite("Vidéos personnelles")
struct VideosPersoTests {
    private func jour(_ j: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + j * 86_400)) }

    private var arbre: ArbreVideosPerso {
        ArbreVideosPerso([
            VideoPerso(chemin: "2023/Noël/Sapin.mov", taille: 10, modifieLe: jour(10)),
            VideoPerso(chemin: "2023/Noël/Cadeaux.mp4", taille: 10, modifieLe: jour(11)),
            VideoPerso(chemin: "2023/Été.mov", taille: 10, modifieLe: jour(5)),
            VideoPerso(chemin: "2024/Ski/Descente.mov", taille: 10, modifieLe: jour(40)),
            VideoPerso(chemin: "Accueil.mp4", taille: 10, modifieLe: jour(1)),
        ])
    }

    @Test func racine() {
        #expect(arbre.dossiers(dans: "").map(\.nom) == ["2024", "2023"])   // le plus récemment alimenté d'abord
        #expect(arbre.dossiers(dans: "").first { $0.nom == "2023" }?.nombre == 3)
        #expect(arbre.videos(dans: "").map(\.nom) == ["Accueil"])
    }

    @Test func sousDossier() {
        #expect(arbre.dossiers(dans: "2023").map(\.chemin) == ["2023/Noël"])
        #expect(arbre.videos(dans: "2023").map(\.nom) == ["Été"])
        #expect(arbre.videos(dans: "2023/Noël").map(\.nom) == ["Cadeaux", "Sapin"])
        #expect(arbre.dossiers(dans: "2023/Noël").isEmpty)
    }

    /// « 2023 » ne doit pas avaler « 2023 bis ».
    @Test func prefixeExact() {
        let arbre = ArbreVideosPerso([VideoPerso(chemin: "2023 bis/A.mov", taille: 1), VideoPerso(chemin: "2023/B.mov", taille: 1)])
        #expect(arbre.videos(dans: "2023").map(\.nom) == ["B"])
        #expect(arbre.dossiers(dans: "2023").isEmpty)
    }

    @Test func recentesEtNoms() {
        #expect(arbre.recentes(2).map(\.nom) == ["Descente", "Cadeaux"])
        #expect(VideoPerso(chemin: "2023/Noël 2023.final.mov", taille: 1).nom == "Noël 2023.final")
    }

    @Test func reglages() {
        let films = ReglagesNAS(hote: "192.168.1.220", partage: "Films", dossiers: ["Films"], utilisateur: "admin")
        let videos = ReglagesVideosPerso.depuis(films)
        #expect(!videos.actif && videos.estComplet)
        #expect(videos.acces.partage == "video" && videos.acces.dossiers.isEmpty)
        #expect(videos.partageLeCompte(de: films))
        var ailleurs = videos
        ailleurs.acces.hote = "192.168.1.50"
        #expect(!ailleurs.partageLeCompte(de: films))
    }
}
