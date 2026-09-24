import XCTest

/// Parcours de la maquette Explorer : les filtres réduisent vraiment les résultats.
@MainActor
final class ExplorerTests: XCTestCase {
    private func capture(_ nom: String, _ app: XCUIApplication) {
        let piece = XCTAttachment(screenshot: app.screenshot())
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    private func texteCompteur(_ app: XCUIApplication) -> String {
        let compteur = app.descendants(matching: .any)["compteurResultats"].firstMatch
        return compteur.label
    }

    func testLesFiltresReduisentLesResultats() throws {
        let app = XCUIApplication()
        if let cle = ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] {
            app.launchEnvironment["SEANCE_CLE_TMDB"] = cle
        }
        app.launch()
        app.aller("Explorer")

        let compteur = app.descendants(matching: .any)["compteurResultats"].firstMatch
        XCTAssertTrue(compteur.waitForExistence(timeout: 20), "Compteur absent")
        let depart = NSPredicate(format: "label CONTAINS 'films'")
        wait(for: [XCTNSPredicateExpectation(predicate: depart, object: compteur)], timeout: 20)
        let avant = texteCompteur(app)
        capture("explorer-depart", app)

        app.buttons["boutonFiltres"].tap()
        let action = app.staticTexts["Action"].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 15), "Genres absents de la feuille")
        action.tap()
        let artsMartiaux = app.staticTexts["Arts martiaux"].firstMatch
        if !artsMartiaux.isHittable { app.swipeUp() }
        artsMartiaux.tap()
        let voir = app.buttons["voirResultats"]
        let compte = NSPredicate(format: "label MATCHES '.*Voir [0-9].*films.*'")
        wait(for: [XCTNSPredicateExpectation(predicate: compte, object: voir)], timeout: 20)
        capture("explorer-feuille", app)
        voir.tap()

        XCTAssertTrue(app.buttons["Retirer Action"].waitForExistence(timeout: 10), "La puce Action n'apparaît pas")
        let change = NSPredicate(format: "label != %@ AND label CONTAINS 'films' AND NOT (label CONTAINS 'Plus de')", avant)
        wait(for: [XCTNSPredicateExpectation(predicate: change, object: compteur)], timeout: 20)
        capture("explorer-resultats", app)
        print("Compteur avant : \(avant) ; après : \(texteCompteur(app))")
    }
}
