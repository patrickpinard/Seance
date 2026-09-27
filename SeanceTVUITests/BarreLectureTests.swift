import XCTest

/// La barre d'avancement du lecteur (8.2.5) : elle garde sa taille au focus et au clic. Lancé sur une vidéo du Mac
/// (`SEANCE_LIRE_FICHIER`) ; sans elle, le test est sauté.
@MainActor
final class BarreLectureTests: XCTestCase {
    private let app = XCUIApplication()
    private let telecommande = XCUIRemote.shared

    private func capture(_ nom: String) {
        let piece = XCTAttachment(screenshot: app.screenshot())
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    func testLaBarreGardeSaTaille() throws {
        let video = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/essai-tv/mire.mp4").path
        try XCTSkipUnless(FileManager.default.fileExists(atPath: video), "Pas de vidéo d'essai (.build/essai-tv/mire.mp4)")
        app.launchEnvironment["SEANCE_DEMO"] = "1"
        app.launchEnvironment["SEANCE_LIRE_FICHIER"] = video
        app.launch()
        let barre = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Progression'")).firstMatch
        XCTAssertTrue(barre.waitForExistence(timeout: 30), "Pas de barre d'avancement")
        Thread.sleep(forTimeInterval: 3)
        let avant = barre.frame
        capture("1-lecture")
        // Des boutons, on monte sur la barre.
        telecommande.press(.up)
        Thread.sleep(forTimeInterval: 1)
        let auFocus = barre.frame
        capture("2-focus")
        telecommande.press(.right)
        Thread.sleep(forTimeInterval: 0.4)
        telecommande.press(.select)
        Thread.sleep(forTimeInterval: 0.3)
        let auClic = barre.frame
        capture("3-clic")
        print("BARRE avant \(avant) focus \(auFocus) clic \(auClic)")
        XCTAssertEqual(avant.width, auFocus.width, accuracy: 2, "La barre s'élargit au focus")
        XCTAssertEqual(avant.width, auClic.width, accuracy: 2, "La barre s'élargit au clic")
        XCTAssertEqual(avant.height, auClic.height, accuracy: 2, "La barre grandit au clic")
    }

    /// Retour pendant la lecture (8.3) : la question « Quitter … ? » plutôt qu'une sortie immédiate ; « Continuer la
    /// lecture » la referme et le lecteur reste ouvert.
    func testRetourDemandeAvantDeQuitter() throws {
        let video = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/essai-tv/mire.mp4").path
        try XCTSkipUnless(FileManager.default.fileExists(atPath: video), "Pas de vidéo d'essai (.build/essai-tv/mire.mp4)")
        app.launchEnvironment["SEANCE_DEMO"] = "1"
        app.launchEnvironment["SEANCE_LIRE_FICHIER"] = video
        app.launch()
        let barre = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Progression'")).firstMatch
        XCTAssertTrue(barre.waitForExistence(timeout: 30), "Pas de lecteur")
        let question = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Quitter'")).firstMatch
        // Un ou deux Retour : le premier peut cacher les commandes, le suivant pose la question.
        for _ in 0..<2 where !question.exists {
            telecommande.press(.menu)
            Thread.sleep(forTimeInterval: 1.2)
        }
        capture("quitter-question")
        XCTAssertTrue(question.waitForExistence(timeout: 5), "Retour a quitté la lecture sans demander")
        telecommande.press(.select)   // « Continuer la lecture », choisie d'office
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(barre.exists, "Le lecteur s'est fermé malgré « Continuer la lecture »")
    }
}
