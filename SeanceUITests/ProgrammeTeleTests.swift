import XCTest

/// Le programme télé sur l'iPhone, avec le guide fictif de la démonstration : les jours, les moments de la journée,
/// les épisodes réunis et le titre de ta liste mis en avant.
@MainActor
final class ProgrammeTeleTests: XCTestCase {
    private var app = XCUIApplication()

    private func capture(_ nom: String, attente: TimeInterval = 2) {
        Thread.sleep(forTimeInterval: attente)
        let piece = XCTAttachment(screenshot: app.screenshot())
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    func testProgrammeTele() throws {
        continueAfterFailure = true
        app.launchEnvironment["SEANCE_DEMO"] = "1"
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Accueil"].firstMatch.waitForExistence(timeout: 10))
        app.open(URL(string: "seance://tele")!)
        XCTAssertTrue(app.navigationBars["Programme télé"].waitForExistence(timeout: 10), "Le programme télé ne s'ouvre pas")
        XCTAssertTrue(app.staticTexts["En ce moment"].waitForExistence(timeout: 5), "Pas de section « En ce moment »")
        capture("tele-films", attente: 4)

        // La cloche d'un passage à venir : « me le rappeler un quart d'heure avant ». iOS demande la permission.
        let cloche = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Me rappeler'")).firstMatch
        XCTAssertTrue(cloche.waitForExistence(timeout: 5), "Aucune cloche sur les passages à venir")
        cloche.tap()
        let ecran = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for libelle in ["Autoriser", "Allow"] where ecran.buttons[libelle].waitForExistence(timeout: 3) {
            ecran.buttons[libelle].tap()
            break
        }
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Retirer le rappel'")).firstMatch.waitForExistence(timeout: 8),
                      "La cloche ne pose pas le rappel")
        capture("tele-rappel", attente: 1)
        app.swipeUp()
        capture("tele-films-bas")
        app.swipeDown()

        app.buttons["Tout"].firstMatch.tap()
        app.swipeUp()
        // Deux épisodes de Reacher qui s'enchaînent sur RTS 1 : une seule carte.
        let reacher = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reacher'"))
        XCTAssertTrue(reacher.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(reacher.count, 1, "Les épisodes qui s'enchaînent ne sont pas réunis")
        XCTAssertTrue(reacher.firstMatch.label.contains("S02E06 et E07"))
        capture("tele-tout-bas")

        // Un autre jour, puis la fiche d'un passage et le retour.
        app.swipeDown()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Demain'")).firstMatch.tap()
        capture("tele-demain")
        XCTAssertFalse(app.staticTexts["En ce moment"].exists, "« En ce moment » ne concerne qu'aujourd'hui")
    }
}
