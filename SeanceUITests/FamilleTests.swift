import XCTest

/// Famille (6.0) : un second profil a ses listes à lui, et l'on revient aux siennes en rechangeant de profil.
@MainActor
final class FamilleTests: XCTestCase {
    private var app = XCUIApplication()

    private func capture(_ nom: String, attente: TimeInterval = 2) {
        Thread.sleep(forTimeInterval: attente)
        let piece = XCTAttachment(screenshot: app.screenshot())
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    private func ouvrirFamille() {
        app.tabBars.buttons["Préférences"].firstMatch.tap()
        app.navigationBars.buttons["Réglages"].firstMatch.tap()
        let tuile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Famille'")).firstMatch
        XCTAssertTrue(app.amener(tuile), "Pas de tuile « Famille » dans les Réglages")
        tuile.tap()
        XCTAssertTrue(app.navigationBars["Famille"].waitForExistence(timeout: 8))
    }

    func testUnSecondProfilASesListes() throws {
        continueAfterFailure = true
        Lancement.demonstration(app)
        app.launchArguments += ["-apparence", "sombre"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Accueil"].firstMatch.waitForExistence(timeout: 20))

        // Le profil principal a ses listes.
        app.tabBars.buttons["Mes listes"].firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'John Wick'")).firstMatch.waitForExistence(timeout: 10))

        // Anne arrive dans la famille.
        ouvrirFamille()
        app.buttons["ajouterProfil"].firstMatch.tap()
        let champ = app.textFields["prenomProfil"].firstMatch
        XCTAssertTrue(champ.waitForExistence(timeout: 5))
        champ.tap()
        champ.typeText("Anne")
        app.buttons["OK"].firstMatch.tap()
        capture("famille-deux-profils")
        let choisirAnne = app.buttons["Passer au profil de Anne"].firstMatch
        XCTAssertTrue(choisirAnne.waitForExistence(timeout: 5), "Le nouveau profil n'apparaît pas")
        choisirAnne.tap()

        // L'app se reconstruit sur le magasin d'Anne : pas de listes, mais les plateformes de la maison.
        XCTAssertTrue(app.tabBars.buttons["Accueil"].firstMatch.waitForExistence(timeout: 15))
        app.tabBars.buttons["Mes listes"].firstMatch.tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'John Wick'")).firstMatch.waitForExistence(timeout: 4),
                       "Les listes du profil principal se voient dans celui d'Anne")
        capture("famille-listes-anne")

        // Retour au profil principal : ses listes sont là.
        ouvrirFamille()
        let retour = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Passer au profil de'")).firstMatch
        XCTAssertTrue(retour.waitForExistence(timeout: 5))
        retour.tap()
        XCTAssertTrue(app.tabBars.buttons["Accueil"].firstMatch.waitForExistence(timeout: 15))
        app.tabBars.buttons["Mes listes"].firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'John Wick'")).firstMatch.waitForExistence(timeout: 10),
                      "De retour au profil principal, ses listes ont disparu")
    }
}
