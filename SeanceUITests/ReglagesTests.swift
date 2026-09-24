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
        app.ouvrirReglages()
        XCTAssertTrue(app.staticTexts["La maison"].firstMatch.waitForExistence(timeout: 10), "Réglages ne s'ouvre pas")
        capture("reglages")

        // Le prénom se saisit et se retrouve sur sa ligne.
        let prenom = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Prénom'")).firstMatch
        XCTAssertTrue(app.amener(prenom, essais: 16), "Tuile « Prénom et idées » introuvable")
        prenom.tap()
        XCTAssertTrue(app.navigationBars["Toi"].waitForExistence(timeout: 8), "La page « Toi » ne s'ouvre pas")
        let champ = app.textFields["Ton prénom"]
        XCTAssertTrue(champ.waitForExistence(timeout: 5))
        champ.tap()
        // Le prénom du simulateur reste d'un test à l'autre : on vide le champ d'abord.
        champ.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40) + "Camille\n")
        capture("reglages-Toi")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Camille'")).firstMatch.waitForExistence(timeout: 8),
                      "Le prénom saisi n'apparaît pas dans Réglages")

        let pages: [(ligne: String, repere: String)] = [
            ("Apparence", "Apparence"),
            ("TMDB", "Clé TMDB"),
            ("Claude", "Clé Claude"),
            ("Plateformes", "Plateformes"),
            ("TV", "Guide des programmes"),
            ("NAS", "NAS"),
            ("Lecture", "Lecture"),
            ("Alertes", "Alertes"),
            ("Appareils et synchronisation", "Sauvegarde"),
            ("Séance", "L'application"),
            ("Versions", "Versions"),
            ("Journal", "Journal"),
        ]
        for page in pages {
            // Du haut de la page à chaque fois : une carte restée sous la barre de navigation translucide se dit touchable,
            // mais le toucher atterrit sur la barre.
            app.swipeDown(); app.swipeDown(); app.swipeDown()
            let ligne = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", page.ligne)).firstMatch
            XCTAssertTrue(app.amener(ligne, essais: 16), "Ligne « \(page.ligne) » absente")
            ligne.tap()
            let ouverte = app.navigationBars[page.ligne].waitForExistence(timeout: 8)
                || app.staticTexts[page.repere].firstMatch.waitForExistence(timeout: 2)
            XCTAssertTrue(ouverte, "La page « \(page.ligne) » ne s'ouvre pas")
            capture("reglages-\(page.ligne)")
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.staticTexts["La maison"].firstMatch.waitForExistence(timeout: 8)
                          || app.staticTexts["L'app"].firstMatch.waitForExistence(timeout: 2),
                          "Retour à Réglages impossible depuis « \(page.ligne) »")
        }

        // Réglages refermés, puis un autre onglet : l'app répond toujours.
        app.fermerPreferences()
        app.tabBars.buttons["Accueil"].firstMatch.tap()
        XCTAssertTrue(app.tabBars.buttons["Accueil"].firstMatch.isSelected)
    }
}
