import Foundation
import SeanceKit
import SwiftUI

/// Ce qui habille la grande carte d'un titre : son image de fond et, pour un film, sa durée. Ni les soirées, ni les
/// rendez-vous, ni le NAS ne gardent l'image de fond : elle est lue une fois sur TMDB, puis gardée d'un lancement à
/// l'autre, pour que les pages s'ouvrent avec leurs images.
@MainActor
@Observable
final class EtatDecors {
    struct Decor: Codable, Equatable {
        var fond: String?
        var minutes: Int?
    }

    private(set) var decors: [String: Decor] = EtatDecors.enregistres()
    /// Les titres que TMDB n'a pas rendus : pas redemandés avant le prochain lancement.
    private var echecs: Set<String> = []
    private var enCours: Set<String> = []

    private static let cleReglage = "cesoir.decors"
    private static let plafond = 400

    func decor(_ reference: ReferenceTitre) -> Decor? {
        decors[Self.cle(reference)]
    }

    private nonisolated static func cle(_ reference: ReferenceTitre) -> String {
        "\(reference.type.rawValue)-\(reference.tmdbID)"
    }

    private static func enregistres() -> [String: Decor] {
        guard let donnees = UserDefaults.standard.data(forKey: cleReglage) else { return [:] }
        return (try? JSONDecoder().decode([String: Decor].self, from: donnees)) ?? [:]
    }

    /// Lit sur TMDB le décor des titres qui n'en ont pas encore, vingt-quatre au plus par appel.
    func charger(_ references: [ReferenceTitre], client: TMDBClient?) async {
        guard let client else { return }
        let manquantes = Array(Set(references).filter {
            let cle = Self.cle($0)
            return decors[cle] == nil && !echecs.contains(cle) && !enCours.contains(cle)
        }.prefix(24))
        guard !manquantes.isEmpty else { return }
        enCours.formUnion(manquantes.map(Self.cle))
        var nouveaux: [String: Decor] = [:]
        await withTaskGroup(of: (String, Decor?).self) { groupe in
            for reference in manquantes {
                groupe.addTask {
                    switch reference.type {
                    case .film:
                        let film = try? await client.film(reference.tmdbID, complements: [])
                        return (Self.cle(reference), film.map { Decor(fond: $0.cheminFond, minutes: $0.dureeMinutes) })
                    case .serie:
                        let serie = try? await client.serie(reference.tmdbID)
                        return (Self.cle(reference), serie.map { Decor(fond: $0.cheminFond, minutes: nil) })
                    }
                }
            }
            for await (cle, decor) in groupe {
                if let decor { nouveaux[cle] = decor } else { echecs.insert(cle) }
            }
        }
        enCours.subtract(manquantes.map(Self.cle))
        guard !nouveaux.isEmpty else { return }
        // Au-delà du plafond, on repart des seuls titres demandés : le reste se relira au besoin.
        var tous = decors.count + nouveaux.count > Self.plafond ? [:] : decors
        tous.merge(nouveaux) { _, nouveau in nouveau }
        decors = tous
        UserDefaults.standard.set(try? JSONEncoder().encode(tous), forKey: Self.cleReglage)
    }
}
