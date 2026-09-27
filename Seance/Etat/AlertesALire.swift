import Foundation
import SeanceDonnees

/// Les alertes reçues à lire (8.2.14, demande de Patrick) : en plus de la notification, une pastille en haut de chaque
/// page compte celles qu'on n'a pas encore vues dans Séance ; on en accuse réception une à une, ou toutes d'un coup.
/// Tout se garde dans les réglages de l'appareil, par une clé tirée de l'alerte — le magasin n'y est pas touché.
enum AlertesALire {
    static let cleLues = "alertes.lues"
    static let cleLuesAvant = "alertes.luesAvant"
    static let cleEffacees = "alertes.effacees"
    static let cleEffaceesAvant = "alertes.effaceesAvant"

    static func cle(_ alerte: AlertePlanifiee) -> String {
        "\(alerte.typeBrut)|\(alerte.tmdbID)|\(alerte.motif)|\(Int(alerte.date.timeIntervalSince1970))"
    }

    static func ensemble(_ brut: String) -> Set<String> { Set(brut.split(separator: "\n").map(String.init)) }

    /// Reçues, et pas effacées.
    static func recues(_ alertes: [AlertePlanifiee], effaceesAvant: Double, effacees: String, maintenant: Date = .now) -> [AlertePlanifiee] {
        let masquees = ensemble(effacees)
        return alertes.filter {
            $0.envoyee && $0.date <= maintenant && $0.date.timeIntervalSince1970 > effaceesAvant && !masquees.contains(cle($0))
        }
    }

    static func estLue(_ alerte: AlertePlanifiee, luesAvant: Double, lues: String) -> Bool {
        alerte.date.timeIntervalSince1970 <= luesAvant || ensemble(lues).contains(cle(alerte))
    }

    /// La valeur brute à garder après avoir ajouté `alerte` à l'ensemble.
    static func ajouter(_ alerte: AlertePlanifiee, a brut: String) -> String {
        var liste = ensemble(brut)
        liste.insert(cle(alerte))
        return liste.joined(separator: "\n")
    }
}
