import Foundation

/// Film ou série : TMDB range les deux dans des espaces d'identifiants distincts.
public enum TypeTitre: String, Sendable, Codable, CaseIterable {
    case film
    case serie

    /// Segment de chemin utilisé par l'API TMDB.
    var segmentTMDB: String {
        switch self {
        case .film: "movie"
        case .serie: "tv"
        }
    }
}

/// Désigne un film ou une série sans ambiguïté.
public struct ReferenceTitre: Codable, Hashable, Sendable, CustomStringConvertible {
    public var type: TypeTitre
    public var tmdbID: Int

    public init(type: TypeTitre, tmdbID: Int) {
        self.type = type
        self.tmdbID = tmdbID
    }

    public var description: String {
        "\(type.rawValue):\(tmdbID)"
    }

    /// Relit la forme « film:603 » : c'est sous ce nom que les titres voyagent vers Claude et en reviennent (EF-25).
    public init?(texte: String) {
        let parties = texte.split(separator: ":")
        guard parties.count == 2, let type = TypeTitre(rawValue: String(parties[0])), let id = Int(parties[1]) else {
            return nil
        }
        self.init(type: type, tmdbID: id)
    }
}

/// Saison et épisode, dans l'ordre de visionnage.
public struct NumeroEpisode: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public var saison: Int
    public var episode: Int

    public init(saison: Int, episode: Int) {
        self.saison = saison
        self.episode = episode
    }

    public static func < (a: NumeroEpisode, b: NumeroEpisode) -> Bool {
        (a.saison, a.episode) < (b.saison, b.episode)
    }

    /// « S02E05 »
    public var description: String {
        String(format: "S%02dE%02d", saison, episode)
    }
}

extension TimeZone {
    /// Fuseau de référence de l'app : Patrick vit en Suisse.
    public static let suisse = TimeZone(identifier: "Europe/Zurich")!
}

extension DateTMDB {
    /// Le jour calendaire d'un instant, dans un fuseau donné.
    public init(_ date: Date, fuseau: TimeZone = .suisse) {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = fuseau
        let c = calendrier.dateComponents([.year, .month, .day], from: date)
        self.init(annee: c.year!, mois: c.month!, jour: c.day!)
    }

    /// L'instant où ce jour atteint l'heure donnée, dans le fuseau donné.
    public func instant(heure: Int = 0, minute: Int = 0, fuseau: TimeZone = .suisse) -> Date {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = fuseau
        return calendrier.date(from: DateComponents(year: annee, month: mois, day: jour, hour: heure, minute: minute))!
    }
}
