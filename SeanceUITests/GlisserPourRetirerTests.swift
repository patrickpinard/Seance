import XCTest

/// Mes listes › Terminés, en cartes (8.6) : glisser une carte vers la gauche la retire, sans passer par la vue en liste.
@MainActor
final class GlisserPourRetirerTests: XCTestCase {
    private let app = XCUIApplication()

    private func capture(_ nom: String) {
        let piece = XCTAttachment(screenshot: app.screenshot())
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    func testGlisserUneCarteDesTerminesLaRetire() throws {
        Lancement.demonstration(app)
        app.launch()
        app.onglet("Mes listes")
        let termines = app.buttons["Terminés"].firstMatch
        XCTAssertTrue(termines.waitForExistence(timeout: 20), "Pas d'onglet « Terminés »")
        termines.tap()
        // En cartes : la bascule « Grille ».
        let grille = app.buttons["Grille"].firstMatch
        if grille.waitForExistence(timeout: 5), !grille.isSelected { grille.tap() }
        let cartes = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Nobody' OR label CONTAINS 'Heat'"))
        let carte = cartes.firstMatch
        XCTAssertTrue(carte.waitForExistence(timeout: 10), "Pas de carte dans Terminés")
        let nom = carte.label
        capture("termines-avant")
        let depart = carte.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        depart.press(forDuration: 0.05, thenDragTo: carte.coordinate(withNormalizedOffset: CGVector(dx: -0.4, dy: 0.5)))
        Thread.sleep(forTimeInterval: 1.5)
        capture("termines-apres")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == %@", nom)).firstMatch.exists, "La carte glissée est toujours là")
    }

    /// 8.7 (Patrick : « elle s'ouvre tout de suite sur la page du film ») : un glissement découvre les boutons sans ouvrir
    /// la fiche ; un toucher sur la carte ouverte la referme ; seul un toucher franc ouvre la fiche.
    func testGlisserNOuvrePasLaFiche() throws {
        Lancement.demonstration(app)
        app.launch()
        app.onglet("Mes listes")
        let termines = app.buttons["Terminés"].firstMatch
        XCTAssertTrue(termines.waitForExistence(timeout: 20), "Pas d'onglet « Terminés »")
        termines.tap()
        let grille = app.buttons["Grille"].firstMatch
        if grille.waitForExistence(timeout: 5), !grille.isSelected { grille.tap() }
        let carte = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Nobody' OR label CONTAINS 'Heat'")).firstMatch
        XCTAssertTrue(carte.waitForExistence(timeout: 10), "Pas de carte dans Terminés")
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
