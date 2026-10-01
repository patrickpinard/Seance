import XCTest

/// « Qui est-ce ? » à la pause (8.9) : les visages du film paraissent au-dessus de la barre, un visage ouvre le panneau
/// « Tu l'as vu dans », Retour le referme sans quitter le lecteur. Vidéo du Mac (`SEANCE_LIRE_FICHIER`), visages du film
/// de démonstration du faux TMDB (`SEANCE_LIRE_TITRE`) ; sans vidéo d'essai, le test est sauté.
@MainActor
final class QuiEstCeTests: XCTestCase {
    private let app = XCUIApplication()
    private let telecommande = XCUIRemote.shared

    private func capture(_ nom: String) {
        let piece = XCTAttachment(screenshot: app.screenshot())
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    func testLesVisagesALaPause() throws {
        let racine = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let video = racine.appendingPathComponent(".build/essai-tv/mire.mp4").path
        try XCTSkipUnless(FileManager.default.fileExists(atPath: video), "Pas de vidéo d'essai (.build/essai-tv/mire.mp4)")
        app.launchEnvironment["SEANCE_DEMO"] = "1"
        app.launchEnvironment["SEANCE_FAUX_TMDB"] = racine.appendingPathComponent("SeanceKit/Tests/SeanceKitTests/Fixtures").path
        app.launchEnvironment["SEANCE_LIRE_FICHIER"] = video
        app.launchEnvironment["SEANCE_LIRE_TITRE"] = "film:11"
        app.launch()
        let barre = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Progression'")).firstMatch
        XCTAssertTrue(barre.waitForExistence(timeout: 30), "Pas de lecteur")
        Thread.sleep(forTimeInterval: 2)
        let rangee = app.staticTexts["Dans ce film"]
        XCTAssertFalse(rangee.exists, "Les visages paraissent pendant la lecture")

        telecommande.press(.playPause)
        XCTAssertTrue(rangee.waitForExistence(timeout: 10), "Pas de visages à la pause")
        capture("1-pause")

        // Des boutons, on monte sur la barre, puis sur les visages.
        telecommande.press(.up)
        Thread.sleep(forTimeInterval: 0.6)
        telecommande.press(.up)
        Thread.sleep(forTimeInterval: 0.8)
        capture("2-visage")
        telecommande.press(.select)
        let dejaVu = app.staticTexts["Tu l'as vu dans"]
        XCTAssertTrue(dejaVu.waitForExistence(timeout: 10), "Le panneau de la personne ne s'ouvre pas")
        Thread.sleep(forTimeInterval: 1.5)
        capture("3-panneau")

        telecommande.press(.menu)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(dejaVu.exists, "Retour ne referme pas le panneau")
        XCTAssertTrue(barre.exists, "Retour a quitté le lecteur au lieu de refermer le panneau")
    }
}
