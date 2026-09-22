import XCTest

/// ▶︎ (6.1) : « on ne voit pas comment lancer le film » (Patrick, Kill Bill). Sur une grande carte, le rond lance la lecture
/// — ou demande où, quand le titre est à plusieurs endroits — sans ouvrir la fiche ; la fiche, elle, a sa capsule ▶︎.
@MainActor
final class LectureTests: XCTestCase {
    private var app = XCUIApplication()

    private func capture(_ nom: String, attente: TimeInterval = 1) {
        Thread.sleep(forTimeInterval: attente)
        let piece = XCTAttachment(screenshot: app.screenshot())
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    func testLeRondLanceLaLectureEtLaFicheASonBouton() throws {
        continueAfterFailure = true
        Lancement.demonstration(app)
        app.launchArguments += ["-apparence", "sombre"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Accueil"].firstMatch.waitForExistence(timeout: 20))

        // Mes listes, en grandes cartes : John Wick, sur le NAS de la démonstration, a son ▶︎.
        app.tabBars.buttons["Mes listes"].firstMatch.tap()
        let rond = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Regarder John Wick'")).firstMatch
        XCTAssertTrue(app.amener(rond, essais: 6), "Pas de bouton ▶︎ sur la carte de John Wick")
        XCTAssertTrue(rond.isHittable)
        capture("carte-lecture")
        rond.tap()
        // Plusieurs accès : le menu demande lequel ; on prend le NAS.
        let nas = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sur ton NAS'")).firstMatch
        if nas.waitForExistence(timeout: 3) {
            capture("carte-lecture-choix")
            nas.tap()
        }
        // Le rond lance la lecture (Infuse n'est pas dans le simulateur : le bandeau le dit) ; la fiche ne s'ouvre pas.
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Regarder maintenant' OR identifier == 'choixLecture'")).firstMatch
            .waitForExistence(timeout: 3), "Toucher ▶︎ a ouvert la fiche au lieu de lancer la lecture")
        XCTAssertTrue(app.staticTexts["Mes listes"].firstMatch.exists, "On a quitté Mes listes")

        // La carte elle-même ouvre la fiche, où la capsule ▶︎ est en tête.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'John Wick'")).firstMatch.tap()
        let grand = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Regarder' AND NOT (label BEGINSWITH 'Regarder John Wick')")).firstMatch
        XCTAssertTrue(grand.waitForExistence(timeout: 10), "Pas de bouton ▶︎ en tête de fiche")
        capture("fiche-lecture")
    }
}
