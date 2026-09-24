import Foundation
import Testing
@testable import SeanceKit

@Suite("Positions de lecture (reprendre où tu en étais)")
struct PositionsLectureTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Une vidéo entamée se reprend, pas une vidéo à peine commencée ni finie")
    func aReprendre() {
        var positions = PositionsLecture()
        positions.noter("Films/Interstellar.mkv", secondes: 3792, duree: 10_140, appareil: "iPad", le: t0)
        positions.noter("Films/Heat.mkv", secondes: 30, duree: 10_000, appareil: nil, le: t0)
        positions.noter("Films/Dune.mkv", secondes: 9_900, duree: 10_000, appareil: nil, le: t0)
        #expect(positions.aReprendre("Films/Interstellar.mkv")?.secondes == 3792)
        #expect(positions.aReprendre("Films/Interstellar.mkv")?.appareil == "iPad")
        #expect(positions.aReprendre("Films/Heat.mkv") == nil)
        #expect(positions.aReprendre("Films/Dune.mkv") == nil)
        #expect(positions.entrees["Films/Dune.mkv"]?.secondes == 0)
        #expect(positions.enCours.map(\.chemin) == ["Films/Interstellar.mkv"])
    }

    @Test("Le générique compte comme la fin")
    func generique() {
        var positions = PositionsLecture()
        positions.noter("a.mp4", secondes: 5_000, duree: 5_150, appareil: nil, le: t0)
        #expect(positions.aReprendre("a.mp4") == nil)
    }

    @Test("La position la plus récente l'emporte, entrée par entrée")
    func fusion() {
        var ici = PositionsLecture()
        ici.noter("a.mp4", secondes: 600, duree: 6_000, appareil: "iPhone", le: t0)
        ici.noter("b.mp4", secondes: 900, duree: 6_000, appareil: "iPhone", le: t0.addingTimeInterval(100))
        var la = PositionsLecture()
        la.noter("a.mp4", secondes: 1_200, duree: 6_000, appareil: "Apple TV", le: t0.addingTimeInterval(50))
        la.noter("b.mp4", secondes: 300, duree: 6_000, appareil: "Apple TV", le: t0)
        let change = ici.fusionner(la)
        #expect(change)
        #expect(ici.entrees["a.mp4"]?.secondes == 1_200)
        #expect(ici.entrees["b.mp4"]?.secondes == 900)
        let encore = ici.fusionner(la)
        #expect(!encore)
    }

    @Test("« Depuis le début » efface la position pour tous les appareils")
    func oublier() {
        var positions = PositionsLecture()
        positions.noter("a.mp4", secondes: 600, duree: 6_000, appareil: nil, le: t0)
        positions.oublier("a.mp4", le: t0.addingTimeInterval(10))
        #expect(positions.aReprendre("a.mp4") == nil)
        var autre = PositionsLecture()
        autre.noter("a.mp4", secondes: 600, duree: 6_000, appareil: nil, le: t0)
        autre.fusionner(positions)
        #expect(autre.aReprendre("a.mp4") == nil)
    }

    @Test("Aller-retour par les réglages, et libellés")
    func formats() {
        var positions = PositionsLecture()
        positions.noter("a.mp4", secondes: 3792, duree: 10_140, appareil: "iPad", le: t0)
        #expect(PositionsLecture(donnees: positions.encoder()) == positions)
        #expect(PositionsLecture.horodatage(3792) == "1:03:12")
        #expect(PositionsLecture.horodatage(725) == "12:05")
        #expect(PositionsLecture.reste(6_300) == "encore 1 h 45")
        #expect(PositionsLecture.reste(1_860) == "encore 31 min")
    }
}
