import XCTest

/// Le tour de l'app sans clé TMDB, grâce au faux TMDB : chaque page s'ouvre, montre ce qu'elle doit, et laisse une
/// capture à relire. Écrit pour l'iPhone. Sur un iPad, il sert aux captures : la barre d'onglets du haut n'y montre
/// que trois onglets (les autres sont derrière « > » ou dans la barre latérale), et l'étape Profil y échoue.
@MainActor
final class TourCompletTests: XCTestCase {
    private var app = XCUIApplication()

    private var prefixe = ""

    private func capture(_ nom: String, attente: TimeInterval = 2.5) {
        Thread.sleep(forTimeInterval: attente)
        let piece = XCTAttachment(screenshot: app.screenshot())
        piece.name = prefixe + nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    /// Barre d'onglets sur l'iPhone ; sur l'iPad, les onglets sont des boutons en haut ou des lignes de barre latérale.
    private func onglet(_ nom: String) {
        let enBas = app.tabBars.buttons[nom].firstMatch
        if enBas.exists { enBas.tap(); return }
        let ligne = app.cells.matching(NSPredicate(format: "label == %@", nom)).firstMatch
        if ligne.exists { ligne.tap() } else { app.buttons[nom].firstMatch.tap() }
    }

    /// L'apparence d'origine.
    func testTourComplet() throws {
        try tour(apparence: "sombre", prefixe: "")
    }

    /// Le même tour en apparence claire : chaque page doit rester lisible.
    func testTourEnClair() throws {
        try tour(apparence: "clair", prefixe: "clair-")
    }

    /// Texte très agrandi (réglage d'accessibilité d'iOS) : les pages principales se capturent pour relecture.
    func testGrandTexte() throws {
        continueAfterFailure = true
        Lancement.demonstration(app)
        app.launchArguments += ["-apparence", "sombre", "-profil.prenom", "Camille",
                                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch()
        prefixe = "grand-"
        XCTAssertTrue(app.staticTexts["Nouveautés"].firstMatch.waitForExistence(timeout: 20))
        capture("01-accueil", attente: 5)
        app.swipeUp()
        capture("02-accueil-tele")
        onglet("Ce soir")
        capture("03-ce-soir", attente: 4)
        onglet("Mes listes")
        capture("04-listes")
        app.buttons["À venir"].firstMatch.tap()
        capture("05-a-venir", attente: 3)
        onglet("Profil")
        capture("06-profil", attente: 3)
        app.navigationBars.buttons["Réglages"].firstMatch.tap()
        capture("07-reglages", attente: 3)
        app.open(URL(string: "seance://tele")!)
        capture("08-tele", attente: 5)
    }

    private func tour(apparence: String, prefixe: String) throws {
        continueAfterFailure = true
        Lancement.demonstration(app)
        // Les réglages du simulateur restent d'un test à l'autre : apparence et prénom sont imposés.
        app.launchArguments += ["-apparence", apparence, "-profil.prenom", "Camille"]
        app.launch()
        self.prefixe = prefixe

        // Accueil : le faux TMDB remplit le Top et « Nouveautés » ; la démonstration, la TV et le NAS.
        XCTAssertTrue(app.staticTexts["Nouveautés"].firstMatch.waitForExistence(timeout: 20), "L'accueil ne charge pas « Nouveautés »")
        XCTAssertTrue(app.staticTexts["Regardable ce soir, dans ta liste"].firstMatch.waitForExistence(timeout: 10),
                      "L'accueil ne montre pas ce qui est regardable ce soir dans la liste")
        capture("01-accueil", attente: 5)
        app.swipeUp()
        capture("02-accueil-tele")
        app.swipeUp()
        capture("03-accueil-bas")

        // Ce soir : la rangée de jours et les grandes cartes.
        onglet("Ce soir")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Ce soir, '")).firstMatch.waitForExistence(timeout: 10),
                      "La rangée des soirées est absente")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reacher'")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Hier soir, Heat'")).firstMatch.waitForExistence(timeout: 8),
                      "La soirée d'hier ne demande pas si le film a été regardé")
        capture("04-ce-soir", attente: 4)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Demain' OR label CONTAINS 'rien de prévu'")).element(boundBy: 1).tap()
        capture("05-ce-soir-autre-jour")

        // Mes listes : grille, liste, puis « À venir » avec sa rangée de jours.
        onglet("Mes listes")
        XCTAssertTrue(app.buttons["Grille"].firstMatch.waitForExistence(timeout: 10), "Pas de choix grille ou liste")
        capture("06-listes-grille")
        // Une fiche ouverte depuis la grille se referme : un seul retour ramène à Mes listes.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'John Wick'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 3)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["Grille"].firstMatch.waitForExistence(timeout: 8), "Depuis une fiche ouverte dans la grille, un retour ne ramène pas à Mes listes")
        app.buttons["Liste"].firstMatch.tap()
        capture("07-listes-liste")
        app.buttons["Grille"].firstMatch.tap()
        app.buttons["Terminés"].firstMatch.tap()
        capture("08-listes-termines")
        // Une liste nommée s'ouvre en grille d'affiches.
        app.buttons["Listes"].firstMatch.tap()
        let listeNommee = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Soirées Keanu'")).firstMatch
        XCTAssertTrue(listeNommee.waitForExistence(timeout: 8), "La liste nommée de la démonstration est absente")
        listeNommee.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'John Wick'")).firstMatch.waitForExistence(timeout: 8))
        capture("08-liste-nommee")
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["À venir"].firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tout : '")).firstMatch.waitForExistence(timeout: 10),
                      "La rangée de jours d'« À venir » est absente")
        capture("09-a-venir", attente: 4)
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Nouvel épisode' OR label CONTAINS 'Sur '")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 3)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["À venir"].firstMatch.waitForExistence(timeout: 8), "Depuis une fiche ouverte dans « À venir », un retour ne ramène pas à Mes listes")
        app.swipeUp()
        capture("10-a-venir-bas")

