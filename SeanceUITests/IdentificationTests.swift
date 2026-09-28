import XCTest

/// 8.4 : une vidéo du NAS que Séance n'a pas reconnue seule dans TMDB s'identifie parmi ses propositions, et passe alors
/// dans la bibliothèque.
@MainActor
final class IdentificationTests: XCTestCase {
    private var app = XCUIApplication()

    private func capture(_ nom: String) {
        let piece = XCTAttachment(screenshot: app.screenshot())
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    func testUneVideoNonReconnueSIdentifie() throws {
        Lancement.demonstration(app)
        app.launch()
        app.aller("NAS")
        let puce = app.buttons["1 non reconnu"].firstMatch
        XCTAssertTrue(puce.waitForExistence(timeout: 10), "Pas de puce « 1 non reconnu » sur la page NAS")
        puce.tap()

        let ligne = app.buttons.matching(NSPredicate(format: "label CONTAINS 'The.Runner.2026.mkv'")).firstMatch
        XCTAssertTrue(ligne.waitForExistence(timeout: 8), "La vidéo non reconnue n'est pas listée")
        ligne.tap()

        XCTAssertTrue(app.staticTexts["Propositions de TMDB"].firstMatch.waitForExistence(timeout: 8), "La feuille « Identifier » ne s'ouvre pas")
        let proposition = app.buttons["proposition-550"].firstMatch
        XCTAssertTrue(proposition.waitForExistence(timeout: 10), "TMDB ne propose rien")
        capture("identifier")
        proposition.tap()

        XCTAssertTrue(app.staticTexts["Toutes les vidéos sont reconnues."].firstMatch.waitForExistence(timeout: 10),
                      "La vidéo identifiée reste parmi les non reconnues")
        capture("identifier-fait")
    }
}
