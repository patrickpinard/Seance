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

    /// Les Préférences (7.0) : le portrait en haut à gauche de chaque page, qui les ouvre en feuille.
    @MainActor
    func ouvrirPreferences() {
        let portrait = buttons["preferences"].firstMatch
        _ = portrait.waitForExistence(timeout: 20)
        portrait.tap()
    }

    /// Réglages (7.0) : la roue dentée en haut à droite de chaque page ; en feuille sur l'iPhone, en onglet sur l'iPad.
    @MainActor
    func ouvrirReglages() {
        let roue = buttons["reglages"].firstMatch
        _ = roue.waitForExistence(timeout: 20)
        roue.tap()
    }

    /// Referme la feuille des Préférences ou des Réglages, en remontant d'abord les pages ouvertes dedans.
    @MainActor
    func fermerPreferences() {
        for _ in 0..<5 {
            let ok = navigationBars.buttons["OK"].firstMatch
            if ok.waitForExistence(timeout: 2) { ok.tap(); return }
            let retour = navigationBars.buttons.firstMatch
            guard retour.exists else { return }
            retour.tap()
        }
    }
}
