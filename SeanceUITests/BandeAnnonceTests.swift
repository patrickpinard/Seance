import XCTest

/// La bande-annonce se lit dans la fiche, en flux.
@MainActor
final class BandeAnnonceTests: XCTestCase {
    func testLaBandeAnnonceSOuvre() throws {
        let app = XCUIApplication()
        if let cle = ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] {
            app.launchEnvironment["SEANCE_CLE_TMDB"] = cle
        }
        app.launch()
        app.open(URL(string: "seance://film/603692")!)
        XCTAssertTrue(app.staticTexts["Synopsis"].waitForExistence(timeout: 20), "La fiche ne s'est pas ouverte")

        let bouton = app.buttons["Bande-annonce"].firstMatch
        XCTAssertTrue(bouton.waitForExistence(timeout: 10), "Pas de bouton bande-annonce")
        bouton.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10), "Le lecteur ne s'est pas ouvert")
        // Laisse YouTube charger la vidéo avant la capture.
        _ = app.staticTexts["__attente__"].waitForExistence(timeout: 8)
        let piece = XCTAttachment(screenshot: app.screenshot())
        piece.name = "bande-annonce"
        piece.lifetime = .keepAlways
        add(piece)
    }
}
