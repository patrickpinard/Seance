import Foundation
import Testing
@testable import SeanceKit

@Suite("Tes réalisateurs")
struct RealisateursTests {
    @Test func lesPlusVusDAbord() {
        var reserve = ReserveRealisateurs()
        let mann = ReserveRealisateurs.Realisateur(id: 1, nom: "Michael Mann", cheminPortrait: nil)
        let nolan = ReserveRealisateurs.Realisateur(id: 2, nom: "Christopher Nolan", cheminPortrait: nil)
        reserve.parFilm = [10: [mann], 11: [mann], 12: [mann], 20: [nolan], 21: [nolan], 30: [], 40: [nolan]]
        let classement = reserve.classement(filmsVus: [10, 11, 12, 20, 21, 30])
        #expect(classement.map(\.realisateur.nom) == ["Michael Mann", "Christopher Nolan"])
        #expect(classement[1].films == [20, 21])
        #expect(reserve.manquants([10, 50]) == [50])
    }

    @Test func unSeulFilmNeSuffitPas() {
        var reserve = ReserveRealisateurs()
        reserve.parFilm = [10: [.init(id: 1, nom: "A", cheminPortrait: nil)]]
        #expect(reserve.classement(filmsVus: [10]).isEmpty)
    }
}
