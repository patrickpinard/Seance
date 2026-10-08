import XCTest

/// Mes listes › À voir, en cartes (8.6 ; 8.11 : Terminés n'est plus dans Mes listes) : glisser une carte vers la gauche la retire, sans passer par la vue en liste.
@MainActor
final class GlisserPourRetirerTests: XCTestCase {
    private let app = XCUIApplication()

    private func capture(_ nom: String) {
        let piece = XCTAttachment(screenshot: app.screenshot())
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    func testGlisserUneCarteDeMaListeLaRetire() throws {
        Lancement.demonstration(app)
        app.launch()
        app.onglet("Mes listes")
        let termines = app.buttons["À voir"].firstMatch
        XCTAssertTrue(termines.waitForExistence(timeout: 20), "Pas d'onglet « À voir »")
        termines.tap()
        // En cartes : la bascule « Grille ».
        let grille = app.buttons["Grille"].firstMatch
        if grille.waitForExistence(timeout: 5), !grille.isSelected { grille.tap() }
        let cartes = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Chapitre 2'"))
        let carte = cartes.firstMatch
        XCTAssertTrue(carte.waitForExistence(timeout: 10), "Pas de carte dans À voir")
        let nom = carte.label
        capture("a-voir-avant")
        let depart = carte.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        depart.press(forDuration: 0.05, thenDragTo: carte.coordinate(withNormalizedOffset: CGVector(dx: -0.4, dy: 0.5)))
        Thread.sleep(forTimeInterval: 1.5)
        capture("a-voir-apres")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == %@", nom)).firstMatch.exists, "La carte glissée est toujours là")
    }

    /// 8.7 (Patrick : « elle s'ouvre tout de suite sur la page du film ») : un glissement découvre les boutons sans ouvrir
    /// la fiche ; un toucher sur la carte ouverte la referme ; seul un toucher franc ouvre la fiche.
    func testGlisserNOuvrePasLaFiche() throws {
        Lancement.demonstration(app)
        app.launch()
        app.onglet("Mes listes")
        let termines = app.buttons["À voir"].firstMatch
        XCTAssertTrue(termines.waitForExistence(timeout: 20), "Pas d'onglet « À voir »")
        termines.tap()
        let grille = app.buttons["Grille"].firstMatch
        if grille.waitForExistence(timeout: 5), !grille.isSelected { grille.tap() }
        let carte = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Chapitre 2'")).firstMatch
        XCTAssertTrue(carte.waitForExistence(timeout: 10), "Pas de carte dans À voir")
        let nom = carte.label
        carte.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: carte.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)))
        Thread.sleep(forTimeInterval: 1.2)
        capture("glissement-boutons")
        XCTAssertTrue(termines.isHittable, "Le glissement a ouvert la fiche")
        let laCarte = app.buttons.matching(NSPredicate(format: "label == %@", nom)).firstMatch
        XCTAssertTrue(laCarte.exists, "La carte a disparu après un petit glissement")
        // Un toucher sur la carte ouverte la referme, sans ouvrir la fiche.
        laCarte.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(termines.isHittable, "Toucher la carte ouverte a ouvert la fiche au lieu de la refermer")
        // Un toucher franc ouvre la fiche.
        laCarte.tap()
        Thread.sleep(forTimeInterval: 2)
        capture("fiche")
        XCTAssertFalse(termines.isHittable, "Un toucher sur la carte n'ouvre plus la fiche")
    }
}
