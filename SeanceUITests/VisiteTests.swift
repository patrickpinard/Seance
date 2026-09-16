import XCTest

/// Visite des pages, pour relire l'interface sur des captures.
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

    func testPremierLancement() throws {
        continueAfterFailure = true
        if let cle = ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] {
            app.launchEnvironment["SEANCE_CLE_TMDB"] = cle
        }
        app.launchEnvironment["SEANCE_BIENVENUE"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["Bienvenue dans Séance"].waitForExistence(timeout: 10))
        capture("71-bienvenue")
        app.buttons["Commencer"].tap()
        capture("72-plateformes", attente: 4)
        app.buttons["Suivant"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Qu'aimes-tu regarder ?"].waitForExistence(timeout: 5))
        app.buttons["Action"].firstMatch.tap()
        app.buttons["Thriller"].firstMatch.tap()
        app.buttons["Arts martiaux"].firstMatch.tap()
        capture("73-gouts")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Suivant'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["As-tu vu ce film ?"].waitForExistence(timeout: 20), "Notation rapide absente")
        capture("74-notation")
        app.buttons["Note 9 sur 10"].firstMatch.tap()
        app.buttons["Note 8 sur 10"].firstMatch.tap()
        app.buttons["Je ne l'ai pas vu"].firstMatch.tap()
        capture("75-notation-suite", attente: 1.5)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Terminer'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["C'est prêt !"].waitForExistence(timeout: 5))
        capture("76-fin")
        app.buttons["Découvrir Séance"].tap()
        XCTAssertTrue(app.tabBars.buttons["Accueil"].firstMatch.waitForExistence(timeout: 5))
    }

    /// Données de démonstration en mémoire : statistiques et bilan en cartes.
    func testStatistiques() throws {
        continueAfterFailure = true
        if let cle = ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] {
            app.launchEnvironment["SEANCE_CLE_TMDB"] = cle
        }
        app.launchEnvironment["SEANCE_DEMO"] = "1"
        app.launch()
        app.tabBars.buttons["Moi"].firstMatch.tap()
        capture("80-moi")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Statistiques'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Mois par mois"].waitForExistence(timeout: 5))
        capture("81-statistiques")
        app.swipeUp()
        capture("82-statistiques-bas")
        app.swipeDown()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Ton année' OR label BEGINSWITH 'Ton bilan'")).firstMatch.tap()
        capture("83-bilan-heures", attente: 5)
        for nom in ["84-bilan-titres", "85-bilan-acteur", "86-bilan-genres", "87-bilan-film", "88-bilan-soiree", "89-bilan-resume"] {
            app.swipeLeft()
            capture(nom, attente: 1.5)
        }
        XCTAssertTrue(app.buttons["Partager cette carte"].exists, "Bouton de partage absent")
        app.buttons["Partager cette carte"].tap()
        capture("90-partage", attente: 3)
    }

    /// Vues des widgets à leurs tailles, puis liens des widgets vers Ce soir et À venir.
    func testWidgets() throws {
        continueAfterFailure = true
        if let cle = ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] {
            app.launchEnvironment["SEANCE_CLE_TMDB"] = cle
        }
        app.launchEnvironment["SEANCE_DEMO"] = "1"
        app.launchEnvironment["SEANCE_APERCU_WIDGETS"] = "1"
        app.launch()
        app.tabBars.buttons["Moi"].firstMatch.tap()
        app.swipeUp()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Aperçu des widgets'")).firstMatch.tap()
        capture("91-widgets-accueil", attente: 5)
        app.swipeUp()
        capture("92-widgets-bas")
        app.swipeUp()
        capture("93-widgets-verrouille")

        app.open(URL(string: "seance://cesoir")!)
        capture("94-lien-ce-soir", attente: 4)
        app.open(URL(string: "seance://avenir")!)
        capture("95-lien-a-venir", attente: 4)
        XCTAssertTrue(app.buttons["À venir"].firstMatch.isSelected, "Mes listes ne s'est pas ouvert sur À venir")
    }

    /// Ce soir sans la recherche d'idées, le lien vers Explorer, puis les versions repliables.
    func testCeSoirEtVersions() throws {
        continueAfterFailure = true
        if let cle = ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] {
            app.launchEnvironment["SEANCE_CLE_TMDB"] = cle
        }
        app.launchEnvironment["SEANCE_DEMO"] = "1"
        app.launch()
        app.tabBars.buttons["Ce soir"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Ma soirée"].waitForExistence(timeout: 10))
        capture("96-ce-soir", attente: 5)
        XCTAssertFalse(app.staticTexts["Une idée pour ce soir ?"].exists, "La recherche d'idées est encore là")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH \"Envie d\"")).firstMatch.tap()
        capture("97-vers-explorer")

        // Dans Explorer, la barre d'onglets se replie autour du champ de recherche.
        app.terminate()
        app.launch()
        app.tabBars.buttons["Moi"].firstMatch.tap()
        app.swipeUp()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'À propos'")).firstMatch.tap()
        app.buttons["Versions"].firstMatch.tap()
        capture("98-versions")
        app.swipeUp()
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Version 1.1'")).firstMatch.tap()
        capture("99-versions-1-1", attente: 1.5)
    }
}
