import XCTest

/// Les plantages de l'iPhone qu'aucun test ne voyait (8.11, après l'audit) : toucher une alerte de Séance (6.2 à 8.8),
/// et le lecteur qui publie son affiche au Centre de contrôle (8.10).
@MainActor
final class RegressionsTests: XCTestCase {
    private var app = XCUIApplication()
    private let accueil = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    private func capture(_ nom: String, de cible: XCUIApplication? = nil) {
        let piece = XCTAttachment(screenshot: (cible ?? app).screenshot())
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    /// La version `async` du délégué rendait la main à iOS hors du fil principal : toucher l'alerte arrêtait Séance.
    func testToucherUneAlerteOuvreLaFiche() throws {
        Lancement.demonstration(app)
        app.launchEnvironment["SEANCE_ALERTE_ESSAI"] = "seance://film/11"
        app.launch()
        // La première fois, iOS demande l'autorisation des alertes.
        for libelle in ["Autoriser", "Allow"] {
            let bouton = accueil.buttons[libelle].firstMatch
            if bouton.waitForExistence(timeout: 4) { bouton.tap(); break }
        }
        XCUIDevice.shared.press(.home)
        let alerte = accueil.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Essai de Séance'")).firstMatch
        XCTAssertTrue(alerte.waitForExistence(timeout: 20), "L'alerte d'essai n'est pas arrivée (alertes refusées dans ce simulateur ?)")
        capture("alerte", de: accueil)
        alerte.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "Toucher l'alerte n'a pas ramené Séance")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(app.state, .runningForeground, "Séance s'est arrêtée après le toucher de l'alerte")
        capture("apres-alerte")
    }

    /// MediaPlayer demande l'affiche depuis sa propre file : écrit sur le fil principal, le bloc arrêtait l'app.
    func testLeLecteurPublieSonAfficheSansSArreter() throws {
        let racine = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let video = racine.appendingPathComponent(".build/essai-tv/mire.mp4").path
        try XCTSkipUnless(FileManager.default.fileExists(atPath: video), "Pas de vidéo d'essai (.build/essai-tv/mire.mp4)")
        Lancement.demonstration(app)
        app.launchEnvironment["SEANCE_LIRE_FICHIER"] = video
        app.launchEnvironment["SEANCE_LIRE_AFFICHE"] = racine.appendingPathComponent("Seance/Assets.xcassets/AppIcon.appiconset/AppIcon.png").path
        app.launch()
        Thread.sleep(forTimeInterval: 8)
        capture("lecteur")
        XCTAssertEqual(app.state, .runningForeground, "Le lecteur s'est arrêté (Centre de contrôle, affiche)")
    }
}
