import XCTest

/// Ce que voit quelqu'un qui vient d'installer Séance : aucun titre, aucune soirée, pas de NAS, pas de guide TV.
/// Chaque écran doit dire ce qu'il montrera et comment le remplir — jamais une page blanche. Captures à relire.
@MainActor
final class EtatsVidesTests: XCTestCase {
    private var app = XCUIApplication()

    private func capture(_ nom: String, attente: TimeInterval = 2) {
        Thread.sleep(forTimeInterval: attente)
        let piece = XCTAttachment(screenshot: app.screenshot())
        piece.name = "vide-" + nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    func testEcransVides() throws {
        continueAfterFailure = true
        Lancement.demonstration(app)
        app.launchEnvironment["SEANCE_DEMO"] = "vide"
        app.launch()
        // Sans aucune donnée, Séance accueille : c'est le premier état vide. « Plus tard » mène à l'app nue.
        let plusTard = app.buttons["Plus tard"].firstMatch
        XCTAssertTrue(plusTard.waitForExistence(timeout: 20), "Pas d'écran de bienvenue sur une app vide")
        capture("00-bienvenue", attente: 1)
        plusTard.tap()
        XCTAssertTrue(app.tabBars.buttons["Accueil"].firstMatch.waitForExistence(timeout: 10))
        capture("01-accueil", attente: 5)
        app.swipeUp()
        capture("02-accueil-bas")
        app.swipeDown()

        app.aller("Ce soir")
        capture("03-ce-soir", attente: 3)

        app.tabBars.buttons["Mes listes"].firstMatch.tap()
        for (rang, onglet) in ["À voir", "À venir", "En cours", "Terminés", "Listes"].enumerated() {
            app.buttons[onglet].firstMatch.tap()
            capture("0\(4 + rang)-listes-\(onglet)")
        }

        app.ouvrirPreferences()
        capture("09-profil", attente: 3)
        app.swipeUp()
        capture("10-profil-bas")
        let statistiques = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Ta collection et ton année'")).firstMatch
        if app.amener(statistiques, essais: 4) {
            statistiques.tap()
            capture("11-statistiques", attente: 3)
            app.navigationBars.buttons.firstMatch.tap()
        }

        // `open` relance l'app, et la démonstration vide repart alors de zéro : la bienvenue revient, on la repasse.
        app.open(URL(string: "seance://tele")!)
        if app.buttons["Plus tard"].firstMatch.waitForExistence(timeout: 5) { app.buttons["Plus tard"].firstMatch.tap() }
        capture("12-tele", attente: 3)
        // Le programme vide mène aux réglages des chaînes, et on en revient.
        let chaines = app.buttons["Choisir mes chaînes"].firstMatch
        XCTAssertTrue(chaines.waitForExistence(timeout: 5), "Le programme TV vide ne propose pas de choisir ses chaînes")
        chaines.tap()
        XCTAssertTrue(app.navigationBars["TV"].waitForExistence(timeout: 8), "« Choisir mes chaînes » n'ouvre pas les réglages de télévision")
        capture("12b-tele-reglages", attente: 1)
        app.navigationBars.buttons.firstMatch.tap()
        // De retour sur Regarder : son premier bouton est le portrait (les Préférences), pas un retour — on n'y touche pas.
        _ = app.navigationBars["Regarder"].waitForExistence(timeout: 5)

        // La page NAS, depuis l'accueil — si son bouton existe quand aucun NAS n'est configuré.
        app.tabBars.buttons["Accueil"].firstMatch.tap()
        let nas = app.buttons["boutonNAS"].firstMatch
        if nas.waitForExistence(timeout: 3) {
            nas.tap()
            capture("13-nas", attente: 3)
        }

        // En dernier, car Explorer replie la barre d'onglets de l'iPhone : l'état vide d'« À voir » propose d'aller chercher des idées, et y mène.
        app.tabBars.buttons["Mes listes"].firstMatch.tap()
        app.buttons["À voir"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Ta liste est vide"].waitForExistence(timeout: 5), "« À voir » vide n'explique rien")
        XCTAssertFalse(app.buttons["Regardable ce soir"].exists, "Un filtre au-dessus d'une liste vide n'a pas d'objet")
        app.buttons["Trouver des suggestions"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Explorer"].waitForExistence(timeout: 8) || app.searchFields.firstMatch.waitForExistence(timeout: 3),
                      "« Trouver des suggestions » ne mène pas à la recherche")
        capture("14-explorer-depuis-vide")
    }
}
