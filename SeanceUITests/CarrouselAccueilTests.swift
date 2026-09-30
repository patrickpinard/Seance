import XCTest

/// Le carrousel de l'accueil (8.6) : les propositions du soir défilent au doigt et avec « Autre chose », des points disent
/// où l'on en est, et un toucher sur le titre ouvre la fiche.
@MainActor
final class CarrouselAccueilTests: XCTestCase {
    private let app = XCUIApplication()

    private func capture(_ nom: String) {
        let piece = XCTAttachment(screenshot: app.screenshot())
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    func testLesPropositionsDefilentEtOuvrentLaFiche() throws {
        Lancement.demonstration(app)
        app.launch()
        let points = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Proposition 1 sur'")).firstMatch
        XCTAssertTrue(points.waitForExistence(timeout: 30), "Pas de carrousel en tête de l'accueil")
        Thread.sleep(forTimeInterval: 3)
        capture("carrousel-1")
        // Au doigt, vers la gauche : la suivante.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.28))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.28)))
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Proposition 2 sur'")).firstMatch.exists,
                      "Le glissement ne passe pas à la proposition suivante")
        capture("carrousel-2")
        // 8.6, comme Netflix : « Lecture » et « Plus d'infos » ; « Plus d'infos » ouvre la fiche.
        let infos = app.buttons.matching(identifier: "plusDInfos").allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertFalse(infos.isEmpty, "Pas de bouton « Plus d'infos »")
        XCTAssertTrue(app.buttons.matching(identifier: "lectureProposition").allElementsBoundByIndex.contains(where: \.isHittable),
                      "Pas de bouton « Lecture »")
        capture("carrousel-boutons")
        infos.first?.tap()
        Thread.sleep(forTimeInterval: 2.5)
        capture("fiche-ouverte")
        XCTAssertFalse(app.buttons.matching(identifier: "titreProposition").allElementsBoundByIndex.contains(where: \.isHittable),
                       "Le titre n'ouvre pas la fiche")
    }

    /// 8.7 (demande de Patrick) : « ⋯ » à côté de « Plus d'infos » — « Pas ce soir », « Pas ce genre », « Je n'aime pas ».
    /// « Pas ce genre » écarte le genre et le dit ; la proposition suivante prend sa place.
    func testPasCeGenreDepuisLaProposition() throws {
        Lancement.demonstration(app)
        app.launch()
        let points = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Proposition 1 sur'")).firstMatch
        XCTAssertTrue(points.waitForExistence(timeout: 30), "Pas de carrousel en tête de l'accueil")
        Thread.sleep(forTimeInterval: 3)
        // La première proposition qui connaît ses genres (« Prévu ce soir » peut ne pas les avoir).
        for _ in 0..<5 {
            let autres = app.buttons.matching(identifier: "autresActionsProposition").allElementsBoundByIndex.first(where: \.isHittable)
            let bouton = try XCTUnwrap(autres, "Pas de bouton « ⋯ » sur la proposition")
            bouton.tap()
            XCTAssertTrue(app.buttons["Pas ce soir"].waitForExistence(timeout: 5), "Le menu « ⋯ » n'a pas « Pas ce soir »")
            XCTAssertTrue(app.buttons["Je n'aime pas"].exists, "Le menu « ⋯ » n'a pas « Je n'aime pas »")
            capture("menu-proposition")
            let pasCeGenre = app.buttons["Pas ce genre"]
            if pasCeGenre.exists {
                pasCeGenre.tap()
                let genre = app.buttons.matching(NSPredicate(format: "label != 'Pas ce genre'")).allElementsBoundByIndex
                    .last { $0.isHittable && $0.frame.minY > bouton.frame.minY - 600 }
                let nom = try XCTUnwrap(genre?.label)
                capture("menu-genres")
                genre?.tap()
                let confirmation = app.staticTexts["Plus de « \(nom) » dans tes propositions"]
                XCTAssertTrue(confirmation.waitForExistence(timeout: 5), "« Pas ce genre » ne confirme pas")
                capture("genre-ecarte")
                return
            }
            // Pas de genre connu : on ferme le menu et on passe à la suivante.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
            Thread.sleep(forTimeInterval: 0.8)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.28))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.28)))
            Thread.sleep(forTimeInterval: 1.5)
        }
        XCTFail("Aucune proposition ne propose « Pas ce genre »")
    }
}
