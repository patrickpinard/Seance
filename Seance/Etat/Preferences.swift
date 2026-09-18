import Foundation

/// Ton prénom, saisi dans Réglages : Séance te parle plus familièrement quand elle propose quelque chose.
/// Vide, les phrases restent neutres.
enum Prenom {
    static let cle = "profil.prenom"

    /// Le prénom nettoyé, ou `nil` s'il n'est pas renseigné.
    static func lire(_ brut: String = UserDefaults.standard.string(forKey: cle) ?? "") -> String? {
        let propre = brut.trimmingCharacters(in: .whitespacesAndNewlines)
        return propre.isEmpty ? nil : String(propre.prefix(30))
    }

    /// « Bonsoir Patrick » le soir et la nuit, « Bonjour Patrick » le jour ; sans prénom, « Bonsoir » tout court.
    static func salut(_ prenom: String?, maintenant: Date = .now, calendrier: Calendar = .current) -> String {
        let heure = calendrier.component(.hour, from: maintenant)
        let mot = (5..<18).contains(heure) ? "Bonjour" : "Bonsoir"
        return prenom.map { "\(mot) \($0)" } ?? mot
    }

    /// Ajoute « , Patrick » à la fin d'une phrase courte : « Rien de prévu ce soir, Patrick ».
    static func interpeller(_ phrase: String, _ prenom: String?) -> String {
        prenom.map { "\(phrase), \($0)" } ?? phrase
    }
}

/// Combien d'idées « Idées pour ce soir » montre à la fois.
enum NombreIdees {
    static let cle = "cesoir.nombreIdees"
    static let choix = [3, 5, 10]
    static let parDefaut = 5

    static func lire(_ brut: Int) -> Int {
        choix.contains(brut) ? brut : parDefaut
    }

    /// Les idées classées d'avance : de quoi remplacer celles qu'on écarte, sans en demander trop à Claude.
    static var aClasser: Int {
        max(12, lire(UserDefaults.standard.integer(forKey: cle)) + 7)
    }
}
