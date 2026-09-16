import XCTest

/// Parcours d'interface réels dans le simulateur. La clé TMDB est passée par l'environnement du
/// test (`SEANCE_CLE_TMDB`), jamais écrite dans le dépôt.
@MainActor
final class FicheDefilementTests: XCTestCase {
    private func lancer() -> XCUIApplication {
        let app = XCUIApplication()
        if let cle = ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] {
            app.launchEnvironment["SEANCE_CLE_TMDB"] = cle
        }
        app.launch()
        return app
    }

    private func capture(_ nom: String, _ app: XCUIApplication) {
        let piece = XCTAttachment(screenshot: app.screenshot())
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    @MainActor
    func testLaFicheDefileJusquAuCasting() throws {
        let app = lancer()
        app.open(URL(string: "seance://film/603692")!)

        let titre = app.staticTexts["Synopsis"]
        XCTAssertTrue(titre.waitForExistence(timeout: 20), "La fiche ne s'est pas ouverte")
        capture("fiche-haut", app)

        let casting = app.staticTexts["Casting"]
        for _ in 0..<4 where !(casting.exists && casting.isHittable) {
            app.swipeUp()
        }
        capture("fiche-bas", app)
        XCTAssertTrue(casting.exists && casting.isHittable, "Le défilement n'atteint pas le casting")
    }

    @MainActor
    func testLAccueilDefile() throws {
        let app = lancer()
        let tendances = app.staticTexts["Tendances"]
        XCTAssertTrue(tendances.waitForExistence(timeout: 20))
        let avant = tendances.frame.minY
        // Le glissement part du centre de l'écran, donc du bandeau vedette.
        app.swipeUp()
        capture("accueil-bas", app)
        XCTAssertLessThan(tendances.frame.minY, avant - 100, "L'accueil n'a pas défilé")
    }
}
