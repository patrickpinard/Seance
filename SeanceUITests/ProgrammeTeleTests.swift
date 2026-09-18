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
        XCTAssertTrue(app.buttons["Filtrer par chaîne"].firstMatch.waitForExistence(timeout: 5), "Pas de filtre par chaîne")
        capture("tele-films", attente: 4)

        // La cloche d'un passage à venir : « me le rappeler un quart d'heure avant ». iOS demande la permission.
        // Le soir, plusieurs émissions sont « en ce moment » : leurs cartes repoussent la première cloche sous l'écran.
        let cloche = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Me rappeler'")).firstMatch
        XCTAssertTrue(app.amener(cloche), "Aucune cloche sur les passages à venir")
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
        XCTAssertTrue(app.amener(app.buttons["Tout"].firstMatch, versLeHaut: true), "Le choix Films, Séries, Tout a disparu")
        app.buttons["Tout"].firstMatch.tap()
        // Reacher passe ce soir : « en soirée », « en ce moment », ou déjà fini selon l'heure du test. Pour la capture.
        app.amener(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reacher'")).firstMatch, essais: 3)
        capture("tele-tout-bas")

        // Un autre jour. Deux épisodes de Jack Ryan s'y enchaînent sur RTS 2 : une seule carte.
        let demain = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Demain'")).firstMatch
        XCTAssertTrue(app.amener(demain, versLeHaut: true), "La rangée de jours a disparu")
        demain.tap()
        let jackRyan = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Jack Ryan'"))
        XCTAssertTrue(app.amener(jackRyan.firstMatch), "Jack Ryan absent du programme de demain")
        XCTAssertEqual(jackRyan.count, 1, "Les épisodes qui s'enchaînent ne sont pas réunis")
        XCTAssertTrue(jackRyan.firstMatch.label.contains("S01E03 et E04"), "Libellé inattendu : \(jackRyan.firstMatch.label)")
        capture("tele-demain")
        XCTAssertFalse(app.staticTexts["En ce moment"].exists, "« En ce moment » ne concerne qu'aujourd'hui")
    }
}
