import Foundation

// Fiches complètes, chargées en un seul appel grâce à `append_to_response` (ENF-03).
// Les sous-réponses ajoutées n'ont pas de champ `id`.

/// Ce qu'on ajoute à une fiche dans le même appel.
public enum ComplementFiche: Sendable, Hashable, CaseIterable {
    case casting
    case datesDeSortie
    case fournisseurs
    case videos
    /// Sous-genres d'Explorer (EF-53) vérifiés sur la fiche.
    case motsCles

    func valeurTMDB(pour type: TypeTitre) -> String? {
        switch (self, type) {
        case (.casting, .film): "credits"
        // Pour une série, le casting cumulé de toutes les saisons.
        case (.casting, .serie): "aggregate_credits"
        case (.datesDeSortie, .film): "release_dates"
        case (.datesDeSortie, .serie): nil
        case (.fournisseurs, _): "watch/providers"
        case (.videos, _): "videos"
        case (.motsCles, _): "keywords"
        }
    }
}

public struct PersonneCasting: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let nom: String
    public let personnage: String?
    public let ordre: Int?
    public let cheminPortrait: String?
    /// Séries seulement (casting cumulé).
    public let nombreEpisodes: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case nom = "name"
        case personnage = "character"
        case ordre = "order"
        case cheminPortrait = "profile_path"
        case nombreEpisodes = "total_episode_count"
    }
}

public struct MembreEquipe: Decodable, Sendable, Hashable {
    public let id: Int
    public let nom: String
    public let poste: String?

    enum CodingKeys: String, CodingKey {
        case id
        case nom = "name"
        case poste = "job"
    }
}

public struct Casting: Decodable, Sendable {
    public let acteurs: [PersonneCasting]
    public let equipe: [MembreEquipe]

    enum CodingKeys: String, CodingKey {
        case acteurs = "cast"
        case equipe = "crew"
    }

    public var realisateurs: [MembreEquipe] {
        equipe.filter { $0.poste == "Director" }
    }

    /// Les premiers rôles, dans l'ordre du générique.
    public func principaux(_ nombre: Int = 5) -> [PersonneCasting] {
        Array(acteurs.sorted { ($0.ordre ?? .max) < ($1.ordre ?? .max) }.prefix(nombre))
    }
}

/// Mots-clés d'une fiche : TMDB les range sous `keywords` pour un film, sous `results` pour une série.
public struct MotsCles: Decodable, Sendable, Hashable {
    public let ids: [Int]

    private struct MotCle: Decodable {
        let id: Int
    }

    enum CodingKeys: String, CodingKey {
        case keywords
        case results
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let liste = try c.decodeIfPresent([MotCle].self, forKey: .keywords) ?? c.decodeIfPresent([MotCle].self, forKey: .results) ?? []
        ids = liste.map(\.id)
    }
}

public struct Video: Decodable, Sendable, Hashable, Identifiable {
    public let cle: String
    public let site: String
    public let type: String
    public let nom: String
    public let officielle: Bool?
    /// « fr », « en »…
    public let langue: String?

    enum CodingKeys: String, CodingKey {
        case cle = "key"
        case site
        case type
        case nom = "name"
        case officielle = "official"
        case langue = "iso_639_1"
    }

    public var id: String { cle }

    /// Lecteur intégré de YouTube, sans cookie de suivi.
    public var urlIntegration: URL? {
        site == "YouTube" ? URL(string: "https://www.youtube-nocookie.com/embed/\(cle)?playsinline=1&autoplay=1&rel=0") : nil
    }

    public var urlVignette: URL? {
        site == "YouTube" ? URL(string: "https://img.youtube.com/vi/\(cle)/hqdefault.jpg") : nil
    }

    public var urlYouTube: URL? {
        site == "YouTube" ? URL(string: "https://www.youtube.com/watch?v=\(cle)") : nil
    }
}

public struct ListeVideos: Decodable, Sendable {
    public let resultats: [Video]

    enum CodingKeys: String, CodingKey {
        case resultats = "results"
    }

    /// Bandes-annonces et teasers YouTube (UX-09) : en français d'abord, puis les bandes-annonces
    /// avant les teasers, les officielles avant les autres.
    public var bandesAnnonces: [Video] {
        func rang(_ v: Video, _ position: Int) -> (Int, Int, Int, Int) {
            (v.langue == "fr" ? 0 : 1, v.type == "Trailer" ? 0 : 1, v.officielle == true ? 0 : 1, position)
        }
        return resultats
            .filter { ($0.type == "Trailer" || $0.type == "Teaser") && $0.site == "YouTube" }
            .enumerated()
            .sorted { rang($0.element, $0.offset) < rang($1.element, $1.offset) }
            .map(\.element)
    }
}

