import XCTest

/// Visite des pages, pour relire l'interface sur des captures.
@MainActor
final class VisiteTests: XCTestCase {
    private var app = XCUIApplication()

    private func capture(_ nom: String, attente: TimeInterval = 2.5) {
        Thread.sleep(forTimeInterval: attente)
        let piece = XCTAttachment(screenshot: app.screenshot())
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    /// Sur l'iPhone, Réglages s'ouvre depuis l'engrenage de Profil.
    private func ouvrirReglages() {
        app.ouvrirReglages()
    }

    func testPremierLancement() throws {
        continueAfterFailure = true
        if let cle = ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] {
            app.launchEnvironment["SEANCE_CLE_TMDB"] = cle
        }
        app.launchEnvironment["SEANCE_BIENVENUE"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["Bienvenue dans Séance"].waitForExistence(timeout: 10))
        capture("71-bienvenue")
        app.buttons["Commencer"].tap()
        capture("72-plateformes", attente: 4)
        app.buttons["Suivant"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Qu'aimes-tu regarder ?"].waitForExistence(timeout: 5))
        app.buttons["Action"].firstMatch.tap()
        app.buttons["Thriller"].firstMatch.tap()
        app.buttons["Arts martiaux"].firstMatch.tap()
        capture("73-gouts")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Suivant'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["As-tu vu ce film ?"].waitForExistence(timeout: 20), "Notation rapide absente")
        capture("74-notation")
        app.buttons["Note 9 sur 10"].firstMatch.tap()
        app.buttons["Note 8 sur 10"].firstMatch.tap()
        app.buttons["Je ne l'ai pas vu"].firstMatch.tap()
        capture("75-notation-suite", attente: 1.5)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Terminer'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["C'est prêt !"].waitForExistence(timeout: 5))
        capture("76-fin")
        app.buttons["Découvrir Séance"].tap()
        XCTAssertTrue(app.tabBars.buttons["Accueil"].firstMatch.waitForExistence(timeout: 5))
    }

    /// Données de démonstration en mémoire : statistiques et bilan en cartes.
    func testStatistiques() throws {
        continueAfterFailure = true
        if let cle = ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] {
            app.launchEnvironment["SEANCE_CLE_TMDB"] = cle
        }
        app.launchEnvironment["SEANCE_DEMO"] = "1"
        app.launch()
        app.ouvrirPreferences()
        capture("80-profil")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tes statistiques'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Mois par mois"].waitForExistence(timeout: 5))
        capture("81-statistiques")
        app.swipeUp()
        capture("82-statistiques-bas")
        app.swipeDown()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Ton année' OR label BEGINSWITH 'Ton bilan'")).firstMatch.tap()
        capture("83-bilan-heures", attente: 5)
        for nom in ["84-bilan-titres", "85-bilan-acteur", "86-bilan-genres", "87-bilan-film", "88-bilan-soiree", "89-bilan-resume"] {
            app.swipeLeft()
            capture(nom, attente: 1.5)
        }
        XCTAssertTrue(app.buttons["Partager cette carte"].exists, "Bouton de partage absent")
        app.buttons["Partager cette carte"].tap()
        capture("90-partage", attente: 3)
    }

    /// Vues des widgets à leurs tailles, puis liens des widgets vers Ce soir et À venir.
    func testWidgets() throws {
        continueAfterFailure = true
        if let cle = ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] {
            app.launchEnvironment["SEANCE_CLE_TMDB"] = cle
        }
        app.launchEnvironment["SEANCE_DEMO"] = "1"
        app.launchEnvironment["SEANCE_APERCU_WIDGETS"] = "1"
        app.launch()
        ouvrirReglages()
        app.swipeUp()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Aperçu des widgets'")).firstMatch.tap()
        capture("91-widgets-accueil", attente: 5)
        app.swipeUp()
        capture("92-widgets-bas")
        app.swipeUp()
        capture("93-widgets-verrouille")

        app.open(URL(string: "seance://cesoir")!)
        capture("94-lien-ce-soir", attente: 4)
        app.open(URL(string: "seance://avenir")!)
        capture("95-lien-a-venir", attente: 4)
        XCTAssertTrue(app.buttons["À venir"].firstMatch.isSelected, "Mes listes ne s'est pas ouvert sur À venir")
    }

    /// Ce soir sans la recherche d'idées, le lien vers Explorer, puis les versions repliables.
    func testCeSoirEtVersions() throws {
        continueAfterFailure = true
        if let cle = ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] {
            app.launchEnvironment["SEANCE_CLE_TMDB"] = cle
        }
        app.launchEnvironment["SEANCE_DEMO"] = "1"
        app.launch()
        // La page ne montre que la sélection du soir ; tout le reste est dans « Ajouter ».
        app.aller("Ce soir")
        XCTAssertTrue(app.amener(app.buttons["Suggestions pour ce soir"].firstMatch))
        capture("96-ce-soir", attente: 5)
        app.buttons["Suggestions pour ce soir"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Suggestions pour ce soir"].waitForExistence(timeout: 10), "La feuille ne propose pas de suggestions")
        capture("97-ajouter", attente: 4)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Chercher un titre'")).firstMatch.tap()
        capture("97-vers-explorer")

        // Dans Explorer, la barre d'onglets se replie autour du champ de recherche.
        app.terminate()
        app.launch()
        ouvrirReglages()
        app.swipeUp()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'À propos'")).firstMatch.tap()
        app.buttons["Versions"].firstMatch.tap()
        capture("98-versions")
        app.swipeUp()
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Version 1.1'")).firstMatch.tap()
        capture("99-versions-1-1", attente: 1.5)
    }

    /// Grand écran (iPad, même mise en page que le Mac) : barre latérale, fiche en deux colonnes, grilles.
    func testGrandEcran() throws {
        continueAfterFailure = true
        if let cle = ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] {
            app.launchEnvironment["SEANCE_CLE_TMDB"] = cle
        }
        app.launchEnvironment["SEANCE_DEMO"] = "1"
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        // Les onglets de la barre latérale sont des lignes de liste.
        func onglet(_ nom: String) {
            app.aller(nom)
        }
        capture("A1-accueil", attente: 6)
        onglet("Ce soir")
        capture("A2-ce-soir", attente: 3)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reacher'")).firstMatch.tap()
        capture("A3-fiche-serie", attente: 6)
        app.swipeUp()
        capture("A4-fiche-serie-bas", attente: 2)
        app.ouvrirPreferences()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tes statistiques'")).firstMatch.tap()
        capture("A5-statistiques", attente: 3)
        onglet("Explorer")
        capture("A6-explorer", attente: 6)
    }

    /// Affiches après un défilement rapide, puis l'espace utilisé dans À propos.
    func testAffichesEtEspaceUtilise() throws {
        continueAfterFailure = true
        if let cle = ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] {
            app.launchEnvironment["SEANCE_CLE_TMDB"] = cle
        }
        app.launchEnvironment["SEANCE_DEMO"] = "1"
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        Thread.sleep(forTimeInterval: 4)
        // Défilement rapide : les affiches interrompues doivent se recharger en revenant.
        for _ in 0..<4 { app.swipeUp(velocity: .fast) }
        capture("B1-accueil-bas", attente: 3)
        for _ in 0..<4 { app.swipeDown(velocity: .fast) }
        capture("B2-accueil-retour", attente: 3)
        ouvrirReglages()
        app.swipeUp()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'À propos'")).firstMatch.tap()
        app.swipeUp()
        capture("B3-espace-utilise", attente: 3)
    }
}
