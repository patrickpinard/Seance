import XCTest

/// L'Apple TV, à la télécommande (Séance 6.0). Jusqu'ici, chaque défaut de la TV — casting hors d'atteinte, menu,
/// page qui ne se referme pas — a été trouvé par Patrick devant son téléviseur : ces tests rejouent ses gestes.
@MainActor
final class TelecommandeTests: XCTestCase {
    private var app = XCUIApplication()
    private let telecommande = XCUIRemote.shared

    private var reponsesTMDB: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SeanceKit/Tests/SeanceKitTests/Fixtures").path
    }

    private func lancer(_ environnement: [String: String] = [:]) {
        app.launchEnvironment["SEANCE_DEMO"] = "1"
        app.launchEnvironment["SEANCE_FAUX_TMDB"] = reponsesTMDB
        for (cle, valeur) in environnement { app.launchEnvironment[cle] = valeur }
        app.launch()
    }

    private func capture(_ nom: String) {
        let piece = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    /// Vrai si l'élément qui a le focus porte l'un de ces textes : le focus descend sur la carte la plus proche, pas
    /// forcément la première de la rangée.
    private func focusSur(_ textes: [String]) -> Bool {
        textes.contains { texte in
            app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true AND label CONTAINS %@", texte)).firstMatch.exists
        }
    }

    /// Descend à la télécommande jusqu'à ce que le focus porte l'un de ces textes.
    private func descendreJusqua(_ textes: [String], essais: Int = 14) -> Bool {
        for _ in 0..<essais {
            if focusSur(textes) { return true }
            telecommande.press(.down)
            Thread.sleep(forTimeInterval: 0.6)
        }
        return focusSur(textes)
    }

    /// Le menu est en haut, et ses huit entrées sont là.
    func testLeMenuDuHaut() throws {
        lancer()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "Pas de barre d'onglets en haut")
        for onglet in ["Accueil", "Ce soir", "Mes listes", "Explorer", "TV", "NAS", "Préférences", "Réglages"] {
            XCTAssertTrue(app.tabBars.buttons[onglet].exists, "« \(onglet) » absent du menu")
        }
        capture("tv-menu")
    }

    /// Sur la fiche d'un film du NAS, on descend jusqu'au casting et un visage ouvre la fiche de la personne, où on
    /// peut la suivre. (4.8.2 : une section de focus vide arrêtait la télécommande avant le casting.)
    func testDeLaFicheAuCastingPuisALActeur() throws {
        lancer(["SEANCE_TV_FICHE": "film:324552"])
        XCTAssertTrue(app.buttons["Lire"].waitForExistence(timeout: 30), "La fiche du film du NAS ne s'ouvre pas")
        XCTAssertTrue(descendreJusqua(["Edward Norton", "Brad Pitt", "Helena Bonham Carter", "Meat Loaf", "Jared Leto"]), "La télécommande n'atteint pas le casting")
        capture("tv-casting")
        telecommande.press(.select)
        XCTAssertTrue(app.buttons["Suivre"].waitForExistence(timeout: 15), "La fiche de l'acteur ne s'ouvre pas, ou ne propose pas de le suivre")
        capture("tv-acteur")
        // La touche Retour referme la page, sans quitter l'app.
        telecommande.press(.menu)
        XCTAssertTrue(app.buttons["Lire"].waitForExistence(timeout: 10), "Retour ne ramène pas à la fiche")
    }

    /// Les Réglages en grandes cartes : la première carte à régler s'ouvre, et Retour en revient.
    func testLesReglagesSOuvrentEtSeReferment() throws {
        lancer(["SEANCE_TV_ONGLET": "reglages"])
        XCTAssertTrue(app.staticTexts["État de Séance sur cette TV"].waitForExistence(timeout: 30))
        XCTAssertTrue(descendreJusqua(["TMDB", "Plateformes", "Télévision"]), "La télécommande n'atteint pas les cartes des réglages")
        telecommande.press(.select)
        XCTAssertFalse(app.staticTexts["État de Séance sur cette TV"].waitForExistence(timeout: 3), "La carte choisie n'ouvre rien")
        capture("tv-reglage-tmdb")
        telecommande.press(.menu)
        XCTAssertTrue(app.staticTexts["État de Séance sur cette TV"].waitForExistence(timeout: 10), "Retour ne ramène pas aux Réglages")
    }
}
