import XCTest

/// La synchronisation par un dossier, de bout en bout, sans iCloud : un « iPad » a déposé son fichier dans le dossier ;
/// l'app doit l'importer à l'ouverture, le dire, montrer le titre et la soirée reçus, et déposer son propre fichier.
@MainActor
final class SynchroTests: XCTestCase {
    private var app = XCUIApplication()

    func testImporteLesAutresAppareilsEtDeposeLeSien() throws {
        continueAfterFailure = true
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("SeanceSynchro-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dossier) }

        // Le fichier d'un autre appareil : « Heat », à voir, prévu dans trois jours.
        let soiree = ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(3 * 86_400)).prefix(10)
        let json = """
        {"version": 1, "creeeLe": "2026-09-18T10:00:00Z", "visionnages": [], "listes": [], "filtres": [], "interets": [], "abonnements": [], "chaines": [],
         "suivis": [{"reference": {"type": "film", "tmdbID": 949}, "statut": "aVoir", "exclusionLangue": false, "ajouteLe": "2026-09-17T20:00:00Z",
                     "titre": "Heat", "cheminAffiche": "/umSVjVdbVwtx5ryCA2QXL44Durm.jpg", "acteursPrincipaux": ["Al Pacino"], "genres": [28, 80]}],
         "soirees": [{"reference": {"type": "film", "tmdbID": 949}, "titre": "Heat", "cheminAffiche": "/umSVjVdbVwtx5ryCA2QXL44Durm.jpg",
                      "soiree": "\(soiree)", "ajouteLe": "2026-09-17T20:00:00Z"}],
         "preferences": {"profil.prenom": {"texte": {"_0": "Camille"}}}}
        """
        try Data(json.utf8).write(to: dossier.appendingPathComponent("Séance — iPad TEST.json"))

        Lancement.demonstration(app)
        app.launchEnvironment["SEANCE_SYNCHRO_DOSSIER"] = dossier.path
        app.launch()

        // Le titre reçu est dans « À voir » (le bandeau « Synchronisé » est masqué à l'accessibilité : il est annoncé, pas lu).
        XCTAssertTrue(app.tabBars.buttons["Mes listes"].firstMatch.waitForExistence(timeout: 20))
        app.tabBars.buttons["Mes listes"].firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Heat'")).firstMatch.waitForExistence(timeout: 10),
                      "Le titre de l'autre appareil n'est pas arrivé dans À voir")

        // L'app a déposé son propre fichier, et il contient ses données.
        let fichiers = try FileManager.default.contentsOfDirectory(atPath: dossier.path)
        let propre = try XCTUnwrap(fichiers.first { $0.hasPrefix("Séance — iPhone") }, "L'app n'a pas déposé son fichier : \(fichiers)")
        let contenu = try String(contentsOf: dossier.appendingPathComponent(propre), encoding: .utf8)
        XCTAssertTrue(contenu.contains("John Wick"), "Le fichier déposé ne contient pas les titres de cet appareil")
        XCTAssertTrue(contenu.contains("Heat"), "Le fichier déposé ne contient pas le titre reçu")
        // Et une sauvegarde datée, à côté : le filet de sécurité.
        let archives = (try? FileManager.default.contentsOfDirectory(atPath: dossier.appendingPathComponent("Sauvegardes datées").path)) ?? []
        XCTAssertEqual(archives.filter { $0.hasPrefix("Séance — iPhone") }.count, 1, "Pas de sauvegarde datée : \(archives)")

        // La page de réglages dit où en est la synchronisation.
        app.tabBars.buttons["Profil"].firstMatch.tap()
        app.navigationBars.buttons["Réglages"].firstMatch.tap()
        app.swipeUp()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sauvegarde'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Synchroniser maintenant"].firstMatch.waitForExistence(timeout: 10))
        let piece = XCTAttachment(screenshot: app.screenshot())
        piece.name = "synchro-reglages"
        piece.lifetime = .keepAlways
        add(piece)
    }
}
