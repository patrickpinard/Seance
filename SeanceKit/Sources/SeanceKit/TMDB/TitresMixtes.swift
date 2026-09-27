import Foundation

/// Un film ou une série, sous une forme commune aux écrans (cartes, carrousels, grilles).
public struct TitreResume: Codable, Sendable, Hashable, Identifiable {
    public let reference: ReferenceTitre
    public let titre: String
    public let titreOriginal: String
    public let langueOriginale: String?
    public let synopsis: String
    public let genres: [Int]
    public let cheminAffiche: String?
    public let cheminFond: String?
    public let noteMoyenne: Double
    public let nombreVotes: Int
    public let date: DateTMDB?

    public var id: ReferenceTitre { reference }
}

extension FilmResume {
    public var titreResume: TitreResume {
        TitreResume(reference: ReferenceTitre(type: .film, tmdbID: id), titre: titre, titreOriginal: titreOriginal,
                    langueOriginale: langueOriginale, synopsis: synopsis, genres: genres, cheminAffiche: cheminAffiche,
                    cheminFond: cheminFond, noteMoyenne: noteMoyenne, nombreVotes: nombreVotes, date: dateSortie)
    }
}

extension SerieResume {
    public var titreResume: TitreResume {
        TitreResume(reference: ReferenceTitre(type: .serie, tmdbID: id), titre: nom, titreOriginal: nomOriginal,
                    langueOriginale: langueOriginale, synopsis: synopsis, genres: genres, cheminAffiche: cheminAffiche,
                    cheminFond: cheminFond, noteMoyenne: noteMoyenne, nombreVotes: nombreVotes, date: premiereDiffusion)
    }
}

public struct PersonneResume: Sendable, Hashable, Identifiable {
    public let id: Int
    public let nom: String
    public let cheminPortrait: String?
    public let domaine: String?
}

/// Un résultat des tendances ou de la recherche globale, où films, séries et personnes se mêlent.
public enum ElementMixte: Decodable, Sendable, Hashable {
    case titre(TitreResume)
    case personne(PersonneResume)
    case autre

    enum CodingKeys: String, CodingKey {
        case typeMedia = "media_type"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decodeIfPresent(String.self, forKey: .typeMedia) {
        case "movie": self = .titre(try FilmResume(from: decoder).titreResume)
        case "tv": self = .titre(try SerieResume(from: decoder).titreResume)
        case "person": self = .personne(try PersonneBrute(from: decoder).resume)
        default: self = .autre
        }
    }

    public var titre: TitreResume? {
        if case .titre(let t) = self { t } else { nil }
    }

    public var personne: PersonneResume? {
        if case .personne(let p) = self { p } else { nil }
    }
}

private struct PersonneBrute: Decodable, Sendable {
    let id: Int
    let name: String
    let profile_path: String?
    let known_for_department: String?

    var resume: PersonneResume {
        PersonneResume(id: id, nom: name, cheminPortrait: profile_path, domaine: known_for_department)
    }
}

public enum PeriodeTendance: String, Sendable, Hashable, CaseIterable {
    case jour = "day"
    case semaine = "week"
}

extension TMDBClient {
    /// Carrousel « Tendances » et sa bascule Aujourd'hui / Cette semaine (UX-02).
    public func tendances(_ periode: PeriodeTendance, page: Int = 1) async throws -> [TitreResume] {
        let reponse: PageTMDB<ElementMixte> = try await envoyerPublic(
            "/3/trending/all/\(periode.rawValue)", page == 1 ? [] : [URLQueryItem(name: "page", value: String(page))]
        )
        return reponse.resultats.compactMap(\.titre)
    }

    /// Recherche de personnes seules : la portée « Acteurs » d'Explorer, triée par popularité par TMDB.
    public func rechercherPersonnes(_ texte: String, page: Int = 1) async throws -> [PersonneResume] {
        let resultat: PageTMDB<PersonneBrute> = try await envoyerPublic("/3/search/person", [
            URLQueryItem(name: "query", value: texte),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "page", value: String(page)),
        ])
        return resultat.resultats.map(\.resume)
    }

    /// Recherche de films, séries et personnes à la fois (EF-05).
    public func rechercherTout(_ texte: String, page: Int = 1) async throws -> [ElementMixte] {
        let resultat: PageTMDB<ElementMixte> = try await envoyerPublic("/3/search/multi", [
            URLQueryItem(name: "query", value: texte),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "page", value: String(page)),
        ])
        return resultat.resultats.filter { $0 != .autre }
    }
}

public extension TitreResume {
    /// Un titre connu seulement par sa référence, son nom et son affiche (8.2.15) : pour le menu d'une carte de Mes
    /// listes ou du NAS, qui n'a pas de fiche TMDB sous la main.
    init(reference: ReferenceTitre, titre: String, cheminAffiche: String?, cheminFond: String? = nil, genres: [Int] = [],
         date: DateTMDB? = nil) {
        self.init(reference: reference, titre: titre, titreOriginal: titre, langueOriginale: nil, synopsis: "", genres: genres,
                  cheminAffiche: cheminAffiche, cheminFond: cheminFond, noteMoyenne: 0, nombreVotes: 0, date: date)
    }
}

extension Sequence {
    /// Les plus récents d'abord (8.2.19) : 2026, puis 2025… d'après la date de sortie ou de première diffusion ; à date
    /// égale, l'ordre d'origine (la popularité) reste ; les titres sans date passent à la fin.
    public func recentsDAbord(_ date: (Element) -> DateTMDB?) -> [Element] {
        enumerated()
            .sorted { a, b in
                switch (date(a.element), date(b.element)) {
                case let (x?, y?) where x != y: x > y
                case (_?, nil): true
                case (nil, _?): false
                default: a.offset < b.offset
                }
            }
            .map(\.element)
    }
}
