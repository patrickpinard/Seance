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
    /// Le bouton de lecture en tête de fiche : « Lire » pour un seul accès, « Regarder… » quand il y en a plusieurs (6.3 : la
    /// démonstration a des abonnements, John Wick est sur le NAS et sur deux plateformes).
    private var boutonLecture: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == 'Lire' OR label BEGINSWITH 'Regarder'")).firstMatch
    }

    func testDeLaFicheAuCastingPuisALActeur() throws {
        lancer(["SEANCE_TV_FICHE": "film:324552"])
        XCTAssertTrue(boutonLecture.waitForExistence(timeout: 30), "La fiche du film du NAS ne s'ouvre pas")
        XCTAssertTrue(descendreJusqua(["Edward Norton", "Brad Pitt", "Helena Bonham Carter", "Meat Loaf", "Jared Leto"]), "La télécommande n'atteint pas le casting")
        capture("tv-casting")
        telecommande.press(.select)
        XCTAssertTrue(app.buttons["Suivre"].waitForExistence(timeout: 15), "La fiche de l'acteur ne s'ouvre pas, ou ne propose pas de le suivre")
        capture("tv-acteur")
        // La touche Retour referme la page, sans quitter l'app.
        telecommande.press(.menu)
        XCTAssertTrue(boutonLecture.waitForExistence(timeout: 10), "Retour ne ramène pas à la fiche")
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

    /// Famille : « Qui regarde ? » à l'ouverture ; choisir Anne ouvre ses listes à elle, vides, pas celles du profil principal.
    func testQuiRegardeALOuverture() throws {
        lancer(["SEANCE_TV_FAMILLE": "Anne", "SEANCE_TV_ONGLET": "listes"])
        XCTAssertTrue(app.staticTexts["Qui regarde ?"].waitForExistence(timeout: 30), "Pas de « Qui regarde ? » à l'ouverture avec deux profils")
        capture("tv-qui-regarde")
        for _ in 0..<3 where !focusSur(["Anne"]) { telecommande.press(.right); Thread.sleep(forTimeInterval: 0.6) }
        XCTAssertTrue(focusSur(["Anne"]), "La télécommande n'atteint pas le profil d'Anne")
        telecommande.press(.select)
        XCTAssertTrue(app.staticTexts["Tes listes sont vides sur cette TV"].waitForExistence(timeout: 20), "Le profil d'Anne montre les listes d'un autre")
        // En haut à gauche, à la hauteur du menu : qui regarde.
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Qui regarde : Anne'")).firstMatch.waitForExistence(timeout: 5),
                      "Le prénom d'Anne n'est pas affiché en haut à gauche")
        capture("tv-listes-anne")

        // 6.1 : le prénom est un bouton. Du menu du haut, vers la gauche, la télécommande l'atteint et rouvre « Qui regarde ? ».
        for _ in 0..<3 where !focusSur(["Mes listes", "Accueil", "Ce soir"]) { telecommande.press(.up); Thread.sleep(forTimeInterval: 0.6) }
        for _ in 0..<8 where !focusSur(["Qui regarde : Anne"]) { telecommande.press(.left); Thread.sleep(forTimeInterval: 0.6) }
        XCTAssertTrue(focusSur(["Qui regarde : Anne"]), "La télécommande n'atteint pas le prénom en haut à gauche")
        capture("tv-pastille-focus")
        telecommande.press(.select)
        XCTAssertTrue(app.staticTexts["Qui regarde ?"].waitForExistence(timeout: 10), "Le prénom n'ouvre pas « Qui regarde ? »")
        capture("tv-qui-regarde-depuis-pastille")
    }

    /// 6.2 : les vidéos personnelles en albums de souvenirs, rangés par année, comme sur l'iPhone.
    func testVideosPersonnellesEnAlbums() throws {
        lancer(["SEANCE_TV_ONGLET": "nas"])
        // La tuile est en tête de la page NAS : on attend qu'elle soit là, puis on remonte jusqu'à elle si besoin.
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Vidéos personnelles'")).firstMatch
            .waitForExistence(timeout: 30), "Pas de tuile « Vidéos personnelles » sur la page NAS")
        for _ in 0..<4 where !focusSur(["Vidéos personnelles"]) { telecommande.press(.down); Thread.sleep(forTimeInterval: 0.6) }
        for _ in 0..<4 where !focusSur(["Vidéos personnelles"]) { telecommande.press(.up); Thread.sleep(forTimeInterval: 0.6) }
        XCTAssertTrue(focusSur(["Vidéos personnelles"]), "La télécommande n'atteint pas « Vidéos personnelles »")
        telecommande.press(.select)
        XCTAssertTrue(app.staticTexts["2026"].firstMatch.waitForExistence(timeout: 15), "Pas de section « 2026 »")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS \"Vacances d'été\"")).firstMatch.exists,
                      "L'album « Vacances d'été » est absent")
        capture("tv-souvenirs")
        // L'anniversaire, plus récent, est la première carte de « 2026 » : l'album est à sa droite.
        for _ in 0..<3 where !focusSur(["Vacances d'été"]) { telecommande.press(.right); Thread.sleep(forTimeInterval: 0.6) }
        XCTAssertTrue(focusSur(["Vacances d'été"]) || descendreJusqua(["Vacances d'été"], essais: 4), "La télécommande n'atteint pas l'album")
        telecommande.press(.select)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Plage, premier jour'")).firstMatch.waitForExistence(timeout: 10),
                      "L'album ne s'ouvre pas sur ses vidéos")
        capture("tv-souvenirs-album")
    }

    /// 6.3 : l'historique des versions sur la TV, la même liste que sur l'iPhone ; une ligne s'ouvre sur ce qu'elle apporte.
    func testHistoriqueDesVersions() throws {
        lancer(["SEANCE_TV_ONGLET": "reglages", "SEANCE_TV_REGLAGE": "versions"])
        let liste = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Version 6.3'")).firstMatch
        XCTAssertTrue(liste.waitForExistence(timeout: 30), "La page Versions ne s'ouvre pas sur la TV")
        capture("tv-versions")
        XCTAssertTrue(descendreJusqua(["Version 6.3"], essais: 4), "La télécommande n'atteint pas la version installée")
        telecommande.press(.select)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Les logos sur les cartes de la TV'")).firstMatch
            .waitForExistence(timeout: 10), "La version ne s'ouvre pas sur ce qu'elle apporte")
        capture("tv-versions-ouverte")
    }


    /// 6.3 : « Regarder » ouvre le choix de la source dans une page de Séance (`DialogueTV`), lisible — les fenêtres du
    /// système écrivaient blanc sur blanc —, et la touche Retour la referme.
    func testLeChoixDeLaSourceEstLisible() throws {
        lancer(["SEANCE_TV_FICHE": "film:324552"])
        let regarder = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Regarder'")).firstMatch
        XCTAssertTrue(regarder.waitForExistence(timeout: 30), "Pas de bouton « Regarder » sur la fiche")
        // Le focus sur le bouton lui-même — pas sur un autre élément qui dirait « Regarder » plus bas.
        let aLeFocus = { regarder.value(forKey: "hasFocus") as? Bool == true }
        for _ in 0..<6 where !aLeFocus() { telecommande.press(.down); Thread.sleep(forTimeInterval: 0.6) }
        for _ in 0..<6 where !aLeFocus() { telecommande.press(.up); Thread.sleep(forTimeInterval: 0.6) }
        XCTAssertTrue(aLeFocus(), "La télécommande n'atteint pas « Regarder »")
        capture("tv-fiche-regarder")
        telecommande.press(.select)
        XCTAssertTrue(app.staticTexts["Où veux-tu le lancer ?"].waitForExistence(timeout: 10), "Le choix de la source ne s'ouvre pas")
        capture("tv-choix-source")
        telecommande.press(.menu)
        XCTAssertFalse(app.staticTexts["Où veux-tu le lancer ?"].waitForExistence(timeout: 3), "Retour ne referme pas le choix de la source")
    }
}
