import XCTest

/// Le carrousel de l'accueil sur l'Apple TV (8.6), comme l'app TV d'Apple : gauche sur « Lecture » et droite sur
/// « Plus d'infos » font défiler les propositions ; entre les deux boutons, gauche et droite changent de bouton.
@MainActor
final class CarrouselTVTests: XCTestCase {
    private let app = XCUIApplication()
    private let telecommande = XCUIRemote.shared

    private var reponsesTMDB: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SeanceKit/Tests/SeanceKitTests/Fixtures").path
    }

    private func focusSur(_ texte: String) -> Bool {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true AND label CONTAINS %@", texte)).firstMatch.exists
    }

    private var position: String {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Proposition '")).firstMatch.label
    }

    private func capture(_ nom: String) {
        let piece = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    func testGaucheEtDroiteFontDefilerLesPropositions() throws {
        app.launchEnvironment["SEANCE_DEMO"] = "1"
        app.launchEnvironment["SEANCE_FAUX_TMDB"] = reponsesTMDB
        app.launch()
        let points = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Proposition 1 sur'")).firstMatch
        XCTAssertTrue(points.waitForExistence(timeout: 30), "Pas de carrousel sur l'accueil")
        Thread.sleep(forTimeInterval: 2)
        // Jusqu'à « Lecture » (ou « Reprendre ») ; depuis « Plus d'infos », gauche y ramène sans faire défiler.
        for _ in 0..<3 where !(focusSur("Lecture") || focusSur("Reprendre") || focusSur("Plus d'infos")) {
            telecommande.press(.down); Thread.sleep(forTimeInterval: 0.7)
        }
        if focusSur("Plus d'infos") { telecommande.press(.left); Thread.sleep(forTimeInterval: 0.8) }
        XCTAssertTrue(focusSur("Lecture") || focusSur("Reprendre"), "Le focus n'arrive pas sur « Lecture »")
        let depart = position
        capture("carrousel-tv-1")
        // Droite depuis « Lecture » : le focus passe à « Plus d'infos », la proposition ne change pas.
        telecommande.press(.right); Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(focusSur("Plus d'infos"), "Droite ne mène pas à « Plus d'infos »")
        XCTAssertEqual(position, depart, "Passer d'un bouton à l'autre a changé de proposition")
        // Droite depuis « Plus d'infos » : la suivante.
        telecommande.press(.right); Thread.sleep(forTimeInterval: 1.2)
        XCTAssertNotEqual(position, depart, "Droite sur « Plus d'infos » ne fait pas défiler")
        capture("carrousel-tv-2")
        // Retour à « Lecture », puis gauche : on revient à la première.
        telecommande.press(.left); Thread.sleep(forTimeInterval: 1)
        telecommande.press(.left); Thread.sleep(forTimeInterval: 1.2)
        XCTAssertEqual(position, depart, "Gauche sur « Lecture » ne revient pas à la proposition précédente")
        capture("carrousel-tv-3")
    }
}
