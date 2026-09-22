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
        // En haut à gauche de la page : qui regarde.
        let quiRegarde = app.buttons.matching(NSPredicate(format: "identifier == 'quiRegarde' OR label CONTAINS 'Anne'")).firstMatch
        XCTAssertTrue(quiRegarde.waitForExistence(timeout: 5), "Le nom de la personne n'est pas affiché en haut de la page")
        XCTAssertTrue(quiRegarde.label.contains("Anne"), "La pastille ne dit pas qui regarde : « \(quiRegarde.label) »")
        capture("famille-listes-anne")

        // La pastille ouvre « Qui regarde ? » ; rechoisir Anne referme sans rien changer.
        quiRegarde.tap()
        XCTAssertTrue(app.staticTexts["Qui regarde ?"].waitForExistence(timeout: 5), "La pastille n'ouvre pas « Qui regarde ? »")
        capture("famille-qui-regarde")
        // Le profil principal garde son nom : il prenait le prénom de la personne en cours (deux « Anne »).
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Anne'")).count, 1, "Deux profils s'appellent « Anne » dans « Qui regarde ? »")
        app.buttons["Anne"].firstMatch.tap()
        XCTAssertTrue(app.tabBars.buttons["Accueil"].firstMatch.waitForExistence(timeout: 15))

        // Retour au profil principal : ses listes sont là.
        ouvrirFamille()
        let retour = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Passer au profil de'")).firstMatch
        XCTAssertTrue(retour.waitForExistence(timeout: 5))
        retour.tap()
        XCTAssertTrue(app.tabBars.buttons["Accueil"].firstMatch.waitForExistence(timeout: 15))
        app.tabBars.buttons["Mes listes"].firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'John Wick'")).firstMatch.waitForExistence(timeout: 10),
                      "De retour au profil principal, ses listes ont disparu")

        // « Qui regarde ce soir ? » : Anne se coche dans les idées de la feuille « Ajouter à ma soirée ».
        app.tabBars.buttons["Ce soir"].firstMatch.tap()
        let ajouter = app.navigationBars.buttons["Ajouter"].firstMatch
        XCTAssertTrue(ajouter.waitForExistence(timeout: 10), "Pas de bouton « Ajouter » sur Ce soir")
        ajouter.tap()
        XCTAssertTrue(app.textFields["rechercheSoiree"].firstMatch.waitForExistence(timeout: 10), "La feuille « Ajouter à ma soirée » ne s'ouvre pas")
        let anne = app.buttons["Anne regarde aussi"].firstMatch
        XCTAssertTrue(app.amener(anne, essais: 12), "« Qui regarde ce soir ? » n'est pas proposé")
        anne.tap()
        XCTAssertTrue(anne.isSelected, "Anne n'est pas cochée")
        capture("famille-ce-soir", attente: 4)
        app.buttons["OK"].firstMatch.tap()

        // 6.1 « Vu avec qui ? » : un film terminé depuis sa fiche s'inscrit aussi chez Anne, cochée d'office puisqu'elle
        // regarde ce soir.
        app.tabBars.buttons["Mes listes"].firstMatch.tap()
        let film = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'John Wick'")).firstMatch
        XCTAssertTrue(film.waitForExistence(timeout: 10))
        film.tap()
        let termine = app.buttons["Terminé"].firstMatch
        XCTAssertTrue(app.amener(termine, versLeHaut: true, essais: 4), "Pas de bouton « Terminé » sur la fiche du film")
        termine.tap()
        XCTAssertTrue(app.staticTexts["Vu avec qui ?"].firstMatch.waitForExistence(timeout: 8), "« Vu avec qui ? » ne s'ouvre pas")
        XCTAssertTrue(app.buttons["Anne l'a vu aussi"].firstMatch.isSelected, "Anne, qui regarde ce soir, n'est pas cochée d'office")
        capture("famille-vu-avec-qui")
        app.buttons["validerAvecQui"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Vu avec qui ?"].firstMatch.waitForNonExistence(timeout: 10), "La feuille ne se referme pas")

        // Chez Anne, le film est dans Terminés, sous le mois en cours.
        app.navigationBars.buttons.firstMatch.tap()
        ouvrirFamille()
        app.buttons["Passer au profil de Anne"].firstMatch.tap()
        XCTAssertTrue(app.tabBars.buttons["Accueil"].firstMatch.waitForExistence(timeout: 15))
        app.tabBars.buttons["Mes listes"].firstMatch.tap()
        app.buttons["Terminés"].firstMatch.tap()
        let format = DateFormatter()
        format.locale = Locale(identifier: "fr_CH")
        format.dateFormat = "LLLL yyyy"
        let mois = format.string(from: .now)
        let entete = mois.prefix(1).uppercased() + mois.dropFirst()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", entete)).firstMatch.waitForExistence(timeout: 10),
                      "Le film vu ensemble n'est pas dans les Terminés d'Anne, sous « \(entete) »")
        capture("famille-termines-anne")
    }
}
