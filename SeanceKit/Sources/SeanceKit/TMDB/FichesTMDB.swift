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
    /// Poste dans l'équipe technique (« Director ») pour une réalisation.
    public let poste: String?
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
        case poste = "job"
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
        poste = try c.decodeIfPresent(String.self, forKey: .poste)
        noteMoyenne = try c.decodeIfPresent(Double.self, forKey: .noteMoyenne)
        nombreVotes = try c.decodeIfPresent(Int.self, forKey: .nombreVotes)
    }
}

public struct Filmographie: Decodable, Sendable {
    /// Rôles d'acteur, du plus récent au plus ancien (EF-31) ; une même œuvre n'apparaît qu'une fois.
    public let roles: [CreditPersonne]
    /// Films et séries réalisés, dans le même ordre.
    public let realisations: [CreditPersonne]

    enum CodingKeys: String, CodingKey {
        case roles = "cast"
        case equipe = "crew"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        roles = Self.ordonner(try c.decode([CreditPersonne].self, forKey: .roles))
        realisations = Self.ordonner((try c.decodeIfPresent([CreditPersonne].self, forKey: .equipe) ?? []).filter { $0.poste == "Director" })
    }

    private static func ordonner(_ credits: [CreditPersonne]) -> [CreditPersonne] {
        var vus = Set<ReferenceTitre>()
        return credits
            .filter { vus.insert($0.reference).inserted }
            .sorted { ($0.date ?? DateTMDB(annee: 0, mois: 1, jour: 1)) > ($1.date ?? DateTMDB(annee: 0, mois: 1, jour: 1)) }
    }
}

/// Fiche d'une personne (EF-30) : portrait, biographie, naissance.
public struct FichePersonne: Decodable, Sendable, Identifiable {
    public let id: Int
    public let nom: String
    public let biographie: String
    public let cheminPortrait: String?
    public let domaine: String?
    public let lieuNaissance: String?
    let naissanceBrute: String?
    let decesBrut: String?

    public var dateNaissance: DateTMDB? { DateTMDB(texte: naissanceBrute) }
    public var dateDeces: DateTMDB? { DateTMDB(texte: decesBrut) }

    enum CodingKeys: String, CodingKey {
        case id
        case nom = "name"
        case biographie = "biography"
        case cheminPortrait = "profile_path"
        case domaine = "known_for_department"
        case lieuNaissance = "place_of_birth"
        case naissanceBrute = "birthday"
        case decesBrut = "deathday"
    }

    /// Âge aujourd'hui, ou âge au décès.
    public func age(aujourdhui: DateTMDB) -> Int? {
        guard let naissance = dateNaissance else { return nil }
        let fin = dateDeces ?? aujourdhui
        let anniversairePasse = (fin.mois, fin.jour) >= (naissance.mois, naissance.jour)
        return fin.annee - naissance.annee - (anniversairePasse ? 0 : 1)
    }
}

/// Ce que la fiche acteur compte et filtre (EF-31 à EF-33).
public enum AnalyseFilmographie {
    public struct Filtres: Sendable, Hashable {
        public var type: TypeTitre = .film
        public var actionSeulement = false
        public var pasVus = false
        /// Seulement ce qui est regardable ce soir : NAS, abonnements ou TV.
        public var ceSoir = false

        public init() {}
    }

    public struct Compte: Sendable, Equatable {
        public let vus: Int
        public let total: Int
    }

    /// Documentaires, actualités, téléréalité et talk-shows : des apparitions, pas des rôles.
    static let genresEcartes: Set<Int> = [99, 10763, 10764, 10767]

    /// Les vrais rôles : sans apparitions dans son propre rôle ni émissions.
    public static func significatifs(_ credits: [CreditPersonne]) -> [CreditPersonne] {
        credits.filter { credit in
            guard credit.genres.allSatisfy({ !genresEcartes.contains($0) }) else { return false }
            let role = (credit.personnage ?? "").lowercased()
            let propreRole = ["self", "himself", "herself", "lui-même", "elle-même", "narrator", "voice"].contains { role.contains($0) }
            return !propreRole
        }
    }

    /// « 12 films vus sur 38 » : titres déjà sortis seulement.
    public static func compte(_ credits: [CreditPersonne], type: TypeTitre, vus: Set<ReferenceTitre>, aujourdhui: DateTMDB) -> Compte {
        let sortis = significatifs(credits).filter { $0.type == type && ($0.date.map { $0 <= aujourdhui } ?? false) }
        return Compte(vus: sortis.filter { vus.contains($0.reference) }.count, total: sortis.count)
    }

    public static func filtrer(
        _ credits: [CreditPersonne], filtres: Filtres, vus: Set<ReferenceTitre>, regardables: Set<ReferenceTitre>
    ) -> [CreditPersonne] {
        let action = filtres.type == .film ? 28 : 10759
        return significatifs(credits).filter { credit in
            guard credit.type == filtres.type else { return false }
            if filtres.actionSeulement, !credit.genres.contains(action) { return false }
            if filtres.pasVus, vus.contains(credit.reference) { return false }
            if filtres.ceSoir, !regardables.contains(credit.reference) { return false }
            return true
        }
    }
}
