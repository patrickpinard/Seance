import XCTest

/// Le tour de l'app sans clé TMDB, grâce au faux TMDB : chaque page s'ouvre, montre ce qu'elle doit, et laisse une
/// capture à relire. Écrit pour l'iPhone. Sur un iPad, il sert aux captures : la barre d'onglets du haut n'y montre
/// que trois onglets (les autres sont derrière « > » ou dans la barre latérale), et l'étape Profil y échoue.
@MainActor
final class TourCompletTests: XCTestCase {
    private var app = XCUIApplication()

    private func capture(_ nom: String, attente: TimeInterval = 2.5) {
        Thread.sleep(forTimeInterval: attente)
        let piece = XCTAttachment(screenshot: app.screenshot())
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    /// Barre d'onglets sur l'iPhone ; sur l'iPad, les onglets sont des boutons en haut ou des lignes de barre latérale.
    private func onglet(_ nom: String) {
        let enBas = app.tabBars.buttons[nom].firstMatch
        if enBas.exists { enBas.tap(); return }
        let ligne = app.cells.matching(NSPredicate(format: "label == %@", nom)).firstMatch
        if ligne.exists { ligne.tap() } else { app.buttons[nom].firstMatch.tap() }
    }

    func testTourComplet() throws {
        continueAfterFailure = true
        Lancement.demonstration(app)
        app.launch()

        // Accueil : le faux TMDB remplit le Top et « Du moment » ; la démonstration, la télé et le NAS.
        XCTAssertTrue(app.staticTexts["Du moment"].firstMatch.waitForExistence(timeout: 20), "L'accueil ne charge pas « Du moment »")
        capture("01-accueil", attente: 5)
        app.swipeUp()
        capture("02-accueil-tele")
        app.swipeUp()
        capture("03-accueil-bas")

        // Ce soir : la rangée de jours et les grandes cartes.
        onglet("Ce soir")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Ce soir, '")).firstMatch.waitForExistence(timeout: 10),
                      "La rangée des soirées est absente")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reacher'")).firstMatch.waitForExistence(timeout: 10))
        capture("04-ce-soir", attente: 4)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Demain' OR label CONTAINS 'rien de prévu'")).element(boundBy: 1).tap()
        capture("05-ce-soir-autre-jour")

        // Mes listes : grille, liste, puis « À venir » avec sa rangée de jours.
        onglet("Mes listes")
        XCTAssertTrue(app.buttons["Grille"].firstMatch.waitForExistence(timeout: 10), "Pas de choix grille ou liste")
        capture("06-listes-grille")
        app.buttons["Liste"].firstMatch.tap()
        capture("07-listes-liste")
        app.buttons["Grille"].firstMatch.tap()
        app.buttons["Terminés"].firstMatch.tap()
        capture("08-listes-termines")
        app.buttons["À venir"].firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tout : '")).firstMatch.waitForExistence(timeout: 10),
                      "La rangée de jours d'« À venir » est absente")
        capture("09-a-venir", attente: 4)
        app.swipeUp()
        capture("10-a-venir-bas")

        // La page NAS, depuis l'accueil.
        onglet("Accueil")
        app.buttons["boutonNAS"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Nouveaux sur ton NAS"].firstMatch.waitForExistence(timeout: 10), "Les nouveautés du NAS sont absentes")
        capture("14-nas", attente: 4)

        // Profil.
        onglet("Profil")
        XCTAssertTrue(app.staticTexts["Ta collection"].firstMatch.waitForExistence(timeout: 10))
        capture("15-profil")

        // Explorer : les sources.
        onglet("Explorer")
        XCTAssertTrue(app.buttons["Source : NAS"].firstMatch.waitForExistence(timeout: 15), "Le sélecteur de source est absent")
        capture("11-explorer", attente: 5)
        app.buttons["Source : Télé"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Cette semaine"].firstMatch.waitForExistence(timeout: 5))
        capture("12-explorer-tele", attente: 5)
        app.buttons["Source : NAS"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '0 films'")).firstMatch.exists == false,
                      "La source NAS ne trouve aucun film alors que le NAS de démonstration en a")
        capture("13-explorer-nas", attente: 5)
    }
}
