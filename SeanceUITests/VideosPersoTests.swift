import XCTest

/// Les vidéos personnelles (EF-157 à EF-159), avec les exemples de la démonstration : l'entrée depuis la page NAS, les
/// dossiers, un retour qui ramène au dossier parent, et le réglage avec sa case à cocher.
@MainActor
final class VideosPersoTests: XCTestCase {
    private var app = XCUIApplication()

    private func capture(_ nom: String) {
        Thread.sleep(forTimeInterval: 1.5)
        let piece = XCTAttachment(screenshot: app.screenshot()); piece.name = nom; piece.lifetime = .keepAlways; add(piece)
    }

    func testParcoursEtReglage() throws {
        continueAfterFailure = true
        Lancement.demonstration(app)
        app.launch()
        // La bibliothèque s'ouvre par « Tout voir » de l'étagère « Sur ton NAS », plus bas sur l'accueil.
        XCTAssertTrue(app.staticTexts["Nouveautés"].firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(app.amener(app.buttons["boutonNAS"].firstMatch), "L'étagère « Sur ton NAS » n'a pas de « Tout voir »")
        app.buttons["boutonNAS"].firstMatch.tap()
        let entree = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Vidéos personnelles'")).firstMatch
        XCTAssertTrue(entree.waitForExistence(timeout: 10), "La page NAS ne propose pas les vidéos personnelles")
        entree.tap()
        XCTAssertTrue(app.navigationBars["Vidéos personnelles"].waitForExistence(timeout: 8))
        capture("videos-racine")

        let dossier = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '2026'")).firstMatch
        XCTAssertTrue(dossier.waitForExistence(timeout: 5), "Le dossier « 2026 » est absent")
        dossier.tap()
        XCTAssertTrue(app.navigationBars["2026"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Lire Anniversaire de Camille"].firstMatch.waitForExistence(timeout: 5), "La vidéo rangée dans « 2026 » est absente")
        capture("videos-2026")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Vidéos personnelles"].waitForExistence(timeout: 8), "Un retour ne ramène pas au dossier parent")

        // Le réglage : une ligne de l'état, et une case à cocher.
        app.tabBars.buttons["Préférences"].firstMatch.tap()
        app.navigationBars.buttons["Réglages"].firstMatch.tap()
        let ligne = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Vidéos personnelles'")).firstMatch
        XCTAssertTrue(app.amener(ligne), "La ligne « Vidéos personnelles » est absente de l'état")
        ligne.tap()
        XCTAssertTrue(app.switches["Inclure mes vidéos personnelles"].firstMatch.waitForExistence(timeout: 8), "La case à cocher est absente")
        capture("videos-reglage")
    }
}
