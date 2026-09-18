import XCTest

/// L'iPad au lancement : en paysage, la barre latérale s'ouvre à côté de la page et montre tous les onglets ; en
/// portrait, où le système la poserait par-dessus le contenu, elle reste fermée et l'accueil est visible.
/// À lancer sur un simulateur d'iPad : `SIMULATEUR="iPad Air 11-inch (M3)" outils/tests-interface.sh IPadTests`.
@MainActor
final class IPadTests: XCTestCase {
    private var app = XCUIApplication()

    private func capture(_ nom: String) {
        Thread.sleep(forTimeInterval: 2)
        let piece = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    private func lancer(_ orientation: UIDeviceOrientation) throws {
        XCUIDevice.shared.orientation = orientation
        Lancement.demonstration(app)
        app.launch()
        // Le lanceur de tests se dit « iPhone » même sur un iPad : c'est la largeur de la fenêtre qui fait foi.
        let fenetre = app.windows.firstMatch
        XCTAssertTrue(fenetre.waitForExistence(timeout: 15))
        try XCTSkipUnless(min(fenetre.frame.width, fenetre.frame.height) > 700, "Test réservé à l'iPad")
        XCTAssertTrue(app.staticTexts["Du moment"].firstMatch.waitForExistence(timeout: 15) || app.buttons["Accueil"].firstMatch.waitForExistence(timeout: 5))
        // La barre s'ouvre 400 ms après le montage de la fenêtre.
        Thread.sleep(forTimeInterval: 1.5)
    }

    func testPaysageBarreOuverte() throws {
        try lancer(.landscapeLeft)
        capture("ipad-paysage")
        // Tous les onglets sont là, sous forme de lignes de la barre latérale.
        for onglet in ["Accueil", "Ce soir", "Mes listes", "Profil", "Réglages", "Explorer"] {
            XCTAssertTrue(app.cells.containing(.staticText, identifier: onglet).firstMatch.exists
                          || app.buttons[onglet].firstMatch.exists, "« \(onglet) » absent de la barre latérale")
        }
        // Et la page reste utilisable à côté : un onglet s'ouvre sans avoir à refermer quoi que ce soit.
        let reglages = app.cells.containing(.staticText, identifier: "Réglages").firstMatch
        if reglages.exists { reglages.tap() } else { app.buttons["Réglages"].firstMatch.tap() }
        XCTAssertTrue(app.staticTexts["Où regarder"].firstMatch.waitForExistence(timeout: 8), "Réglages ne s'ouvre pas depuis la barre latérale")
        capture("ipad-paysage-reglages")
    }

    func testPortraitAccueilVisible() throws {
        try lancer(.portrait)
        capture("ipad-portrait")
        // Rien ne recouvre l'accueil : son premier bouton se touche.
        XCTAssertFalse(app.cells.containing(.staticText, identifier: "Réglages").firstMatch.exists,
                       "La barre latérale recouvre l'accueil en portrait")
    }

    override func tearDown() async throws {
        await MainActor.run { XCUIDevice.shared.orientation = .portrait }
    }
}
