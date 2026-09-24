import XCTest

/// L'iPad, en portrait et en paysage (8.0) : le menu en haut, comme sur l'Apple TV — Accueil, Regarder, Mes listes et la
/// loupe —, une seule roue dentée par page, rien par-dessus la page.
/// À lancer sur un simulateur d'iPad : `SIMULATEUR="iPad Air 11-inch (M4)" outils/tests-interface.sh IPadTests`.
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

    private func lancer(_ orientation: UIDeviceOrientation, arguments: [String] = []) throws {
        XCUIDevice.shared.orientation = orientation
        Lancement.demonstration(app)
        app.launchArguments += arguments
        app.launch()
        // Le lanceur de tests se dit « iPhone » même sur un iPad : c'est la largeur de la fenêtre qui fait foi.
        let fenetre = app.windows.firstMatch
        XCTAssertTrue(fenetre.waitForExistence(timeout: 15))
        try XCTSkipUnless(min(fenetre.frame.width, fenetre.frame.height) > 700, "Test réservé à l'iPad")
        XCTAssertTrue(app.staticTexts["Nouveautés"].firstMatch.waitForExistence(timeout: 15) || app.buttons["Accueil"].firstMatch.waitForExistence(timeout: 5))
    }

    /// 8.0 : les trois onglets et la loupe en haut, une seule roue dentée ; Réglages s'ouvre et se lit à côté de sa liste.
    private func verifierMenu(_ nom: String) {
        capture("ipad-\(nom)")
        for onglet in ["Accueil", "Regarder", "Mes listes"] {
            XCTAssertTrue(app.buttons[onglet].firstMatch.exists, "« \(onglet) » absent du menu en \(nom)")
        }
        XCTAssertEqual(app.buttons.matching(identifier: "reglages").count, 1, "Pas exactement une roue dentée en \(nom)")
        // Rien ne recouvre la page : pas de barre latérale ouverte d'office.
        XCTAssertFalse(app.cells.containing(.staticText, identifier: "Mes listes").firstMatch.exists,
                       "Une barre latérale recouvre la page en \(nom)")
        // Regarder et ses pastilles, puis la page NAS : toujours une seule roue dentée (deux en 7.0 sur l'iPad).
        app.aller("NAS")
        XCTAssertTrue(app.buttons["NAS"].firstMatch.waitForExistence(timeout: 8), "Pas de pastille NAS dans Regarder")
        XCTAssertEqual(app.buttons.matching(identifier: "reglages").count, 1, "Deux roues dentées sur la page NAS en \(nom)")
        capture("ipad-\(nom)-nas")
        app.ouvrirReglages()
        XCTAssertTrue(app.staticTexts["La maison"].firstMatch.waitForExistence(timeout: 8), "Réglages ne s'ouvre pas en \(nom)")
        capture("ipad-\(nom)-reglages")
    }

    func testPaysageMenuEnHaut() throws {
        try lancer(.landscapeLeft)
        verifierMenu("paysage")
    }

    func testPortraitMenuEnHaut() throws {
        try lancer(.portrait)
        verifierMenu("portrait")
    }

    override func tearDown() async throws {
        await MainActor.run { XCUIDevice.shared.orientation = .portrait }
    }
}
