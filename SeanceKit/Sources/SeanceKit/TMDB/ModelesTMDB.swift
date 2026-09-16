import Foundation

// Réponses de l'API TMDB v3. Les clés JSON sont nommées explicitement : la stratégie
// `convertFromSnakeCase` transformerait `iso_3166_1` en `iso31661`.

/// Date calendaire au format TMDB « AAAA-MM-JJ », sans heure ni fuseau.
public struct DateTMDB: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let annee: Int
    public let mois: Int
    public let jour: Int

    public init(annee: Int, mois: Int, jour: Int) {
        self.annee = annee
        self.mois = mois
        self.jour = jour
    }

    /// `nil` pour une chaîne vide ou mal formée : TMDB renvoie `""` quand la date est inconnue.
    public init?(texte: String?) {
        guard let texte else { return nil }
        let parties = texte.split(separator: "-")
        guard parties.count == 3,
              let annee = Int(parties[0]), let mois = Int(parties[1]), let jour = Int(parties[2]),
              (1...12).contains(mois), (1...31).contains(jour)
        else { return nil }
        self.init(annee: annee, mois: mois, jour: jour)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", annee, mois, jour)
    }

    public static func < (a: DateTMDB, b: DateTMDB) -> Bool {
        (a.annee, a.mois, a.jour) < (b.annee, b.mois, b.jour)
    }
}

/// Une page de résultats (`discover`, `search`, `trending`).
public struct PageTMDB<Element: Decodable & Sendable>: Decodable, Sendable {
    public let page: Int
    public let resultats: [Element]
    public let nombrePages: Int
    public let nombreResultats: Int

    enum CodingKeys: String, CodingKey {
        case page
        case resultats = "results"
        case nombrePages = "total_pages"
        case nombreResultats = "total_results"
    }
}

public struct FilmResume: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let titre: String
    public let titreOriginal: String
    public let langueOriginale: String
    public let synopsis: String
    public let genres: [Int]
    public let cheminAffiche: String?
    public let cheminFond: String?
    public let noteMoyenne: Double
    public let nombreVotes: Int
    public let popularite: Double
    let dateSortieBrute: String?

    public var dateSortie: DateTMDB? { DateTMDB(texte: dateSortieBrute) }

    enum CodingKeys: String, CodingKey {
        case id
        case titre = "title"
        case titreOriginal = "original_title"
        case langueOriginale = "original_language"
        case synopsis = "overview"
        case genres = "genre_ids"
        case cheminAffiche = "poster_path"
        case cheminFond = "backdrop_path"
        case noteMoyenne = "vote_average"
        case nombreVotes = "vote_count"
        case popularite = "popularity"
        case dateSortieBrute = "release_date"
    }
}

public struct SerieResume: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let nom: String
    public let nomOriginal: String
    public let langueOriginale: String
    public let synopsis: String
    public let genres: [Int]
    public let paysOrigine: [String]
    public let cheminAffiche: String?
    public let cheminFond: String?
    public let noteMoyenne: Double
    public let nombreVotes: Int
    public let popularite: Double
    let premiereDiffusionBrute: String?

    public var premiereDiffusion: DateTMDB? { DateTMDB(texte: premiereDiffusionBrute) }

    enum CodingKeys: String, CodingKey {
        case id
        case nom = "name"
        case nomOriginal = "original_name"
        case langueOriginale = "original_language"
        case synopsis = "overview"
        case genres = "genre_ids"
        case paysOrigine = "origin_country"
        case cheminAffiche = "poster_path"
        case cheminFond = "backdrop_path"
        case noteMoyenne = "vote_average"
        case nombreVotes = "vote_count"
        case popularite = "popularity"
        case premiereDiffusionBrute = "first_air_date"
    }
}

// MARK: - Plateformes (données JustWatch, à citer comme source)