        // La page NAS, depuis l'accueil.
        onglet("Accueil")
        XCTAssertTrue(app.amener(app.buttons["boutonNAS"].firstMatch), "L'étagère « Sur ton NAS » n'a pas de « Tout voir »")
        app.buttons["boutonNAS"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Nouveaux sur ton NAS"].firstMatch.waitForExistence(timeout: 10), "Les nouveautés du NAS sont absentes")
        capture("14-nas", attente: 4)

        // Une fiche, par un lien direct : The Night Agent, dont trois épisodes sont sur le NAS de démonstration.
        app.open(URL(string: "seance://serie/129552")!)
        capture("15-fiche", attente: 7)
        app.swipeUp()
        capture("16-fiche-bas")
        // « Sur ton NAS » dit la saison ; la lecture se lance depuis la liste des épisodes. Dans le simulateur, Infuse
        // n'est pas installée, et l'app doit le dire.
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Saison 1, épisodes 1 à 3'")).firstMatch.waitForExistence(timeout: 8),
                      "« Sur ton NAS » ne dit pas quelle saison il contient")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Lire Épisode'")).firstMatch.exists,
                       "Les épisodes sont encore listés une seconde fois dans « Sur ton NAS »")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Saison 1'")).firstMatch.tap()
        var essais = 0
        let episode = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Lire l’épisode 1 ' OR label BEGINSWITH \"Lire l'épisode 1 \"")).firstMatch
        while !(episode.exists && episode.isHittable), essais < 6 { app.swipeUp(); essais += 1 }
        XCTAssertTrue(episode.exists, "L'épisode 1, présent sur le NAS, n'a pas de bouton de lecture dans la liste des épisodes")
        if episode.exists, episode.isHittable {
            episode.tap()
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 8), "Toucher ▶︎ sur l'épisode ne tente pas d'ouvrir le lecteur")
            capture("16-lecture", attente: 1)
            app.alerts.buttons["OK"].firstMatch.tap()
        }
        capture("16-episodes")
        // Retour depuis la fiche elle-même : sur l'accueil, le premier bouton de la barre est « Personnaliser ».
        app.navigationBars.buttons.firstMatch.tap()

        // Profil : des images, pas de chiffres ; les statistiques en bas, puis Réglages et l'apparence.
        onglet("Profil")
        XCTAssertTrue(app.staticTexts["Tes goûts"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Ta collection"].exists, "Les chiffres sont encore mis en avant sur le Profil")
        capture("17-profil", attente: 4)
        app.swipeUp()
        capture("18-profil-bas")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tes statistiques'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Ta collection"].firstMatch.waitForExistence(timeout: 10), "La collection n'est pas dans les statistiques")
        capture("19-statistiques", attente: 3)
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons["Réglages"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Tes appareils"].firstMatch.waitForExistence(timeout: 10))
        capture("20-reglages", attente: 3)
        app.swipeUp()
        capture("21-reglages-bas")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Nouvel appareil'")).firstMatch.waitForExistence(timeout: 5),
                      "Le parcours « Nouvel appareil » n'est pas proposé dans les réglages")
        // Piste B : « Lecture » est une ligne de l'état, en haut de la page.
        let lecture = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Lecture'")).firstMatch
        XCTAssertTrue(app.amener(lecture, versLeHaut: true), "La ligne « Lecture » est absente de l'état")
        lecture.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'VLC'")).firstMatch.waitForExistence(timeout: 10), "Le choix du lecteur est absent")
        capture("21-lecture")
        app.navigationBars.buttons.firstMatch.tap()
        let apparence = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Apparence'")).firstMatch
        XCTAssertTrue(app.amener(apparence), "La tuile « Apparence » est absente")
        apparence.tap()
        XCTAssertTrue(app.buttons["Apparence Clair"].firstMatch.waitForExistence(timeout: 10))
        capture("22-apparence")
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()

        // Explorer : les sources.
        onglet("Explorer")
        XCTAssertTrue(app.buttons["NAS"].firstMatch.waitForExistence(timeout: 15), "Le sélecteur de source est absent")
        capture("11-explorer", attente: 5)
        app.buttons["TV"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Cette semaine"].firstMatch.waitForExistence(timeout: 5))
        capture("12-explorer-tele", attente: 5)
        // Source TV : seulement ce qui passe sur ses chaînes. Le guide de la démonstration compte cinq films à venir,
        // et chaque affiche dit sur quelle chaîne et quand.
        let surLaTele = app.buttons.matching(NSPredicate(format: "label CONTAINS 'RTS' OR label CONTAINS 'TF1' OR label CONTAINS 'M6' OR label CONTAINS 'W9' OR label CONTAINS 'France' OR label CONTAINS 'Arte' OR label CONTAINS 'TMC'"))
        XCTAssertTrue(surLaTele.firstMatch.waitForExistence(timeout: 10), "Les résultats de la source TV ne disent pas sur quelle chaîne")
        // « John Wick » (le premier) est sur le NAS de la démonstration mais sur aucune chaîne : il ne doit pas être là.
        let intrus = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'John Wick,' OR label CONTAINS ', John Wick,'"))
        XCTAssertEqual(intrus.count, 0, "La source TV liste un titre qui ne passe sur aucune chaîne")
        app.buttons["NAS"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '0 films'")).firstMatch.exists == false,
                      "La source NAS ne trouve aucun film alors que le NAS de démonstration en a")
        capture("13-explorer-nas", attente: 5)
    }
}
