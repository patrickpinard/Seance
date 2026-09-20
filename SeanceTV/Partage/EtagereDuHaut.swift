import Foundation

/// Ce que l'app prépare pour l'étagère du haut de l'écran d'accueil de l'Apple TV (EF-146) : ta soirée, puis les
/// nouveautés du NAS. L'extension ne connaît ni le magasin ni TMDB : elle lit ce fichier, dans l'espace partagé.
struct EtagereDuHaut: Codable {
    struct Titre: Codable {
        let titre: String
        /// Adresse complète de l'affiche.
        let affiche: String?
        /// `seance://film/603` : ouvre la fiche dans l'app.
        let lien: String
    }

    struct Section: Codable {
        let titre: String
        let titres: [Titre]
    }

    var sections: [Section]

    static let groupe = "group.ch.patrick.seance.tv"

    private static var fichier: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupe)?.appending(path: "etagere.json")
    }

    static func lire() -> EtagereDuHaut? {
        guard let fichier, let donnees = try? Data(contentsOf: fichier) else { return nil }
        return try? JSONDecoder().decode(EtagereDuHaut.self, from: donnees)
    }

    /// Rend `true` si le contenu a changé : inutile de réveiller l'étagère pour rien.
    func ecrire() -> Bool {
        guard let fichier = Self.fichier, let donnees = try? JSONEncoder().encode(self) else { return false }
        if (try? Data(contentsOf: fichier)) == donnees { return false }
        return (try? donnees.write(to: fichier, options: .atomic)) != nil
    }
}