public struct Fournisseur: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let nom: String
    public let cheminLogo: String?
    public let priorite: Int

    enum CodingKeys: String, CodingKey {
        case id = "provider_id"
        case nom = "provider_name"
        case cheminLogo = "logo_path"
        case priorite = "display_priority"
    }
}

/// Les offres d'un titre dans un pays. Une catégorie absente de la réponse devient une liste vide.
public struct OffresRegion: Decodable, Sendable, Hashable {
    public let lien: URL?
    public let abonnement: [Fournisseur]
    public let location: [Fournisseur]
    public let achat: [Fournisseur]
    public let avecPublicite: [Fournisseur]
    public let gratuit: [Fournisseur]

    enum CodingKeys: String, CodingKey {
        case lien = "link"
        case abonnement = "flatrate"
        case location = "rent"
        case achat = "buy"
        case avecPublicite = "ads"
        case gratuit = "free"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lien = try c.decodeIfPresent(URL.self, forKey: .lien)
        abonnement = try c.decodeIfPresent([Fournisseur].self, forKey: .abonnement) ?? []
        location = try c.decodeIfPresent([Fournisseur].self, forKey: .location) ?? []
        achat = try c.decodeIfPresent([Fournisseur].self, forKey: .achat) ?? []
        avecPublicite = try c.decodeIfPresent([Fournisseur].self, forKey: .avecPublicite) ?? []
        gratuit = try c.decodeIfPresent([Fournisseur].self, forKey: .gratuit) ?? []
    }
}

public struct FournisseursParPays: Decodable, Sendable {
    /// Absent quand la réponse est ajoutée à une fiche.
    public let id: Int?
    public let pays: [String: OffresRegion]

    enum CodingKeys: String, CodingKey {
        case id
        case pays = "results"
    }

    public func offres(region: String = "CH") -> OffresRegion? {
        pays[region]
    }
}

/// Une plateforme du catalogue TMDB, proposée dans les réglages.
public struct FournisseurCatalogue: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let nom: String
    public let cheminLogo: String?
    public let priorites: [String: Int]

    enum CodingKeys: String, CodingKey {
        case id = "provider_id"
        case nom = "provider_name"
        case cheminLogo = "logo_path"
        case priorites = "display_priorities"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        nom = try c.decode(String.self, forKey: .nom)
        cheminLogo = try c.decodeIfPresent(String.self, forKey: .cheminLogo)
        priorites = try c.decodeIfPresent([String: Int].self, forKey: .priorites) ?? [:]
    }
}

struct ListeFournisseurs: Decodable, Sendable {
    let resultats: [FournisseurCatalogue]

    enum CodingKeys: String, CodingKey {
        case resultats = "results"
    }
}

// MARK: - Dates de sortie

public enum TypeSortie: Int, Sendable, Codable, CaseIterable {
    case avantPremiere = 1
    case sallesLimitees = 2
    case salles = 3
    case numerique = 4
    case physique = 5
    case television = 6
}

public struct SortieFilm: Decodable, Sendable, Hashable {
    // `certification` et `note` manquent dans certaines réponses réelles.
    public let ageLegal: String?
    public let langue: String?
    public let note: String?
    let dateBrute: String
    let typeBrut: Int

    public var type: TypeSortie? { TypeSortie(rawValue: typeBrut) }

    /// TMDB envoie `1999-11-04T00:00:00.000Z`.
    public var date: Date? {
        try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(dateBrute)
    }

    enum CodingKeys: String, CodingKey {
        case ageLegal = "certification"
        case langue = "iso_639_1"
        case note
        case dateBrute = "release_date"
        case typeBrut = "type"
    }
}

public struct DatesDeSortie: Decodable, Sendable {
    public struct Pays: Decodable, Sendable {
        public let code: String
        public let sorties: [SortieFilm]

        enum CodingKeys: String, CodingKey {
            case code = "iso_3166_1"
            case sorties = "release_dates"
        }
    }

    /// Absent quand la réponse est ajoutée à une fiche.
    public let id: Int?
    public let pays: [Pays]

