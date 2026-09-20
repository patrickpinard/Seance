import XCTest

/// De bout en bout, entre deux simulateurs : une Apple TV simulée affiche le code 424242 (lancée par
/// `outils/test-envoi-tv.sh`), et cet iPhone lui envoie sa configuration par le réseau de la machine.
@MainActor
final class EnvoiAppleTVTests: XCTestCase {
    func testEnvoiVersLAppleTV() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SEANCE_TV_ATTENDUE"] != nil, "Demande une Apple TV simulée en attente : outils/test-envoi-tv.sh")
        let app = XCUIApplication()
        Lancement.demonstration(app)
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Profil"].firstMatch.waitForExistence(timeout: 20))
        app.tabBars.buttons["Profil"].firstMatch.tap()
        app.navigationBars.buttons["Réglages"].firstMatch.tap()
        let carte = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Mon Apple TV'")).firstMatch
        XCTAssertTrue(app.amener(carte), "La tuile « Mon Apple TV » est absente des Réglages")
        carte.tap()

        let tv = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Apple TV'")).firstMatch
        XCTAssertTrue(tv.waitForExistence(timeout: 30), "Aucune Apple TV trouvée sur le réseau")
        let champ = app.textFields["Code affiché sur la TV"]
        XCTAssertTrue(champ.waitForExistence(timeout: 5))
        champ.tap()
        champ.typeText("111111")
        app.buttons["Envoyer à l'Apple TV"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Ce n’est pas le code' OR label BEGINSWITH \"Ce n'est pas le code\"")).firstMatch
            .waitForExistence(timeout: 20), "Un mauvais code doit être refusé, et dit")

        champ.tap()
        champ.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "424242")
        app.buttons["Envoyer à l'Apple TV"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'a tout reçu'")).firstMatch.waitForExistence(timeout: 30),
                      "L'envoi avec le bon code n'a pas abouti")
        let piece = XCTAttachment(screenshot: app.screenshot()); piece.name = "envoi-apple-tv"; piece.lifetime = .keepAlways; add(piece)
    }
}
