import Foundation
import SeanceKit
import SwiftUI

/// Les images choisies pour la tête de l'accueil (8.7, demande de Patrick : « des images plus représentatives du
/// film ») : parmi toutes celles du titre sur TMDB, un fond sans texte pour les écrans larges, l'affiche sans texte pour
/// la page de l'iPhone, et le logo du titre, posé à la place de son nom. Lues une fois, gardées d'un lancement à
/// l'autre. Commun à l'app et à l'Apple TV.
@MainActor
@Observable
final class VisuelsTitres {
    struct Visuel: Codable, Equatable {
        var fond: String?
        var affiche: String?
        var logo: String?
    }

    private(set) var visuels: [String: Visuel] = VisuelsTitres.enregistres()
    private var enCours: Set<String> = []

    private static let cleReglage = "accueil.visuels"
    private static let plafond = 200

    func visuel(_ reference: ReferenceTitre) -> Visuel? {
        visuels[Self.cle(reference)]
    }

    private nonisolated static func cle(_ reference: ReferenceTitre) -> String {
        "\(reference.type.rawValue)-\(reference.tmdbID)"
    }

    private static func enregistres() -> [String: Visuel] {
        guard let donnees = UserDefaults.standard.data(forKey: cleReglage) else { return [:] }
        return (try? JSONDecoder().decode([String: Visuel].self, from: donnees)) ?? [:]
    }

    /// Lit les images des titres qui n'en ont pas encore ; un titre sans réponse garde les images d'avant.
    func charger(_ references: [ReferenceTitre], client: TMDBClient?) async {
        guard let client else { return }
        let manquantes = Array(Set(references).filter { visuels[Self.cle($0)] == nil && !enCours.contains(Self.cle($0)) }.prefix(12))
        guard !manquantes.isEmpty else { return }
        enCours.formUnion(manquantes.map(Self.cle))
        var nouveaux: [String: Visuel] = [:]
        await withTaskGroup(of: (String, Visuel?).self) { groupe in
            for reference in manquantes {
                groupe.addTask {
                    let images = try? await client.images(reference.type, id: reference.tmdbID)
                    return (Self.cle(reference), images.map { Visuel(fond: $0.fondSansTexte, affiche: $0.afficheSansTexte, logo: $0.logo) })
                }
            }
            for await (cle, visuel) in groupe {
                if let visuel { nouveaux[cle] = visuel }
            }
        }
        enCours.subtract(manquantes.map(Self.cle))
        guard !nouveaux.isEmpty else { return }
        var tous = visuels.count + nouveaux.count > Self.plafond ? [:] : visuels
        tous.merge(nouveaux) { _, nouveau in nouveau }
        visuels = tous
        UserDefaults.standard.set(try? JSONEncoder().encode(tous), forKey: Self.cleReglage)
    }
}
