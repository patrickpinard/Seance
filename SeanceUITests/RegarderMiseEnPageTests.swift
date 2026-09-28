import XCTest

/// Regarder, source par source (8.6) : la rangée de jours reste à la même place, sans saut de ligne, que l'on soit sur
/// Tout, Streaming, TV ou le NAS, aujourd'hui ou un autre jour.
@MainActor
final class RegarderMiseEnPageTests: XCTestCase {
    private let app = XCUIApplication()

    private func capture(_ nom: String) {
        let piece = XCTAttachment(screenshot: app.screenshot())
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    func testLaRangeeDeJoursNeBougePas() throws {
        Lancement.demonstration(app)
        app.launch()
        app.onglet("Regarder")
        let demain = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Demain' OR label CONTAINS 'demain'")).firstMatch
        XCTAssertTrue(demain.waitForExistence(timeout: 20), "Pas de rangée de jours")
        var hauteurs: [String: CGFloat] = [:]
        for source in ["Tout", "Streaming", "TV", "NAS"] {
            app.pastille(source)
            Thread.sleep(forTimeInterval: 2)
            capture("regarder-\(source)")
            hauteurs[source] = demain.frame.minY
        }
        demain.tap()
        Thread.sleep(forTimeInterval: 1)
        for source in ["Tout", "Streaming", "TV", "NAS"] {
            app.pastille(source)
            Thread.sleep(forTimeInterval: 2)
            capture("regarder-demain-\(source)")
            XCTAssertEqual(demain.frame.minY, hauteurs["Tout"] ?? 0, accuracy: 2, "La rangée de jours se déplace sur \(source) (demain)")
        }
        for source in ["Streaming", "TV", "NAS"] {
            XCTAssertEqual(hauteurs[source] ?? 0, hauteurs["Tout"] ?? 0, accuracy: 2, "La rangée de jours se déplace sur \(source)")
        }
    }
}