    enum CodingKeys: String, CodingKey {
        case id
        case pays = "results"
    }

    public func sorties(region: String = "CH") -> [SortieFilm] {
        pays.first { $0.code == region }?.sorties ?? []
    }
}

// MARK: - Séries

public struct EpisodeTMDB: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let nom: String
    public let synopsis: String
    public let numero: Int
    public let saison: Int
    public let dureeMinutes: Int?
    public let cheminImage: String?
    public let noteMoyenne: Double?
    let dateDiffusionBrute: String?

    public var dateDiffusion: DateTMDB? { DateTMDB(texte: dateDiffusionBrute) }

    enum CodingKeys: String, CodingKey {
        case id
        case nom = "name"
        case synopsis = "overview"
        case numero = "episode_number"
        case saison = "season_number"
        case dureeMinutes = "runtime"
        case cheminImage = "still_path"
        case noteMoyenne = "vote_average"
        case dateDiffusionBrute = "air_date"
    }
}

public struct SaisonResume: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let nom: String
    public let numero: Int
    public let nombreEpisodes: Int
    public let cheminAffiche: String?
    let dateDiffusionBrute: String?

    public var dateDiffusion: DateTMDB? { DateTMDB(texte: dateDiffusionBrute) }

    enum CodingKeys: String, CodingKey {
        case id
        case nom = "name"
        case numero = "season_number"
        case nombreEpisodes = "episode_count"
        case cheminAffiche = "poster_path"
        case dateDiffusionBrute = "air_date"
    }
}

public struct SerieDetail: Decodable, Sendable, Identifiable {
    public let id: Int
    public let nom: String
    public let nomOriginal: String
    public let langueOriginale: String
    public let synopsis: String
    public let statut: String
    public let enProduction: Bool
    public let nombreSaisons: Int
    public let nombreEpisodes: Int
    public let dureesEpisode: [Int]
    public let dernierEpisode: EpisodeTMDB?
    public let prochainEpisode: EpisodeTMDB?
    public let saisons: [SaisonResume]
    public let cheminAffiche: String?
    public let cheminFond: String?
    public let noteMoyenne: Double
    public let nombreVotes: Int
    public let genres: [Genre]
    public let casting: Casting?
    public let fournisseurs: FournisseursParPays?
    public let videos: ListeVideos?

    public var reference: ReferenceTitre { ReferenceTitre(type: .serie, tmdbID: id) }

    enum CodingKeys: String, CodingKey {
        case id
        case nom = "name"
        case nomOriginal = "original_name"
        case langueOriginale = "original_language"
        case synopsis = "overview"
        case statut = "status"
        case enProduction = "in_production"
        case nombreSaisons = "number_of_seasons"
        case nombreEpisodes = "number_of_episodes"
        case dureesEpisode = "episode_run_time"
        case dernierEpisode = "last_episode_to_air"
        case prochainEpisode = "next_episode_to_air"
        case saisons = "seasons"
        case cheminAffiche = "poster_path"
        case cheminFond = "backdrop_path"
        case noteMoyenne = "vote_average"
        case nombreVotes = "vote_count"
        case genres
        case casting = "aggregate_credits"
        case fournisseurs = "watch/providers"
        case videos
    }
}

public struct SaisonDetail: Decodable, Sendable, Identifiable {
    public let id: Int
    public let nom: String
    public let numero: Int
    public let episodes: [EpisodeTMDB]

    enum CodingKeys: String, CodingKey {
        case id
        case nom = "name"
        case numero = "season_number"
        case episodes
    }
}

// MARK: - Genres

public struct Genre: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let nom: String

    public init(id: Int, nom: String) {
        self.id = id
        self.nom = nom
    }

    enum CodingKeys: String, CodingKey {
        case id
        case nom = "name"
    }
}

struct ListeGenres: Decodable, Sendable {
    let genres: [Genre]
}