public struct FicheFilm: Decodable, Sendable, Identifiable {
    public let id: Int
    public let titre: String
    public let titreOriginal: String
    public let langueOriginale: String
    public let synopsis: String
    public let accroche: String?
    public let dureeMinutes: Int?
    public let genres: [Genre]
    public let statut: String?
    public let cheminAffiche: String?
    public let cheminFond: String?
    public let noteMoyenne: Double
    public let nombreVotes: Int
    public let budget: Int?
    public let recettes: Int?
    let dateSortieBrute: String?
    public let casting: Casting?
    public let datesDeSortie: DatesDeSortie?
    public let fournisseurs: FournisseursParPays?
    public let videos: ListeVideos?
    public let motsCles: MotsCles?

    public var dateSortie: DateTMDB? { DateTMDB(texte: dateSortieBrute) }
    public var reference: ReferenceTitre { ReferenceTitre(type: .film, tmdbID: id) }

    enum CodingKeys: String, CodingKey {
        case id
        case titre = "title"
        case titreOriginal = "original_title"
        case langueOriginale = "original_language"
        case synopsis = "overview"
        case accroche = "tagline"
        case dureeMinutes = "runtime"
        case genres
        case statut = "status"
        case cheminAffiche = "poster_path"
        case cheminFond = "backdrop_path"
        case noteMoyenne = "vote_average"
        case nombreVotes = "vote_count"
        case budget
        case recettes = "revenue"
        case dateSortieBrute = "release_date"
        case casting = "credits"
        case datesDeSortie = "release_dates"
        case fournisseurs = "watch/providers"
        case videos
        case motsCles = "keywords"
    }
}

// MARK: - Filmographie d'une personne

public struct CreditPersonne: Decodable, Sendable, Hashable {
    public let tmdbID: Int
    public let type: TypeTitre
    public let titre: String
    public let titreOriginal: String
    public let langueOriginale: String?
    public let genres: [Int]
    public let cheminAffiche: String?
    public let personnage: String?
    public let noteMoyenne: Double?
    public let nombreVotes: Int?
    public let date: DateTMDB?

    public var reference: ReferenceTitre { ReferenceTitre(type: type, tmdbID: tmdbID) }

    enum CodingKeys: String, CodingKey {
        case id
        case typeMedia = "media_type"
        case title
        case name
        case originalTitle = "original_title"
        case originalName = "original_name"
        case langueOriginale = "original_language"
        case genres = "genre_ids"
        case cheminAffiche = "poster_path"
        case personnage = "character"
        case noteMoyenne = "vote_average"
        case nombreVotes = "vote_count"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tmdbID = try c.decode(Int.self, forKey: .id)
        switch try c.decode(String.self, forKey: .typeMedia) {
        case "tv":
            type = .serie
            titre = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            titreOriginal = try c.decodeIfPresent(String.self, forKey: .originalName) ?? titre
            date = DateTMDB(texte: try c.decodeIfPresent(String.self, forKey: .firstAirDate))
        default:
            type = .film
            titre = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            titreOriginal = try c.decodeIfPresent(String.self, forKey: .originalTitle) ?? titre
            date = DateTMDB(texte: try c.decodeIfPresent(String.self, forKey: .releaseDate))
        }
        langueOriginale = try c.decodeIfPresent(String.self, forKey: .langueOriginale)
        genres = try c.decodeIfPresent([Int].self, forKey: .genres) ?? []
        cheminAffiche = try c.decodeIfPresent(String.self, forKey: .cheminAffiche)
        personnage = try c.decodeIfPresent(String.self, forKey: .personnage)
        noteMoyenne = try c.decodeIfPresent(Double.self, forKey: .noteMoyenne)
        nombreVotes = try c.decodeIfPresent(Int.self, forKey: .nombreVotes)
    }
}

public struct Filmographie: Decodable, Sendable {
    /// Rôles d'acteur uniquement, du plus récent au plus ancien (EF-31) ; une même œuvre n'apparaît qu'une fois.
    public let roles: [CreditPersonne]

    enum CodingKeys: String, CodingKey {
        case roles = "cast"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var vus = Set<ReferenceTitre>()
        roles = try c.decode([CreditPersonne].self, forKey: .roles)
            .filter { vus.insert($0.reference).inserted }
            .sorted { ($0.date ?? DateTMDB(annee: 0, mois: 1, jour: 1)) > ($1.date ?? DateTMDB(annee: 0, mois: 1, jour: 1)) }
    }
}
