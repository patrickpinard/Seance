import XCTest

/// La visite de tous les écrans, avec les vraies données (clé TMDB dans l'environnement du runner) : une capture par
/// écran, et un relevé de ce qui manque ou ne répond pas. Ce test ne juge pas — il enregistre ce qu'un utilisateur voit,
/// pour le rapport de parcours du 23 septembre 2026. Il ne doit jamais échouer sur un écran absent : il le note.
@MainActor
final class VisiteCompleteTests: XCTestCase {
    private var app = XCUIApplication()
    /// Ce que la visite a relevé, écrit à la fin dans une pièce jointe.
    private var releve: [String] = []

    private var cleTMDB: String { ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] ?? "" }

    override func setUp() {
        continueAfterFailure = true
    }

    private func capture(_ nom: String, attente: TimeInterval = 1.5) {
        Thread.sleep(forTimeInterval: attente)
        let piece = XCTAttachment(screenshot: app.screenshot())
        piece.name = nom
        piece.lifetime = .keepAlways
        add(piece)
    }

    private func noter(_ ligne: String) { releve.append(ligne) }

    private func deposerLeReleve() {
        let piece = XCTAttachment(string: releve.joined(separator: "\n"))
        piece.name = "releve"
        piece.lifetime = .keepAlways
        add(piece)
    }

    /// Touche un élément s'il existe ; note son absence sinon.
    @discardableResult
    private func toucher(_ element: XCUIElement, _ quoi: String, amener: Bool = true) -> Bool {
        if amener ? app.amener(element, essais: 8) : element.waitForExistence(timeout: 5) {
            element.tap()
            return true
        }
        noter("MANQUE · \(quoi)")
        return false
    }

    private func onglet(_ nom: String) {
        app.aller(nom)
        Thread.sleep(forTimeInterval: 2)
    }

    /// Revient au début de la pile, quoi qu'il arrive.
    private func revenir(_ fois: Int = 1) {
        for _ in 0..<fois {
            let retour = app.navigationBars.buttons.firstMatch
            if retour.exists, retour.isHittable { retour.tap(); Thread.sleep(forTimeInterval: 1.2) }
        }
    }

    func testVisiteDeTousLesEcrans() throws {
        try XCTSkipIf(cleTMDB.isEmpty, "Pas de clé TMDB")
        app.launchEnvironment["SEANCE_CLE_TMDB"] = cleTMDB
        app.launch()
        // Famille : « Qui regarde ? » s'affiche à chaque lancement dès qu'il y a plusieurs profils — il faut le passer
        // avant de voir quoi que ce soit. C'est déjà un constat : sur un appareil personnel, c'est un écran de plus.
        if app.staticTexts["Qui regarde ?"].waitForExistence(timeout: 12) {
            noter("Au lancement : « Qui regarde ? » s'affiche avant l'accueil (4 profils synchronisés)")
            capture("A0-qui-regarde", attente: 1)
            let premier = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Patrick'")).firstMatch
            if premier.waitForExistence(timeout: 5) { premier.tap() } else { app.buttons.element(boundBy: 0).tap() }
            Thread.sleep(forTimeInterval: 4)
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 40), "Pas de barre d'onglets")

        // ── Accueil, de haut en bas
        capture("A1-accueil-haut", attente: 6)
        for rang in 1...5 {
            app.swipeUp()
            capture("A\(rang + 1)-accueil", attente: 1.2)
        }
        noter("Accueil : \(app.buttons.count) éléments touchables recensés en bas de page")

        // ── Ce soir
        onglet("Ce soir")
        capture("B1-ce-soir", attente: 4)
        app.swipeUp(); capture("B2-ce-soir", attente: 1.2)
        app.swipeUp(); capture("B3-ce-soir", attente: 1.2)

        // ── Mes listes et chacun de ses rayons
        onglet("Mes listes")
        capture("C0-listes", attente: 3)
        for rayon in ["À voir", "En cours", "À venir"] {
            let case_ = app.buttons[rayon].firstMatch
            if case_.waitForExistence(timeout: 4) {
                case_.tap()
                capture("C-\(rayon)", attente: 2.5)
            } else {
                noter("MANQUE · rayon « \(rayon) » dans Mes listes")
            }
        }

        // ── Préférences (profil, goûts, statistiques)
        app.ouvrirPreferences()
        capture("D1-preferences", attente: 3)
        app.swipeUp(); capture("D2-preferences", attente: 1.2)
        app.swipeUp(); capture("D3-preferences", attente: 1.2)

        // ── Explorer et ses sources
        onglet("Explorer")
        capture("E1-explorer", attente: 4)
        for source in ["NAS", "TV"] {
            let bouton = app.buttons[source].firstMatch
            if bouton.waitForExistence(timeout: 4) {
                bouton.tap()
                capture("E-\(source)", attente: 3)
            } else {
                noter("MANQUE · source « \(source) » dans Explorer")
            }
        }

        // ── Une fiche de film, depuis Mes listes
        onglet("Mes listes")
        let premiere = app.buttons.matching(NSPredicate(format: "label CONTAINS 'film' OR label CONTAINS 'série'")).firstMatch
        if premiere.waitForExistence(timeout: 8), app.amener(premiere, essais: 4) {
            premiere.tap()
            capture("F1-fiche", attente: 5)
            app.swipeUp(); capture("F2-fiche", attente: 1.2)
            app.swipeUp(); capture("F3-fiche", attente: 1.2)
            revenir()
        } else {
            noter("MANQUE · aucune carte à ouvrir dans Mes listes")
        }

        deposerLeReleve()
    }
}
