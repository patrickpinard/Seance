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
