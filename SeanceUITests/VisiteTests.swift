import XCTest

/// Visite des pages, pour relire l'interface sur des captures (aucune vérification stricte).
@MainActor
final class VisiteTests: XCTestCase {
    private var app = XCUIApplication()

    private func capture(_ nom: String, attente: TimeInterval = 2.5) {
        Thread.sleep(forTimeInterval: attente)
        let piece = XCTAttachment(screenshot: app.screenshot())
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    func testVisite() throws {
        continueAfterFailure = true
        if let cle = ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] {
            app.launchEnvironment["SEANCE_CLE_TMDB"] = cle
        }
        app.launch()
        capture("51-accueil", attente: 7)
        app.swipeUp(); capture("52-accueil-sections")
        app.swipeUp(); capture("53-accueil-tendances")
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        let sources = app.buttons["boutonSources"].firstMatch
        if sources.waitForExistence(timeout: 4) {
            sources.tap(); capture("54-sources", attente: 2)
            if app.buttons["OK"].firstMatch.exists { app.buttons["OK"].firstMatch.tap() }
        }
        let ceSoir = app.tabBars.buttons["Ce soir"].firstMatch
        if ceSoir.waitForExistence(timeout: 4) { ceSoir.tap() }
        capture("55-ce-soir", attente: 5)
        app.swipeUp(); capture("56-ce-soir-bas")
    }
}
