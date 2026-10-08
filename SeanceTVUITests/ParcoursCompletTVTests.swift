import XCTest

/// Parcours de bout en bout de l'Apple TV (02.10.2026), à la télécommande, onglet par onglet : chaque étape est
/// capturée, et les temps d'affichage sont notés dans le journal (« MESURE … »), pour le bilan de l'app.
@MainActor
final class ParcoursCompletTVTests: XCTestCase {
    private var app = XCUIApplication()
    private let telecommande = XCUIRemote.shared

    private var reponsesTMDB: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SeanceKit/Tests/SeanceKitTests/Fixtures").path
    }

    override func setUp() {
        continueAfterFailure = true
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

    private func focusSur(_ textes: [String]) -> Bool {
        textes.contains { texte in
            app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true AND label CONTAINS %@", texte)).firstMatch.exists
        }
    }

    private var libelleAuFocus: String {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch.label
    }

    private func presser(_ touche: XCUIRemote.Button, _ fois: Int = 1, pause: Double = 0.7) {
        for _ in 0..<fois { telecommande.press(touche); Thread.sleep(forTimeInterval: pause) }
    }

    /// Jusqu'à l'élément qui porte l'un de ces textes, dans une direction.
    @discardableResult
    private func aller(_ direction: XCUIRemote.Button, jusqua textes: [String], essais: Int = 10) -> Bool {
        for _ in 0..<essais {
            if focusSur(textes) { return true }
            presser(direction)
        }
        return focusSur(textes)
    }

    /// Le temps jusqu'à l'apparition d'un élément, noté dans le journal.
    @discardableResult
    private func mesurer(_ nom: String, _ element: XCUIElement, delai: Double = 30) -> Bool {
        let debut = Date()
        let present = element.waitForExistence(timeout: delai)
        print("MESURE \(nom) : \(String(format: "%.2f", Date().timeIntervalSince(debut))) s\(present ? "" : " (absent)")")
        return present
    }

    private func texte(_ contient: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", contient)).firstMatch
    }

    // MARK: Accueil

    func test01AccueilEtEtageres() throws {
        let debut = Date()
        lancer()
        XCTAssertTrue(mesurer("accueil, première proposition", texte("Proposition 1 sur")), "Pas de proposition sur l'accueil")
        print("MESURE lancement complet jusqu'à l'accueil : \(String(format: "%.2f", Date().timeIntervalSince(debut))) s")
        Thread.sleep(forTimeInterval: 1.5)
        capture("e2e-01-accueil")
        // Les étagères, avant de descendre : les pages paresseuses déchargent ce qui sort de l'écran.
        // « Nouveautés », plus bas, n'est chargée qu'en descendant (page paresseuse) : seule « Reprendre » se vérifie ici.
        XCTAssertTrue(texte("Reprendre").exists, "Étagère « Reprendre » absente de l'accueil")
        XCTAssertTrue(aller(.down, jusqua: ["Lecture", "Reprendre", "Plus d'infos"], essais: 3), "Le focus n'atteint pas la proposition")
        // Les étagères, de haut en bas.
        var vues: [String] = []
        for etape in 0..<8 {
            presser(.down, pause: 1)
            vues.append(libelleAuFocus)
            capture("e2e-01-etagere-\(etape)")
        }
        print("MESURE étagères parcourues : \(vues.joined(separator: " | "))")
        // Et retour tout en haut : le menu revient.
        presser(.up, 10, pause: 0.5)
        XCTAssertTrue(app.tabBars.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch.exists,
                      "En remontant de l'accueil, le focus ne revient pas au menu")
        capture("e2e-01-retour-menu")
    }

    func test02PlusDInfosPuisRetour() throws {
        lancer()
        XCTAssertTrue(texte("Proposition 1 sur").waitForExistence(timeout: 30))
        Thread.sleep(forTimeInterval: 1.5)
        aller(.down, jusqua: ["Lecture", "Reprendre", "Plus d'infos"], essais: 3)
        aller(.right, jusqua: ["Plus d'infos"], essais: 2)
        XCTAssertTrue(focusSur(["Plus d'infos"]), "Pas de « Plus d'infos » au focus")
        presser(.select, pause: 0.1)
        XCTAssertTrue(mesurer("fiche depuis Plus d'infos", texte("Où regarder"), delai: 15), "La fiche ne s'ouvre pas")
        Thread.sleep(forTimeInterval: 1)
        capture("e2e-02-fiche")
        print("MESURE focus à l'ouverture de la fiche : \(libelleAuFocus)")
        presser(.menu, pause: 1.5)
        XCTAssertTrue(texte("Proposition").exists, "Retour : l'accueil n'est pas revenu")
        print("MESURE focus au retour de la fiche : \(libelleAuFocus)")
        capture("e2e-02-retour")
    }

    // MARK: Regarder

    func test03RegarderLesQuatreSources() throws {
        lancer(["SEANCE_TV_ONGLET": "regarder"])
        XCTAssertTrue(mesurer("Regarder", app.buttons["Streaming"].firstMatch), "Pas de sources dans Regarder")
        Thread.sleep(forTimeInterval: 1.5)
        capture("e2e-03-tout")
        aller(.down, jusqua: ["Tout", "Streaming", "NAS", "TV", "Filtres"], essais: 4)
        for source in ["Streaming", "TV", "NAS", "Tout"] {
            let debut = Date()
            for _ in 0..<6 where !focusSur([source]) { presser(.right, pause: 0.5) }
            for _ in 0..<6 where !focusSur([source]) { presser(.left, pause: 0.5) }
            XCTAssertTrue(focusSur([source]), "La télécommande n'atteint pas « \(source) »")
            presser(.select, pause: 2)
            print("MESURE source \(source) : \(String(format: "%.2f", Date().timeIntervalSince(debut))) s")
            capture("e2e-03-\(source)")
        }
    }

    func test04AutreDate() throws {
        lancer(["SEANCE_TV_ONGLET": "regarder"])
        XCTAssertTrue(app.buttons["Choisir une autre date"].firstMatch.waitForExistence(timeout: 30), "Pas de tuile « Autre date »")
        Thread.sleep(forTimeInterval: 1.5)
        // Depuis le menu, le focus arrive sur le jour placé sous « Regarder », pas forcément sur « Auj. ».
        aller(.down, jusqua: ["Aujourd'hui", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"], essais: 3)
        print("MESURE focus en arrivant sur la rangée de jours : \(libelleAuFocus)")
        XCTAssertTrue(aller(.right, jusqua: ["Choisir une autre date", "Autre date"], essais: 10), "La télécommande n'atteint pas « Autre date »")
        presser(.select, pause: 1.5)
        XCTAssertTrue(texte("Autre date").exists, "La grille des dates ne s'ouvre pas")
        capture("e2e-04-grille")
        presser(.down, 2)
        let choisi = libelleAuFocus
        presser(.select, pause: 1.5)
        print("MESURE autre date choisie : \(choisi)")
        capture("e2e-04-apres")
        XCTAssertTrue(app.buttons["Choisir une autre date"].firstMatch.exists, "La grille ne s'est pas refermée")
    }

    // MARK: Mes listes

    func test05MesListesEtSesCommandes() throws {
        lancer(["SEANCE_TV_ONGLET": "listes"])
        XCTAssertTrue(mesurer("Mes listes", app.buttons["Regardable ce soir"].firstMatch), "Mes listes ne s'ouvre pas")
        Thread.sleep(forTimeInterval: 1.5)
        capture("e2e-05-listes")
        print("MESURE focus à l'ouverture de Mes listes : \(libelleAuFocus)")
        for commande in ["Regardable ce soir", "Grille", "Liste"] {
            XCTAssertTrue(app.buttons[commande].firstMatch.exists, "« \(commande) » absent de Mes listes")
        }
        XCTAssertTrue(aller(.down, jusqua: ["À voir", "En cours", "À venir"], essais: 3), "Les onglets de Mes listes sont hors d'atteinte")
        for onglet in ["En cours", "À venir", "À voir"] {
            for _ in 0..<7 where !focusSur([onglet]) { presser(.right, pause: 0.4) }
            for _ in 0..<7 where !focusSur([onglet]) { presser(.left, pause: 0.4) }
            XCTAssertTrue(focusSur([onglet]), "Onglet « \(onglet) » hors d'atteinte")
            presser(.select, pause: 1.2)
            capture("e2e-05-\(onglet)")
        }
        // Passer en liste.
        presser(.down, pause: 1)
        print("MESURE focus sous les onglets de Mes listes : \(libelleAuFocus)")
        capture("e2e-05-sous-onglets")
        XCTAssertTrue(focusSur(["Regardable ce soir", "Ajout récent", "Plus court", "Titre", "Grille", "Liste"]),
                      "Sous les onglets, le focus saute les commandes de la liste (tri, cartes ou liste)")
        for _ in 0..<6 where !focusSur(["Liste"]) { presser(.right, pause: 0.4) }
        if focusSur(["Liste"]) { presser(.select, pause: 1.2) }
        capture("e2e-05-en-liste")
    }

    // MARK: Recherche

    func test06RechercheEtFiltres() throws {
        lancer(["SEANCE_TV_ONGLET": "explorer"])
        XCTAssertTrue(mesurer("Recherche, résultats", texte("titres")), "La recherche ne montre pas de résultats sans texte")
        Thread.sleep(forTimeInterval: 1.5)
        capture("e2e-06-recherche")
        for filtre in ["Catégorie", "Disponibilité", "Genres", "Période"] {
            XCTAssertTrue(texte(filtre).exists, "Filtre « \(filtre) » absent")
        }
        // Descendre du clavier jusqu'aux filtres.
        let atteint = aller(.down, jusqua: ["Catégorie", "Réinitialiser", "Disponibilité"], essais: 8)
        print("MESURE focus après descente dans la recherche : \(libelleAuFocus)")
        XCTAssertTrue(atteint, "Les filtres sont hors d'atteinte sous le clavier")
        capture("e2e-06-filtres")
    }

    // MARK: Fiche d'une série

    func test07FicheSerieEtEpisodes() throws {
        lancer(["SEANCE_TV_FICHE": "serie:1399"])
        XCTAssertTrue(mesurer("fiche série", texte("Où regarder"), delai: 20), "La fiche de la série ne s'ouvre pas")
        Thread.sleep(forTimeInterval: 1.5)
        capture("e2e-07-fiche-serie")
        XCTAssertTrue(app.buttons["Saison 1"].firstMatch.waitForExistence(timeout: 10), "Pas de saisons sur la fiche")
        XCTAssertTrue(aller(.down, jusqua: ["Saison"], essais: 10), "Les saisons sont hors d'atteinte")
        presser(.right, 2)
        presser(.select, pause: 2)
        capture("e2e-07-saison")
        presser(.down, 1, pause: 1)
        print("MESURE focus sous les saisons : \(libelleAuFocus)")
        capture("e2e-07-episodes")
    }

    // MARK: Préférences et Réglages

    func test08PreferencesEtReglages() throws {
        lancer(["SEANCE_TV_ONGLET": "profil"])
        XCTAssertTrue(mesurer("Préférences", texte("Langue et sous-titres")), "Les Préférences ne s'ouvrent pas")
        Thread.sleep(forTimeInterval: 1)
        capture("e2e-08-preferences")
        XCTAssertTrue(texte("propositions").exists, "Pas de ligne « Accueil » (nombre de propositions)")
        app.terminate()
        lancer(["SEANCE_TV_ONGLET": "reglages"])
        XCTAssertTrue(mesurer("Réglages", texte("à compléter")), "Pas d'encart « à compléter » dans les Réglages")
        Thread.sleep(forTimeInterval: 1)
        capture("e2e-08-reglages")
        aller(.down, jusqua: ["Plateformes"], essais: 4)
        for _ in 0..<12 {
            presser(.down, pause: 0.8)
        }
        print("MESURE dernière ligne des Réglages atteinte : \(libelleAuFocus)")
        capture("e2e-08-reglages-bas")
    }
}
