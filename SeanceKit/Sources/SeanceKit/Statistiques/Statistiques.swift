import Foundation

/// Un visionnage, avec ce qu'il faut savoir du titre pour les statistiques.
public struct VisionnageStat: Sendable, Hashable {
    public var reference: ReferenceTitre
    public var dureeMinutes: Int
    public var vuLe: Date
    public var genres: [Int]
    public var acteurs: [String]

    public init(reference: ReferenceTitre, dureeMinutes: Int, vuLe: Date, genres: [Int] = [], acteurs: [String] = []) {
        self.reference = reference
        self.dureeMinutes = dureeMinutes
        self.vuLe = vuLe
        self.genres = genres
        self.acteurs = acteurs
    }
}

public struct Classement<Cle: Hashable & Sendable>: Sendable, Hashable {
    public var cle: Cle
    /// Nombre de titres différents, pas de visionnages : une série compte une fois.
    public var nombreTitres: Int
}

public struct Periode: Sendable, Hashable, Comparable {
    public var annee: Int
    public var numero: Int

    public init(annee: Int, numero: Int) {
        self.annee = annee
        self.numero = numero
    }

    public static func < (a: Periode, b: Periode) -> Bool {
        (a.annee, a.numero) < (b.annee, b.numero)
    }
}

public struct RecordSoiree: Sendable, Hashable {
    public var jour: DateTMDB
    public var nombreEpisodes: Int
}

public struct BilanStatistiques: Sendable, Hashable {
    public var minutesTotales = 0
    public var minutesFilms = 0
    public var minutesSeries = 0
    public var nombreFilms = 0
    public var nombreEpisodes = 0
    public var parMois: [Periode: Int] = [:]
    /// Semaines ISO (lundi à dimanche).
    public var parSemaine: [Periode: Int] = [:]
    public var acteurs: [Classement<String>] = []
    public var genres: [Classement<Int>] = []
    /// La plus grosse soirée en épisodes (EF-36).
    public var recordEpisodes: RecordSoiree?

    public var heuresTotales: Double { Double(minutesTotales) / 60 }

    public init() {}
}

/// EF-34 à EF-36 : heures regardées, acteurs et genres favoris.
public enum Statistiques {
    public static func calculer(
        _ visionnages: [VisionnageStat],
        entre periode: ClosedRange<Date>? = nil,
        nombreActeurs: Int = 10,
        nombreGenres: Int = 5,
        fuseau: TimeZone = .suisse
    ) -> BilanStatistiques {
        var calendrier = Calendar(identifier: .iso8601)
        calendrier.timeZone = fuseau
        let retenus = visionnages.filter { periode?.contains($0.vuLe) ?? true }

        var bilan = BilanStatistiques()
        var titresParActeur: [String: Set<ReferenceTitre>] = [:]
        var titresParGenre: [Int: Set<ReferenceTitre>] = [:]
        var episodesParJour: [DateTMDB: Int] = [:]

        for v in retenus {
            bilan.minutesTotales += v.dureeMinutes
            switch v.reference.type {
            case .film:
                bilan.minutesFilms += v.dureeMinutes
                bilan.nombreFilms += 1
            case .serie:
                bilan.minutesSeries += v.dureeMinutes
                bilan.nombreEpisodes += 1
                // Une soirée va de 6 h à 6 h : un épisode vu à 1 h du matin compte pour la veille.
                episodesParJour[DateTMDB(v.vuLe.addingTimeInterval(-6 * 3600), fuseau: fuseau), default: 0] += 1
            }
            let mois = calendrier.dateComponents([.year, .month], from: v.vuLe)
            bilan.parMois[Periode(annee: mois.year!, numero: mois.month!), default: 0] += v.dureeMinutes
            let semaine = calendrier.dateComponents([.yearForWeekOfYear, .weekOfYear], from: v.vuLe)
            bilan.parSemaine[Periode(annee: semaine.yearForWeekOfYear!, numero: semaine.weekOfYear!), default: 0] += v.dureeMinutes
            for acteur in v.acteurs { titresParActeur[acteur, default: []].insert(v.reference) }
            for genre in Set(v.genres.map(genreCommun)) { titresParGenre[genre, default: []].insert(v.reference) }
        }

        bilan.acteurs = classer(titresParActeur, garder: nombreActeurs, departage: <)
        bilan.genres = classer(titresParGenre, garder: nombreGenres, departage: <)
        if let record = episodesParJour.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }) {
            bilan.recordEpisodes = RecordSoiree(jour: record.key, nombreEpisodes: record.value)
        }
        return bilan
    }

    /// Les genres propres aux séries rejoignent leur équivalent film : « Action & Adventure » compte
    /// dans « Action », « Science-Fiction & Fantastique » dans « Science-Fiction », « War & Politics » dans « Guerre ».
    public static func genreCommun(_ genre: Int) -> Int {
        switch genre {
        case 10759: 28
        case 10765: 878
        case 10768: 10752
        default: genre
        }
    }

    private static func classer<Cle: Hashable & Sendable>(
        _ titres: [Cle: Set<ReferenceTitre>], garder: Int, departage: (Cle, Cle) -> Bool
    ) -> [Classement<Cle>] {
        titres
            .map { Classement(cle: $0.key, nombreTitres: $0.value.count) }
            .sorted { $0.nombreTitres != $1.nombreTitres ? $0.nombreTitres > $1.nombreTitres : departage($0.cle, $1.cle) }
            .prefix(garder)
            .map { $0 }
    }
}
