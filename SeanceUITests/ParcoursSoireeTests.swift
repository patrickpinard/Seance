import XCTest

/// Le parcours d'une personne qui organise sa soirée : un film, puis le premier épisode d'une série qu'elle n'a jamais
/// commencée. Il part d'une app vide, vérifie ce qui a été corrigé en 4.5 (série jamais commencée, soirée qui se vide,
/// « Je n'aime pas » et sa remise à zéro) et laisse une capture à chaque étape.
@MainActor
final class ParcoursSoireeTests: XCTestCase {
    private var app = XCUIApplication()
    private var numero = 0

    private func capture(_ nom: String, attente: TimeInterval = 2) {
        Thread.sleep(forTimeInterval: attente)
        numero += 1
        let piece = XCTAttachment(screenshot: app.screenshot())
        piece.name = String(format: "%02d-%@", numero, nom)
        piece.lifetime = .keepAlways
        add(piece)
    }

    private func bouton(_ format: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: format)).firstMatch
    }

    func testFilmPuisPremierEpisode() throws {
        continueAfterFailure = true
        Lancement.demonstration(app)
        app.launchEnvironment["SEANCE_DEMO"] = "vide"
        app.launchArguments += ["-apparence", "sombre"]
        app.launch()
        let plusTard = app.buttons["Plus tard"].firstMatch
        if plusTard.waitForExistence(timeout: 15) { plusTard.tap() }
        XCTAssertTrue(app.tabBars.buttons["Accueil"].firstMatch.waitForExistence(timeout: 15))

        // 1. La feuille d'ajout : la recherche est sur place, sans détour par Explorer.
        app.tabBars.buttons["Ce soir"].firstMatch.tap()
        app.buttons["Choisir quoi regarder"].firstMatch.tap()
        let champ = app.textFields["rechercheSoiree"].firstMatch
        XCTAssertTrue(champ.waitForExistence(timeout: 10), "Pas de recherche dans « Ajouter à ma soirée »")
        capture("feuille", attente: 5)

        // 2. Le film : cherché, ajouté d'un « + ».
        champ.tap()
        champ.typeText("fight")
        let ajouterFilm = app.buttons["Ajouter Fight Club à la soirée"].firstMatch
        XCTAssertTrue(ajouterFilm.waitForExistence(timeout: 15), "La recherche ne trouve pas le film")
        capture("recherche-resultats")
        ajouterFilm.tap()
        XCTAssertTrue(app.buttons["Retirer Fight Club de la soirée"].firstMatch.waitForExistence(timeout: 5), "Le « + » ne dit pas que le film est ajouté")
        app.buttons["Effacer la recherche"].firstMatch.tap()

        // 3. La série, jamais commencée : les idées se limitent aux séries, « Je regarde ».
        // « Je n'aime pas » sur la première idée (un film) : elle laisse sa place, et se retrouvera dans Réglages › Toi.
        let jeNAimePas = app.buttons["Je n'aime pas"].firstMatch
        XCTAssertTrue(jeNAimePas.waitForExistence(timeout: 20), "Pas de « Je n'aime pas » sur les idées")
        jeNAimePas.tap()
        let series = app.buttons["Séries"].firstMatch
        XCTAssertTrue(series.waitForExistence(timeout: 10), "Pas de choix Films / Séries au-dessus des idées")
        series.tap()
        let jeRegarde = app.buttons["Je regarde"].firstMatch
        XCTAssertTrue(jeRegarde.waitForExistence(timeout: 20), "Aucune idée de série")
        capture("idees-series", attente: 3)
        XCTAssertTrue(app.amener(jeRegarde))
        jeRegarde.tap()
        app.buttons["OK"].firstMatch.tap()

        // 4. La soirée : la série propose son premier épisode, avec « Regardé ».
        let carteSerie = bouton("label CONTAINS 'série' AND label CONTAINS 'S01E01'")
        XCTAssertTrue(carteSerie.waitForExistence(timeout: 20), "Une série jamais commencée ne propose pas son premier épisode")
        XCTAssertFalse(app.staticTexts["Aucun nouvel épisode disponible"].exists)
        capture("soiree-remplie", attente: 4)
        app.swipeUp()
        capture("soiree-remplie-bas")

        // 5. Un épisode, pas la série : « Regardé » la retire de la soirée.
        let regardes = app.buttons.matching(identifier: "Regardé")
        XCTAssertEqual(regardes.count, 2, "Le film et l'épisode doivent pouvoir se marquer regardés")
        regardes.element(boundBy: 1).tap()
        XCTAssertTrue(carteSerie.waitForNonExistence(timeout: 15), "L'épisode regardé, la série reste dans la soirée")
        capture("episode-regarde", attente: 1)

        // 6. Le film : regardé, noté.
        app.swipeDown()
        app.buttons["Regardé"].firstMatch.tap()
        let note = app.buttons["Note 8 sur 10"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        note.tap()
        capture("soiree-finie", attente: 3)

        // 7. Réglages › Toi : l'idée écartée y figure, « Tout reproposer » lève les exclusions.
        app.tabBars.buttons["Préférences"].firstMatch.tap()
        app.navigationBars.buttons["Réglages"].firstMatch.tap()
        let toi = bouton("label BEGINSWITH 'Prénom et idées'")
        XCTAssertTrue(app.amener(toi, essais: 16), "Tuile « Prénom et idées » introuvable")
        toi.tap()
        let tout = app.buttons["toutReproposer"].firstMatch
        XCTAssertTrue(app.amener(tout), "Pas de « Tout reproposer » dans Réglages › Toi")
        capture("reglages-ecartes", attente: 1)
        tout.tap()
        app.buttons["Tout reproposer"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Aucun titre écarté"].firstMatch.waitForExistence(timeout: 5), "Les exclusions ne sont pas levées")
        capture("reglages-ecartes-leves", attente: 1)

        // 8. Explorer en dernier (sa barre d'onglets se replie) : la fiche dit l'ajout à la soirée ; « Je n'aime pas » fait sortir le titre d'Explorer.
        app.tabBars.buttons["Explorer"].firstMatch.tap()
        let affiche = bouton("label CONTAINS 'Creed III'")
        XCTAssertTrue(affiche.waitForExistence(timeout: 20))
        affiche.tap()
        let ceSoir = app.buttons["Ajouter à ma soirée"].firstMatch
        XCTAssertTrue(ceSoir.waitForExistence(timeout: 15), "Pas de bouton 🌙 dans la rangée d'actions de la fiche")
        ceSoir.tap()
        XCTAssertTrue(app.buttons["Retirer de ma soirée"].firstMatch.waitForExistence(timeout: 5))
        capture("fiche-ce-soir", attente: 1)
        // 👍 puis 👎 : les pouces de la fiche. Le pouce baissé fait tomber le pouce levé et écarte le titre.
        let jAime = app.buttons["J'aime"].firstMatch
        XCTAssertTrue(jAime.waitForExistence(timeout: 5), "Pas de pouce 👍 sur la fiche")
        jAime.tap()
        XCTAssertTrue(app.buttons["J'aime ✓"].firstMatch.waitForExistence(timeout: 5), "Le pouce levé ne se marque pas")
        capture("fiche-pouces", attente: 1)
        app.buttons["Je n'aime pas"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Je n'aime pas ✓"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["J'aime"].firstMatch.exists, "Le pouce levé devait tomber")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(affiche.waitForNonExistence(timeout: 10), "Un titre écarté reste proposé dans Explorer")
        capture("explorer-sans-le-titre")
    }

    /// La fiche d'un titre qui passe à la TV dit la chaîne, le jour et l'heure dans sa carte « Où regarder ». Sur le
    /// passage du lendemain de la soirée en cours (Jack Ryan, dans la démonstration). La journée TV va de 6 h à 6 h :
    /// entre minuit et six heures, ce lendemain-là est « aujourd'hui » au calendrier — les deux libellés conviennent.
    func testLaFicheDonneLePassageTele() throws {
        Lancement.demonstration(app)
        app.launchArguments += ["-apparence", "sombre"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Accueil"].firstMatch.waitForExistence(timeout: 20))
        app.open(URL(string: "seance://serie/73375")!)
        XCTAssertTrue(app.staticTexts["Où regarder"].firstMatch.waitForExistence(timeout: 25), "La fiche ne s'ouvre pas")
        let passage = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'À la TV · en direct' AND (label CONTAINS 'demain à' OR label CONTAINS %@)", "aujourd'hui à")
        ).firstMatch
        XCTAssertTrue(passage.waitForExistence(timeout: 10), "La carte « Où regarder » ne donne pas la chaîne, le jour et l'heure")
        capture("fiche-passage-tele", attente: 2)
    }
}
