import XCTest

/// Sur l'iPhone, Réglages s'ouvre depuis l'engrenage de Profil : la page et chacune de ses sous-pages doivent
/// s'ouvrir et se refermer sans figer l'app (elle s'est figée en 2.3 et 2.4, puis iOS la tuait).
@MainActor
final class ReglagesTests: XCTestCase {
    private var app = XCUIApplication()

    private func capture(_ nom: String) {
        let piece = XCTAttachment(screenshot: app.screenshot())
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    func testReglagesEtSesPagesSOuvrent() throws {
        continueAfterFailure = true
        app.launchEnvironment["SEANCE_DEMO"] = "1"
        app.launch()
        app.tabBars.buttons["Profil"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars.buttons["Réglages"].firstMatch.waitForExistence(timeout: 10))
        app.navigationBars.buttons["Réglages"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Comptes"].firstMatch.waitForExistence(timeout: 10), "Réglages ne s'ouvre pas")
        capture("reglages")

        // Le prénom se saisit et se retrouve sur sa ligne.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Prénom'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Toi"].waitForExistence(timeout: 8), "La page « Toi » ne s'ouvre pas")
        let champ = app.textFields["Ton prénom"]
        XCTAssertTrue(champ.waitForExistence(timeout: 5))
        champ.tap()
        champ.typeText("Camille\n")
        capture("reglages-Toi")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Camille'")).firstMatch.waitForExistence(timeout: 8),
                      "Le prénom saisi n'apparaît pas dans Réglages")

        let pages: [(ligne: String, repere: String)] = [
            ("TMDB", "Clé TMDB"),
            ("Claude", "Clé Claude"),
            ("Plateformes", "Plateformes"),
            ("Télévision", "Guide des programmes"),
            ("NAS", "NAS"),
            ("Alertes", "Alertes"),
            ("Sauvegarde", "Sauvegarde"),
            ("À propos", "L'application"),
        ]
        for page in pages {
            let ligne = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", page.ligne)).firstMatch
            if !ligne.isHittable { app.swipeUp() }
            XCTAssertTrue(ligne.waitForExistence(timeout: 5), "Ligne « \(page.ligne) » absente")
            ligne.tap()
            let ouverte = app.navigationBars[page.ligne].waitForExistence(timeout: 8)
                || app.staticTexts[page.repere].firstMatch.waitForExistence(timeout: 2)
            XCTAssertTrue(ouverte, "La page « \(page.ligne) » ne s'ouvre pas")
            capture("reglages-\(page.ligne)")
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.staticTexts["Comptes"].firstMatch.waitForExistence(timeout: 8)
                          || app.staticTexts["Mes données"].firstMatch.waitForExistence(timeout: 2),
                          "Retour à Réglages impossible depuis « \(page.ligne) »")
        }

        // Retour au Profil, puis un autre onglet : l'app répond toujours.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Tes goûts"].firstMatch.waitForExistence(timeout: 8), "Retour au Profil impossible")
        app.tabBars.buttons["Accueil"].firstMatch.tap()
        XCTAssertTrue(app.tabBars.buttons["Accueil"].firstMatch.isSelected)
    }
}
