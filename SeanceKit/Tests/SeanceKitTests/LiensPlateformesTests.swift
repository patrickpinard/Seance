import Foundation
import Testing
@testable import SeanceKit

@Suite("Liens vers les plateformes")
struct LiensPlateformesTests {
    @Test func rechercheSurLaPlateforme() {
        #expect(LiensPlateformes.lien(plateforme: 8, titre: "Reacher")?.absoluteString == "https://www.netflix.com/search?q=Reacher")
        #expect(LiensPlateformes.lien(plateforme: 350, titre: "Ted Lasso")?.absoluteString == "https://tv.apple.com/search?term=Ted%20Lasso")
    }

    @Test func titreAvecSignesEtAccents() {
        let lien = LiensPlateformes.lien(plateforme: 9, titre: " Tom & Jerry : l'été ? ")
        #expect(lien?.absoluteString == "https://www.primevideo.com/search?phrase=Tom%20%26%20Jerry%20:%20l'%C3%A9t%C3%A9%20%3F")
    }

    @Test func plateformeInconnueOuTitreVide() {
        #expect(LiensPlateformes.lien(plateforme: 999_999, titre: "Heat") == nil)
        #expect(LiensPlateformes.lien(plateforme: 8, titre: "  ") == nil)
    }
}
