import XCTest

/// Les vidéos personnelles (EF-157 à EF-159), avec les exemples de la démonstration : l'entrée depuis la page NAS, les
/// albums de souvenirs (6.2) et leur couverture, un retour qui ramène aux albums, et le réglage avec sa case à cocher.
/// Depuis la 6.3, ils sont un rayon de la page NAS (« Perso »), pas une tuile à part.
@MainActor
final class VideosPersoTests: XCTestCase {
    private var app = XCUIApplication()

    private func capture(_ nom: String) {
        Thread.sleep(forTimeInterval: 1.5)
        let piece = XCTAttachment(screenshot: app.screenshot()); piece.name = nom; piece.lifetime = .keepAlways; add(piece)
    }

    func testParcoursEtReglage() throws {
        continueAfterFailure = true
        Lancement.demonstration(app)
        app.launch()
        // La bibliothèque s'ouvre par « Tout voir » de l'étagère « Sur ton NAS », plus bas sur l'accueil.
        XCTAssertTrue(app.staticTexts["Nouveautés"].firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(app.amener(app.buttons["boutonNAS"].firstMatch), "L'étagère « Sur ton NAS » n'a pas de « Tout voir »")
        app.buttons["boutonNAS"].firstMatch.tap()
        // 6.3 : un rayon du sélecteur, au même rang que Films et Séries ; « Vidéos » depuis la 6.5.
        let perso = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Vidéos'")).firstMatch
        XCTAssertTrue(perso.waitForExistence(timeout: 10), "La page NAS n'a pas de rayon « Vidéos »")
        perso.tap()
        capture("videos-racine")

        // 6.2 (piste B) : des albums de souvenirs, rangés par année, en grandes cartes à icône.
        XCTAssertTrue(app.staticTexts["2026"].firstMatch.waitForExistence(timeout: 5), "Pas de section « 2026 »")
        let vacances = app.buttons.matching(NSPredicate(format: "label BEGINSWITH \"Vacances d'été\"")).firstMatch
        XCTAssertTrue(vacances.waitForExistence(timeout: 5), "L'album « Vacances d'été » est absent")
        XCTAssertTrue(vacances.label.contains("album") && vacances.label.contains("Vacances"), "L'album n'a pas son icône proposée : « \(vacances.label) »")
        // Une vidéo seule, rangée dans « 2026 », fait carte à elle seule et se lance d'un toucher.
        let anniversaire = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Anniversaire de Camille'")).firstMatch
        XCTAssertTrue(app.amener(anniversaire, essais: 4), "La vidéo seule « Anniversaire de Camille » est absente")
        XCTAssertTrue(anniversaire.label.contains("vidéo") && anniversaire.label.contains("Anniversaire"))
        capture("videos-albums")

        // L'album s'ouvre sur ses vidéos, dans l'ordre.
        app.swipeDown(); app.swipeDown()
        vacances.tap()
        XCTAssertTrue(app.navigationBars["Vacances d'été"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Plage, premier jour'")).firstMatch.waitForExistence(timeout: 5),
                      "La vidéo de l'album est absente")
        capture("videos-album")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(vacances.waitForExistence(timeout: 8), "Un retour ne ramène pas aux albums")

        // La feuille « Couverture » : un appui long, une autre icône, et l'album la porte.
        vacances.press(forDuration: 1.2)
        let couverture = app.buttons["Couverture…"].firstMatch
        XCTAssertTrue(couverture.waitForExistence(timeout: 5), "Pas de « Couverture… » à l'appui long")
        couverture.tap()
        let montagne = app.buttons["Montagne"].firstMatch
        XCTAssertTrue(montagne.waitForExistence(timeout: 8), "La feuille « Couverture » ne propose pas les icônes")
        montagne.tap()
        capture("videos-couverture")
        app.buttons["validerCouverture"].firstMatch.tap()
        let apres = app.buttons.matching(NSPredicate(format: "label BEGINSWITH \"Vacances d'été\"")).firstMatch
        XCTAssertTrue(apres.waitForExistence(timeout: 5))
        XCTAssertTrue(apres.label.contains("Montagne"), "L'icône choisie n'est pas celle de l'album : « \(apres.label) »")

        // Le réglage : une ligne de l'état, et une case à cocher.
        app.tabBars.buttons["Préférences"].firstMatch.tap()
        app.navigationBars.buttons["Réglages"].firstMatch.tap()
        let ligne = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Vidéos personnelles'")).firstMatch
        XCTAssertTrue(app.amener(ligne), "La ligne « Vidéos personnelles » est absente de l'état")
        ligne.tap()
        XCTAssertTrue(app.switches["Inclure mes vidéos personnelles"].firstMatch.waitForExistence(timeout: 8), "La case à cocher est absente")
        capture("videos-reglage")
    }
}
