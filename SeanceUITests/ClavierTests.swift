import XCTest

/// Le clavier doit se ranger après une saisie : sinon il masque la barre d'onglets.
@MainActor
final class ClavierTests: XCTestCase {
    private func lancer() -> XCUIApplication {
        let app = XCUIApplication()
        if let cle = ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] {
            app.launchEnvironment["SEANCE_CLE_TMDB"] = cle
        }
        app.launch()
        return app
    }

    private func attendreClavierRange(_ app: XCUIApplication) -> Bool {
        let absent = NSPredicate(format: "count == 0")
        let attente = XCTNSPredicateExpectation(predicate: absent, object: app.keyboards)
        return XCTWaiter.wait(for: [attente], timeout: 5) == .completed
    }

    @MainActor
    func testRetourDansCeSoirRangeLeClavier() throws {
        let app = lancer()
        app.buttons["Ce soir"].firstMatch.tap()

        // Un champ sur plusieurs lignes apparaît comme une zone de texte.
        let champ = app.textViews.count > 0 ? app.textViews.firstMatch : app.textFields.firstMatch
        _ = app.staticTexts["De quoi as-tu envie ?"].waitForExistence(timeout: 10)
        XCTAssertTrue(champ.waitForExistence(timeout: 5), "Champ d'envie introuvable")
        champ.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Le clavier logiciel ne s'est pas ouvert")
        champ.typeText("film de guerre\n")

        XCTAssertTrue(attendreClavierRange(app), "Retour ne range pas le clavier")
        XCTAssertEqual(champ.value as? String, "film de guerre")
        let accueil = app.buttons["Accueil"].firstMatch
        XCTAssertTrue(accueil.isHittable, "La barre d'onglets reste inaccessible")
        accueil.tap()
    }

    @MainActor
    func testRechercherDansExplorerRangeLeClavier() throws {
        let app = lancer()
        app.buttons["Explorer"].firstMatch.tap()

        let champ = app.searchFields.firstMatch
        XCTAssertTrue(champ.waitForExistence(timeout: 10), "Champ de recherche introuvable")
        if !app.keyboards.firstMatch.exists { champ.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Le clavier logiciel ne s'est pas ouvert")
        champ.typeText("heat\n")

        XCTAssertTrue(attendreClavierRange(app), "Rechercher ne range pas le clavier")
        XCTAssertTrue(app.buttons["Accueil"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Accueil"].firstMatch.isHittable, "La barre d'onglets reste inaccessible")
    }
}
