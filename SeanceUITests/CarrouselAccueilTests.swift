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
}
