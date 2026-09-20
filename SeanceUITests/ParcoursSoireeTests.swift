import XCTest

/// Le parcours d'une personne qui organise sa soirée : un film, puis le premier épisode d'une série qu'elle n'a jamais
/// commencée. Il part d'une app vide et laisse une capture à chaque étape, pour juger de la fluidité du chemin.
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

    /// Ce que l'accessibilité voit de l'écran : boutons et textes, pour relire le parcours sans l'image.
    private func releve(_ nom: String) {
        let boutons = app.buttons.allElementsBoundByIndex.prefix(60).map(\.label).filter { !$0.isEmpty }
        let textes = app.staticTexts.allElementsBoundByIndex.prefix(60).map(\.label).filter { !$0.isEmpty }
        print("RELEVE \(nom) BOUTONS \(boutons)")
        print("RELEVE \(nom) TEXTES \(textes)")
    }

    private func ajouterParLaFiche(_ nom: String) {
        let plus = app.buttons["Plus d'actions"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 15), "\(nom) : la fiche ne s'ouvre pas")
        capture("fiche-\(nom)", attente: 3)
        releve("fiche-\(nom)")
        plus.tap()
        capture("fiche-\(nom)-menu", attente: 1)
        let ajouter = app.buttons["Ajouter à ma soirée"].firstMatch
        XCTAssertTrue(ajouter.waitForExistence(timeout: 5), "\(nom) : « Ajouter à ma soirée » absent du menu")
        ajouter.tap()
        capture("fiche-\(nom)-ajoute", attente: 1.5)
    }

    func testFilmPuisPremierEpisode() throws {
        continueAfterFailure = true
        Lancement.demonstration(app)
        app.launchEnvironment["SEANCE_DEMO"] = "vide"
        app.launchArguments += ["-apparence", "sombre"]
        app.launch()
        let plusTard = app.buttons["Plus tard"].firstMatch
        if plusTard.waitForExistence(timeout: 15) {
            capture("bienvenue", attente: 1)
            plusTard.tap()
        }
        XCTAssertTrue(app.tabBars.buttons["Accueil"].firstMatch.waitForExistence(timeout: 15))
        capture("accueil", attente: 5)

        // 1. Ce soir, vide : que propose la page ?
        app.tabBars.buttons["Ce soir"].firstMatch.tap()
        capture("ce-soir-vide", attente: 3)
        releve("ce-soir-vide")
        app.buttons["Choisir quoi regarder"].firstMatch.tap()
        capture("ajouter-feuille", attente: 5)
        releve("ajouter-feuille")
        app.swipeUp()
        capture("ajouter-feuille-bas")
        releve("ajouter-feuille-bas")

        // 2. Chercher un film : la feuille renvoie à Explorer.
        let chercher = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Chercher un titre'")).firstMatch
        XCTAssertTrue(app.amener(chercher), "« Chercher un titre » introuvable")
        chercher.tap()
        capture("explorer-arrivee", attente: 4)
        releve("explorer-arrivee")

        // 3. Le film : sa fiche, puis « Ajouter à ma soirée ».
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'John Wick: Chapter 4'")).firstMatch.tap()
        ajouterParLaFiche("film")
        app.navigationBars.buttons.firstMatch.tap()
        capture("explorer-retour", attente: 2)
        releve("explorer-retour")

        // 4. La série, jamais commencée : sa fiche, l'ajout, puis ses épisodes.
        app.buttons["Séries"].firstMatch.tap()
        capture("explorer-series", attente: 4)
        releve("explorer-series")
        let serie = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'note '")).firstMatch
        XCTAssertTrue(serie.waitForExistence(timeout: 10), "Aucune série dans Explorer")
        serie.tap()
        ajouterParLaFiche("serie")
        app.swipeUp()
        capture("fiche-serie-episodes", attente: 2)
        releve("fiche-serie-episodes")
        app.swipeUp()
        capture("fiche-serie-episodes-2", attente: 2)
        releve("fiche-serie-episodes-2")
        app.navigationBars.buttons.firstMatch.tap()

        // 5. Retour à la soirée : que disent les deux cartes ?
        // En recherche, la barre d'onglets a disparu : le bouton 🌙 « Ce soir » ramène à la soirée.
        capture("explorer-avant-retour", attente: 2)
        app.buttons["Ce soir"].firstMatch.tap()
        capture("ce-soir-rempli", attente: 5)
        releve("ce-soir-rempli")
        app.swipeUp()
        capture("ce-soir-rempli-bas", attente: 2)
        releve("ce-soir-rempli-bas")

        // 6. La soirée se vit : l'épisode 1 se coche-t-il depuis la carte ? Sinon, par la fiche.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Game of Thrones'")).firstMatch.tap()
        let cocher = app.buttons["Marquer S01E01 comme vu"].firstMatch
        XCTAssertTrue(app.amener(cocher), "Le prochain épisode ne se coche pas depuis la fiche")
        cocher.tap()
        capture("fiche-serie-episode-coche", attente: 2)
        releve("fiche-serie-episode-coche")
        app.navigationBars.buttons.firstMatch.tap()
        capture("ce-soir-apres-episode", attente: 5)
        releve("ce-soir-apres-episode")

        // 7. Le film : « Regardé », puis la note.
        app.swipeDown()
        app.buttons["Regardé"].firstMatch.tap()
        capture("ce-soir-film-regarde", attente: 3)
        releve("ce-soir-film-regarde")
        let note = app.buttons["Note 8 sur 10"].firstMatch
        if note.waitForExistence(timeout: 5) { note.tap() }
        capture("ce-soir-fin", attente: 3)
        releve("ce-soir-fin")

        // 8. Les raccourcis : « Je regarde » sur une idée, puis l'appui long sur une affiche d'Explorer.
        app.buttons["Ajouter"].firstMatch.tap()
        let jeRegarde = app.buttons["Je regarde"].firstMatch
        if jeRegarde.waitForExistence(timeout: 15) { jeRegarde.tap() }
        capture("idee-je-regarde", attente: 2)
        releve("idee-je-regarde")
        app.buttons["OK"].firstMatch.tap()
        capture("ce-soir-apres-idee", attente: 3)
        app.tabBars.buttons["Explorer"].firstMatch.tap()
        let affiche = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'note '")).firstMatch
        if affiche.waitForExistence(timeout: 15) { affiche.press(forDuration: 1.2) }
        capture("explorer-appui-long", attente: 1.5)
        releve("explorer-appui-long")
    }
}
