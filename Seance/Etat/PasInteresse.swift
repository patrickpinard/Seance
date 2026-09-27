import Foundation
import SeanceKit

/// « Pas intéressé pour l'instant » (8.2.11, demande de Patrick) : un titre que Séance cesse de proposer pendant deux
/// mois — suggestions, Nouveautés, accueil, Explorer —, sans le compter comme un goût, contrairement à « Je n'aime
/// pas ». Gardé dans les réglages de l'appareil : référence → date où il peut revenir.
enum PasInteresse {
    static let cle = "suggestions.pasInteresse"
    static let duree: TimeInterval = 60 * 86_400

    private static func lire(_ brut: String) -> [String: Double] {
        (try? JSONDecoder().decode([String: Double].self, from: Data(brut.utf8))) ?? [:]
    }

    private static func cle(_ reference: ReferenceTitre) -> String { "\(reference.type.rawValue):\(reference.tmdbID)" }

    /// Les titres écartés pour l'instant, d'après la valeur brute gardée par `@AppStorage(PasInteresse.cle)`.
    static func references(_ brut: String, maintenant: Date = .now) -> Set<ReferenceTitre> {
        Set(lire(brut).compactMap { cle, jusquA -> ReferenceTitre? in
            guard jusquA > maintenant.timeIntervalSince1970 else { return nil }
            let morceaux = cle.split(separator: ":")
            guard morceaux.count == 2, let type = TypeTitre(rawValue: String(morceaux[0])), let id = Int(morceaux[1]) else { return nil }
            return ReferenceTitre(type: type, tmdbID: id)
        })
    }

    static func ecarter(_ reference: ReferenceTitre, maintenant: Date = .now) {
        var liste = lire(UserDefaults.standard.string(forKey: cle) ?? "").filter { $0.value > maintenant.timeIntervalSince1970 }
        liste[Self.cle(reference)] = maintenant.addingTimeInterval(duree).timeIntervalSince1970
        UserDefaults.standard.set(String(data: (try? JSONEncoder().encode(liste)) ?? Data(), encoding: .utf8), forKey: cle)
    }

    static func reproposer(_ reference: ReferenceTitre) {
        var liste = lire(UserDefaults.standard.string(forKey: cle) ?? "")
        liste[Self.cle(reference)] = nil
        UserDefaults.standard.set(String(data: (try? JSONEncoder().encode(liste)) ?? Data(), encoding: .utf8), forKey: cle)
    }
}
