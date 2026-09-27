import XCTest

/// Regarder › Tout, à la télécommande : les cartes de la soirée s'ouvrent sans arrêter l'app (27.09.2026 : la première et
/// la deuxième carte faisaient quitter Séance sur l'Apple TV de Patrick).
@MainActor
final class RegarderTests: XCTestCase {
    private let app = XCUIApplication()
    private let telecommande = XCUIRemote.shared

    private var reponsesTMDB: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SeanceKit/Tests/SeanceKitTests/Fixtures").path
    }

    private func capture(_ nom: String) {
        let piece = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    private var carteAuFocus: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    func testLesCartesDeLaSoireeSOuvrent() throws {
        for rang in 0..<2 {
            app.launchEnvironment["SEANCE_DEMO"] = "1"
            app.launchEnvironment["SEANCE_FAUX_TMDB"] = reponsesTMDB
            app.launchEnvironment["SEANCE_TV_ONGLET"] = "regarder"
            app.launch()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
            Thread.sleep(forTimeInterval: 3)
            // De la barre d'onglets à la rangée de jours, puis aux cartes de la soirée.
            var trouvee = false
            for _ in 0..<6 {
                telecommande.press(.down)
                Thread.sleep(forTimeInterval: 0.8)
                let label = carteAuFocus.label
                if label.contains("Reacher") || label.contains("Film") || label.contains("Série") { trouvee = true; break }
            }
            capture("carte-\(rang)-avant")
            XCTAssertTrue(trouvee, "Le focus n'arrive pas sur les cartes de la soirée (focus : \(carteAuFocus.label))")
            // Le focus descend sur la carte la plus proche : on revient d'abord à la première de la rangée.
            for _ in 0..<3 { telecommande.press(.left); Thread.sleep(forTimeInterval: 0.6) }
            for _ in 0..<rang { telecommande.press(.right); Thread.sleep(forTimeInterval: 0.8) }
            let nom = carteAuFocus.label
            telecommande.press(.select)
            Thread.sleep(forTimeInterval: 6)
            capture("carte-\(rang)-ouverte")
            XCTAssertEqual(app.state, .runningForeground, "Séance s'est arrêtée en ouvrant « \(nom) »")
            app.terminate()
        }
    }
}
