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
        // La barre s'ouvre 400 ms après le montage de la fenêtre.
        Thread.sleep(forTimeInterval: 1.5)
    }

    func testPaysageBarreOuverte() throws {
        try lancer(.landscapeLeft)
        capture("ipad-paysage")
        // Tous les onglets sont là, en lignes de la barre latérale — et pas seulement en boutons de la barre du haut,
        // qui existent aussi quand la barre latérale est fermée : cette assertion-là ne prouvait rien.
        XCTAssertTrue(app.cells.containing(.staticText, identifier: "Réglages").firstMatch.waitForExistence(timeout: 8),
                      "La barre latérale n'est pas ouverte en paysage")
        for onglet in ["Accueil", "Ce soir", "Mes listes", "Préférences", "Réglages", "Explorer"] {
            XCTAssertTrue(app.cells.containing(.staticText, identifier: onglet).firstMatch.exists, "« \(onglet) » absent de la barre latérale")
        }
        // Et la page reste utilisable à côté : un onglet s'ouvre sans avoir à refermer quoi que ce soit.
        let reglages = app.cells.containing(.staticText, identifier: "Réglages").firstMatch
        if reglages.exists { reglages.tap() } else { app.buttons["Réglages"].firstMatch.tap() }
        XCTAssertTrue(app.staticTexts["Tes appareils"].firstMatch.waitForExistence(timeout: 8), "Réglages ne s'ouvre pas depuis la barre latérale")
        capture("ipad-paysage-reglages")
    }

    /// L'apparence claire sur grand écran, pour relecture : barre latérale, accueil, Ce soir, Mes listes, Réglages.
    func testApparenceClaire() throws {
        continueAfterFailure = true
        try lancer(.landscapeLeft, arguments: ["-apparence", "clair", "-profil.prenom", "Camille"])
        capture("ipad-clair-accueil")
        // Un parcours pour relire les captures, pas une vérification : on attend le repère sans en faire une condition.
        for (onglet, repere) in [("Réglages", "Tes appareils"), ("Ce soir", "Ce soir"), ("Mes listes", "Mes listes"), ("Préférences", "Tes goûts")] {
            let ligne = app.cells.containing(.staticText, identifier: onglet).firstMatch
            if ligne.exists { ligne.tap() } else { app.buttons[onglet].firstMatch.tap() }
            _ = app.staticTexts[repere].firstMatch.waitForExistence(timeout: 8)
            capture("ipad-clair-\(onglet)")
        }
    }

    func testPortraitAccueilVisible() throws {
        try lancer(.portrait)
        capture("ipad-portrait")
        // Rien ne recouvre l'accueil : son premier bouton se touche.
        XCTAssertFalse(app.cells.containing(.staticText, identifier: "Réglages").firstMatch.exists,
                       "La barre latérale recouvre l'accueil en portrait")
        // On tourne la tablette : la barre s'ouvre alors à côté de la page.
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.cells.containing(.staticText, identifier: "Réglages").firstMatch.waitForExistence(timeout: 8),
                      "En passant en paysage, la barre latérale ne s'ouvre pas")
        capture("ipad-portrait-puis-paysage")
    }

    override func tearDown() async throws {
        await MainActor.run { XCUIDevice.shared.orientation = .portrait }
    }
}
