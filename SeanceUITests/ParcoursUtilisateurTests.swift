import XCTest

/// Le parcours d'un vrai utilisateur, avec la vraie clé TMDB et le vrai NAS (23 septembre 2026) : ce que Patrick voit
/// en ouvrant Séance pour la première fois, ce qu'il doit taper, et ce qui se passe quand il lance chaque format de
/// vidéo. Ces tests ne tournent que si les secrets sont dans l'environnement du runner — ils ne sont jamais écrits ici :
///
///   TEST_RUNNER_SEANCE_CLE_TMDB=$(cat outils/.cle-tmdb) TEST_RUNNER_NAS_MDP=$(cat outils/.mdp-nas) \
///     outils/tests-interface.sh ParcoursUtilisateurTests
///
@MainActor
final class ParcoursUtilisateurTests: XCTestCase {
    private var app = XCUIApplication()

    private var cleTMDB: String { ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] ?? "" }
    private var motDePasseNAS: String { ProcessInfo.processInfo.environment["NAS_MDP"] ?? "" }
    private var hoteNAS: String { ProcessInfo.processInfo.environment["NAS_HOTE"] ?? "192.168.1.220" }

    private func capture(_ nom: String, attente: TimeInterval = 1.2) {
        Thread.sleep(forTimeInterval: attente)
        let piece = XCTAttachment(screenshot: app.screenshot())
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    private func lancer(neuf: Bool) throws {
        try XCTSkipIf(cleTMDB.isEmpty, "Pas de clé TMDB dans l'environnement du runner")
        app.launchEnvironment["SEANCE_CLE_TMDB"] = cleTMDB
        if neuf { app.launchArguments += ["-bienvenue.terminee", "NO"] }
        app.launch()
    }

    /// Premier lancement : ce que Séance montre à quelqu'un qui n'a rien configuré.
    func testPremierLancement() throws {
        try lancer(neuf: true)
        capture("01-ouverture", attente: 6)
        // On note simplement ce qui s'affiche : parcours de bienvenue, ou accueil vide.
        let bienvenue = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Bienvenue' OR label CONTAINS 'Séance'")).firstMatch
        XCTAssertTrue(bienvenue.waitForExistence(timeout: 20) || app.tabBars.firstMatch.exists, "Rien ne s'affiche au premier lancement")
        capture("02-premier-ecran", attente: 3)
    }

    /// Configuration du NAS, comme Patrick la ferait : Réglages › NAS, quatre champs, puis l'analyse.
    func testConfigurerLeNASPuisAnalyser() throws {
        try XCTSkipIf(motDePasseNAS.isEmpty, "Pas de mot de passe NAS dans l'environnement du runner")
        try lancer(neuf: false)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "Pas de barre d'onglets")

        // Réglages : la roue dentée en haut de chaque page (7.0).
        app.ouvrirReglages()
        capture("10-reglages", attente: 2)

        let ligneNAS = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'NAS'")).firstMatch
        XCTAssertTrue(app.amener(ligneNAS), "Pas d'entrée NAS dans les Réglages")
        ligneNAS.tap()
        capture("11-reglage-nas", attente: 2)

        remplir("Adresse", hoteNAS)
        remplir("Partage", "Films")
        remplir("Utilisateur", "admin")
        remplir("Mot de passe", motDePasseNAS, secret: true)
        remplir("Films, NEW, Séries", "Films, Séries")
        capture("12-nas-rempli", attente: 1)

        let tester = app.buttons["Enregistrer et tester la connexion"].firstMatch
        XCTAssertTrue(app.amener(tester), "Pas de bouton pour tester la connexion")
        tester.tap()
        // La connexion réelle peut prendre plusieurs secondes.
        capture("13-nas-teste", attente: 20)
    }

    /// L'analyse réelle du NAS, puis la lecture de chaque format : ce qui se lit dans Séance, ce qui part ailleurs.
    func testAnalyserPuisLireChaqueFormat() throws {
        try XCTSkipIf(motDePasseNAS.isEmpty, "Pas de mot de passe NAS")
        try lancer(neuf: false)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))

        // La bibliothèque du NAS, depuis l'accueil.
        let boutonNAS = app.buttons["boutonNAS"].firstMatch
        XCTAssertTrue(app.amener(boutonNAS, essais: 10), "Pas d'étagère « Sur ton NAS » sur l'accueil")
        boutonNAS.tap()
        capture("20-nas", attente: 4)

        // Le rayon « Vidéos » : les vidéos personnelles, tous formats confondus.
        let perso = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Vidéos'")).firstMatch
        guard perso.waitForExistence(timeout: 10) else { return capture("21-pas-de-perso", attente: 1) }
        perso.tap()
        capture("22-perso", attente: 6)

        // Chaque format : on ouvre la première vidéo qui le porte et on regarde ce qui se passe.
        for format in ["MP4", "M4V", "MOV", "AVI", "WMV"] {
            let carte = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", format)).firstMatch
            guard app.amener(carte, essais: 14) else {
                capture("30-\(format)-introuvable", attente: 0.5)
                continue
            }
            carte.tap()
            capture("31-\(format)-lecture", attente: 14)
            // Retour : la croix du lecteur, ou l'alerte, ou la page.
            let croix = app.buttons["Fermer le lecteur"].firstMatch
            if croix.waitForExistence(timeout: 3) {
                croix.tap()
            } else if app.buttons["OK"].firstMatch.exists {
                capture("32-\(format)-alerte", attente: 0.5)
                app.buttons["OK"].firstMatch.tap()
            }
            Thread.sleep(forTimeInterval: 2)
        }
        capture("39-fin", attente: 1)
    }

    private func remplir(_ libelle: String, _ valeur: String, secret: Bool = false) {
        let champ = secret ? app.secureTextFields[libelle].firstMatch : app.textFields[libelle].firstMatch
        guard app.amener(champ, essais: 6) else { return }
        champ.tap()
        if let ancien = champ.value as? String, !ancien.isEmpty, ancien != libelle {
            champ.press(forDuration: 1.0)
            if app.menuItems["Tout sélectionner"].firstMatch.waitForExistence(timeout: 2) {
                app.menuItems["Tout sélectionner"].firstMatch.tap()
            }
        }
        champ.typeText(valeur)
    }
}
