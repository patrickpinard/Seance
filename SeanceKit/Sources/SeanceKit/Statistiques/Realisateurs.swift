import Foundation

/// « Tes réalisateurs » (8.2.11) : les réalisateurs des films que tu as vus, lus une fois sur TMDB puis gardés sur
/// l'appareil (le suivi d'un titre ne garde que ses acteurs principaux).
public struct ReserveRealisateurs: Codable, Sendable, Equatable {
    public struct Realisateur: Codable, Sendable, Hashable {
        public let id: Int
        public let nom: String
        public let cheminPortrait: String?

        public init(id: Int, nom: String, cheminPortrait: String?) {
            self.id = id
            self.nom = nom
            self.cheminPortrait = cheminPortrait
        }
    }

    /// Un réalisateur et les films de lui que tu as vus.
    public struct Classe: Sendable, Hashable {
        public let realisateur: Realisateur
        public let films: [Int]
    }

    /// Par film vu (identifiant TMDB) : ses réalisateurs ; une liste vide si TMDB n'en donne pas.
    public var parFilm: [Int: [Realisateur]] = [:]

    public init() {}

    public static let cle = "profil.realisateurs"

    public init(donnees: Data?) {
        self = donnees.flatMap { try? JSONDecoder().decode(ReserveRealisateurs.self, from: $0) } ?? ReserveRealisateurs()
    }

    public func encoder() -> Data? { try? JSONEncoder().encode(self) }

    /// Les films vus dont on ne connaît pas encore le réalisateur.
    public func manquants(_ films: [Int]) -> [Int] {
        films.filter { parFilm[$0] == nil }
    }

    /// Ceux dont tu as vu au moins `minimum` films, les plus vus d'abord (puis par nom).
    public func classement(filmsVus: Set<Int>, minimum: Int = 2, limite: Int = 12) -> [Classe] {
        var films: [Int: [Int]] = [:]
        var connus: [Int: Realisateur] = [:]
        for (film, realisateurs) in parFilm where filmsVus.contains(film) {
            for realisateur in realisateurs {
                films[realisateur.id, default: []].append(film)
                connus[realisateur.id] = realisateur
            }
        }
        return films.compactMap { id, liste in
            guard liste.count >= minimum, let realisateur = connus[id] else { return nil }
            return Classe(realisateur: realisateur, films: liste.sorted())
        }
        .sorted { $0.films.count != $1.films.count ? $0.films.count > $1.films.count : $0.realisateur.nom < $1.realisateur.nom }
        .prefix(limite)
        .map { $0 }
    }
}
