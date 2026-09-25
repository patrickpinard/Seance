import XCTest

/// Le théâtre des tests d'interface : données de démonstration en mémoire et faux TMDB, qui répond avec les réponses
/// enregistrées de SeanceKit lues sur le disque du Mac. Sans clé ni compte : l'Accueil, Ce soir, Explorer et les
/// fiches s'affichent donc dans le simulateur, toujours pareils.
enum Lancement {
    /// `SeanceKit/Tests/SeanceKitTests/Fixtures`, retrouvé depuis ce fichier.
    static var reponsesTMDB: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SeanceKit/Tests/SeanceKitTests/Fixtures").path
    }

    @MainActor
    static func demonstration(_ app: XCUIApplication) {
        app.launchEnvironment["SEANCE_DEMO"] = "1"
        app.launchEnvironment["SEANCE_FAUX_TMDB"] = reponsesTMDB
    }
}

extension XCUIApplication {
    /// Amène un élément à portée de doigt par petits glissements. Un `swipeUp` fait défiler une page entière : dans une
    /// grille paresseuse, la cellule cherchée sort par le haut et disparaît de l'arbre d'accessibilité.
    @MainActor
    @discardableResult
    func amener(_ element: XCUIElement, versLeHaut: Bool = false, essais: Int = 16) -> Bool {
        func glisser(de depart: CGFloat, a arrivee: CGFloat) {
            let haut = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: depart))
            haut.press(forDuration: 0.05, thenDragTo: coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: arrivee)))
        }
        // Dans un sens d'abord (vers le bas, sauf demande contraire), puis dans l'autre, au-delà du point de départ.
        for essai in 0..<(essais * 3) {
            if element.exists, element.isHittable { return true }
            if (essai < essais) != versLeHaut { glisser(de: 0.65, a: 0.35) } else { glisser(de: 0.35, a: 0.65) }
        }
        return element.exists && element.isHittable
    }

    /// Vrai sur l'iPad (et le Mac) : Préférences et Réglages y sont des onglets du menu (8.0).
    @MainActor
    var ongletsPreferences: Bool {
        // Sur l'iPhone, la roue est là ; sur l'iPad, pas de roue, mais un onglet « Réglages » dans le menu du haut.
        if buttons["reglages"].firstMatch.waitForExistence(timeout: 8) { return false }
        return buttons["Réglages"].firstMatch.exists
    }

    /// Les Préférences : le portrait en haut à gauche sur l'iPhone, qui les ouvre en feuille ; un onglet sur l'iPad.
    @MainActor
    func ouvrirPreferences() {
        if ongletsPreferences { return onglet("Préférences") }
        let portrait = buttons["preferences"].firstMatch
        _ = portrait.waitForExistence(timeout: 20)
        portrait.tap()
    }

    /// Réglages : la roue dentée en haut à droite sur l'iPhone, en feuille ; un onglet sur l'iPad.
    @MainActor
    func ouvrirReglages() {
        if ongletsPreferences { return onglet("Réglages") }
        let roue = buttons["reglages"].firstMatch
        _ = roue.waitForExistence(timeout: 20)
        roue.tap()
    }

    /// Une page de l'app par son nom d'avant la 8.0 : Ce soir et les sources ouvrent Regarder sur leur pastille, Explorer
    /// la recherche, Préférences et Réglages leur feuille. Les onglets sont en bas sur l'iPhone, en haut sur l'iPad.
    @MainActor
    func aller(_ page: String) {
        switch page {
        case "Ce soir":
            onglet("Regarder")
            pastille("Tout")
            let aujourdhui = buttons.matching(NSPredicate(format: "label BEGINSWITH 'Aujourd'")).firstMatch
            if aujourdhui.waitForExistence(timeout: 3) { aujourdhui.tap() }
        case "Streaming", "TV", "NAS", "Regarder › Tout":
            onglet("Regarder")
            pastille(page == "Regarder › Tout" ? "Tout" : page)
        case "Explorer", "Recherche":
            onglet("Recherche")
        case "Préférences", "Profil":
            ouvrirPreferences()
        case "Réglages":
            ouvrirReglages()
        default:
            onglet(page)
        }
    }

    /// Un onglet : un bouton de la barre, ou une ligne de la barre latérale de l'iPad.
    @MainActor
    func onglet(_ nom: String) {
        let enBas = tabBars.buttons[nom].firstMatch
        if enBas.waitForExistence(timeout: 10) { enBas.tap(); return }
        let ligne = cells.matching(NSPredicate(format: "label == %@", nom)).firstMatch
        if ligne.exists { ligne.tap() } else { buttons[nom].firstMatch.tap() }
    }

    /// Une pastille de Regarder : Tout · Streaming · TV · NAS.
    @MainActor
    func pastille(_ nom: String) {
        let bouton = scrollViews.buttons[nom].firstMatch
        if bouton.waitForExistence(timeout: 8) { bouton.tap() } else { buttons[nom].firstMatch.tap() }
    }

    /// Referme la feuille des Préférences ou des Réglages, en remontant d'abord les pages ouvertes dedans.
    @MainActor
    func fermerPreferences() {
        // Sur l'iPad, ce sont des onglets : on revient à l'accueil.
        if !buttons["reglages"].firstMatch.exists, buttons["Réglages"].firstMatch.exists, !navigationBars.buttons["OK"].firstMatch.exists {
            return onglet("Accueil")
        }
        for _ in 0..<5 {
            let ok = navigationBars.buttons["OK"].firstMatch
            if ok.waitForExistence(timeout: 2) { ok.tap(); return }
            let retour = navigationBars.buttons.firstMatch
            guard retour.exists else { return }
            retour.tap()
        }
    }
}
