import Foundation

/// Ce que Séance comprend d'une envie écrite, sans Claude : « un film de guerre »,
/// « une série policière courte », « de l'action mais sans horreur » (EF-22, EF-23).
public struct EnvieInterpretee: Sendable, Hashable {
    public var genresFilms: [Int] = []
    public var genresSeries: [Int] = []
    public var genresExclusFilms: [Int] = []
    public var genresExclusSeries: [Int] = []
    public var type: TypeTitre?
    public var dureeMaxMinutes: Int?

    public init() {}

    public var aDesGenres: Bool {
        !genresFilms.isEmpty || !genresSeries.isEmpty
    }

    public func genres(pour type: TypeTitre) -> [Int] {
        type == .film ? genresFilms : genresSeries
    }

    public func genresExclus(pour type: TypeTitre) -> [Int] {
        type == .film ? genresExclusFilms : genresExclusSeries
    }
}

public enum LectureEnvie {
    /// Un genre et les mots qui l'évoquent. Les racines se comparent au début des mots, sans accents :
    /// « polici » couvre policier et policière. Les identifiants TMDB des films et des séries diffèrent.
    struct Motif {
        let racines: [String]
        let expressions: [String]
        let films: [Int]
        let series: [Int]
    }

    static let motifs: [Motif] = [
        Motif(racines: ["guerr", "militair", "soldat", "batail", "commando"], expressions: ["war"], films: [10752], series: [10768]),
        Motif(racines: ["action", "baston", "explosi"], expressions: [], films: [28], series: [10759]),
        Motif(racines: ["aventur"], expressions: [], films: [12], series: [10759]),
        Motif(racines: ["polici", "polar", "crimin", "enquet", "detectiv", "flic", "mafia", "gangster", "braquag"],
              expressions: ["crime"], films: [80], series: [80]),
        Motif(racines: ["thrill", "suspens", "haletant"], expressions: [], films: [53], series: [9648]),
        Motif(racines: ["futurist", "extraterrestr", "spatial"], expressions: ["sf", "science fiction", "sci fi"], films: [878], series: [10765]),
        Motif(racines: ["fantastiq", "fantasy", "magie", "sorcier"], expressions: [], films: [14], series: [10765]),
        Motif(racines: ["horreur", "epouvant", "flippant", "zombie"], expressions: [], films: [27], series: []),
        Motif(racines: ["comedi", "drole", "humour", "marrant", "rigol"], expressions: [], films: [35], series: [35]),
        Motif(racines: ["drame", "dramatiq", "emouvant"], expressions: [], films: [18], series: [18]),
        Motif(racines: ["romanc", "romantiq"], expressions: [], films: [10749], series: []),
        Motif(racines: ["western", "cowboy"], expressions: [], films: [37], series: [37]),
        Motif(racines: ["historiq"], expressions: [], films: [36], series: [10768]),
        Motif(racines: ["myster", "enigm"], expressions: [], films: [9648], series: [9648]),
        Motif(racines: ["animation"], expressions: ["dessin anime"], films: [16], series: [16]),
        Motif(racines: ["documentair"], expressions: ["docu"], films: [99], series: [99]),
    ]

    /// Mots qui retournent le sens du genre qui suit : « sans horreur », « pas de comédie ».
    static let negations: Set<String> = ["sans", "pas", "aucun", "aucune", "eviter", "evite", "jamais", "surtout"]

    public static func lire(_ texte: String) -> EnvieInterpretee {
        let mots = normaliser(texte)
        let phrase = " " + mots.joined(separator: " ") + " "
        var envie = EnvieInterpretee()

        for motif in motifs {
            var positions: [Int] = []
            for (i, mot) in mots.enumerated() where motif.racines.contains(where: { mot.hasPrefix($0) }) {
                positions.append(i)
            }
            for expression in motif.expressions {
                let cible = " " + expression + " "
                guard let plage = phrase.range(of: cible) else { continue }
                positions.append(phrase[..<plage.lowerBound].split(separator: " ").count)
            }
            guard let position = positions.min() else { continue }
            if estNie(mots, avant: position) {
                ajouter(motif.films, a: &envie.genresExclusFilms)
                ajouter(motif.series, a: &envie.genresExclusSeries)
            } else {
                ajouter(motif.films, a: &envie.genresFilms)
                ajouter(motif.series, a: &envie.genresSeries)
            }
        }

        let series = mots.contains { $0.hasPrefix("serie") || $0.hasPrefix("episode") }
        let films = mots.contains { $0 == "film" || $0 == "films" || $0 == "cine" || $0 == "cinema" }
        if series != films { envie.type = series ? .serie : .film }

        envie.dureeMaxMinutes = duree(dans: phrase)
        return envie
    }

    /// Un genre est nié si « sans », « pas », « aucun »… le précède d'au plus trois mots
    /// (« pas de film d'horreur »).
    static func estNie(_ mots: [String], avant position: Int) -> Bool {
        mots[max(0, position - 3)..<position].contains { negations.contains($0) }
    }

    /// « moins de 2 h », « 1h30 max », « 90 min », « court ».
    static func duree(dans phrase: String) -> Int? {
        if let m = phrase.firstMatch(of: #/\b(\d)\s*h\s*(\d{2})?\b/#), let heures = Int(m.1) {
            return heures * 60 + (m.2.flatMap { Int($0) } ?? 0)
        }
        if let m = phrase.firstMatch(of: #/\b(\d{2,3})\s*min/#), let minutes = Int(m.1) {
            return minutes
        }
        if phrase.contains(" court ") || phrase.contains(" courte ") || phrase.contains(" rapide ")
            || phrase.contains(" pas trop long") || phrase.contains(" pas long") {
            return 100
        }
        return nil
    }

    static func normaliser(_ texte: String) -> [String] {
        texte.lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "fr_FR"))
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined()
            .split(separator: " ")
            .map(String.init)
    }

    private static func ajouter(_ genres: [Int], a liste: inout [Int]) {
        for genre in genres where !liste.contains(genre) {
            liste.append(genre)
        }
    }
}

extension DemandeCeSoir {
    public var interpretation: EnvieInterpretee {
        LectureEnvie.lire(envie)
    }

    /// Le type demandé par les boutons, sinon celui que la phrase laisse entendre.
    public var typeEffectif: TypeTitre? {
        type ?? interpretation.type
    }

    public var dureeMaxEffective: Int? {
        dureeMaxMinutes ?? interpretation.dureeMaxMinutes
    }
}
