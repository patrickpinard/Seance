import Foundation

/// Les critères d'Explorer que TMDB sait appliquer lui-même (EF-53).
/// Les autres (télé, NAS, déjà vu, acteur pour une série) sont filtrés par l'app (EF-59).
public struct CriteresDecouverte: Sendable, Hashable, Codable {
    public enum Combinaison: String, Sendable, Hashable, Codable {
        /// Tous les éléments doivent correspondre : TMDB les sépare par une virgule.
        case tous
        /// Au moins un élément doit correspondre : TMDB les sépare par une barre verticale.
        case auMoinsUn

        var separateur: String {
            switch self {
            case .tous: ","
            case .auMoinsUn: "|"
            }
        }
    }

    public enum Monetisation: String, Sendable, Hashable, Codable, CaseIterable {
        case abonnement = "flatrate"
        case gratuit = "free"
        case avecPublicite = "ads"
        case location = "rent"
        case achat = "buy"
    }

    public enum Tri: String, Sendable, Hashable, Codable, CaseIterable {
        case popularite
        case note
        case date
        case titre
        /// Les plus votés : les titres que tout le monde connaît.
        case votes
    }

    public var genresInclus: [Int] = []
    public var combinaisonGenres: Combinaison = .auMoinsUn
    public var genresExclus: [Int] = []
    public var acteurs: [Int] = []
    public var realisateurs: [Int] = []
    public var combinaisonPersonnes: Combinaison = .tous
    public var motsCles: [Int] = []
    public var motsClesExclus: [Int] = []
    public var sortieDepuis: DateTMDB?
    public var sortieJusqua: DateTMDB?
    /// Séries seulement : un épisode diffusé dans cet intervalle (`air_date`).
    public var episodesDepuis: DateTMDB?
    public var episodesJusqua: DateTMDB?
    public var typesSortie: [TypeSortie] = []
    public var noteMin: Double?
    public var noteMax: Double?
    public var votesMin: Int?
    public var dureeMin: Int?
    public var dureeMax: Int?
    public var langueOriginale: String?
    public var paysOrigine: String?
    public var fournisseurs: [Int] = []
    public var monetisations: [Monetisation] = []
    public var region = "CH"
    public var tri: Tri = .popularite
    public var decroissant = true
    public var page = 1

    public init() {}

    /// Paramètres de `discover/movie` ou `discover/tv`. Les noms diffèrent entre films et séries
    /// pour les dates et le tri ; les personnes et les types de sortie n'existent que pour les films.
    func parametres(pour type: TypeTitre) -> [URLQueryItem] {
        var p: [URLQueryItem] = [
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "sort_by", value: "\(champTri(pour: type)).\(decroissant ? "desc" : "asc")"),
        ]
        func ajouterListe(_ nom: String, _ valeurs: [Int], _ combinaison: Combinaison) {
            guard !valeurs.isEmpty else { return }
            p.append(URLQueryItem(name: nom, value: valeurs.map(String.init).joined(separator: combinaison.separateur)))
        }
        func ajouterValeur<V: CustomStringConvertible>(_ nom: String, _ valeur: V?) {
            guard let valeur else { return }
            p.append(URLQueryItem(name: nom, value: valeur.description))
        }

        ajouterListe("with_genres", genresInclus, combinaisonGenres)
        ajouterListe("without_genres", genresExclus, .auMoinsUn)
        ajouterListe("with_keywords", motsCles, .auMoinsUn)
        ajouterListe("without_keywords", motsClesExclus, .auMoinsUn)
        ajouterValeur("vote_average.gte", noteMin)
        ajouterValeur("vote_average.lte", noteMax)
        ajouterValeur("vote_count.gte", votesMin)
        ajouterValeur("with_runtime.gte", dureeMin)
        ajouterValeur("with_runtime.lte", dureeMax)
        ajouterValeur("with_original_language", langueOriginale)
        ajouterValeur("with_origin_country", paysOrigine)

        switch type {
        case .film:
            ajouterListe("with_cast", acteurs, combinaisonPersonnes)
            ajouterListe("with_crew", realisateurs, combinaisonPersonnes)
            if typesSortie.isEmpty {
                ajouterValeur("primary_release_date.gte", sortieDepuis)
                ajouterValeur("primary_release_date.lte", sortieJusqua)
            } else {
                // TMDB n'applique le type de sortie qu'avec les dates de sortie de la région :
                // sans `release_date`, le filtre est ignoré (vérifié le 16 septembre 2026).
                ajouterListe("with_release_type", typesSortie.map(\.rawValue), .auMoinsUn)
                p.append(URLQueryItem(name: "region", value: region))
                ajouterValeur("release_date.gte", sortieDepuis)
                ajouterValeur("release_date.lte", sortieJusqua ?? DateTMDB(annee: 2100, mois: 12, jour: 31))
            }
        case .serie:
            ajouterValeur("first_air_date.gte", sortieDepuis)
            ajouterValeur("first_air_date.lte", sortieJusqua)
            ajouterValeur("air_date.gte", episodesDepuis)
            ajouterValeur("air_date.lte", episodesJusqua)
        }

        if !fournisseurs.isEmpty || !monetisations.isEmpty {
            p.append(URLQueryItem(name: "watch_region", value: region))
            ajouterListe("with_watch_providers", fournisseurs, .auMoinsUn)
            if !monetisations.isEmpty {
                p.append(URLQueryItem(name: "with_watch_monetization_types",
                                      value: monetisations.map(\.rawValue).joined(separator: "|")))
            }
        }
        return p
    }

    private func champTri(pour type: TypeTitre) -> String {
        switch (tri, type) {
        case (.popularite, _): "popularity"
        case (.note, _): "vote_average"
        case (.date, .film): "primary_release_date"
        case (.date, .serie): "first_air_date"
        case (.titre, .film): "title"
        case (.titre, .serie): "name"
        case (.votes, _): "vote_count"
        }
    }
}

extension CriteresDecouverte {
    /// Genres de télé sans intérêt pour des nouveautés : actualités, téléréalité, feuilletons, talk-shows.
    static let genresTeleEcartes = [10763, 10764, 10766, 10767]

    /// Top 10 de l'accueil, cinq films et cinq séries : les mieux notés sur TMDB parmi les films sortis dans
    /// l'année et les séries avec un épisode diffusé dans l'année. Assez de votes pour que la note compte ;
    /// ni documentaires ni téléfilms, ni actualités, téléréalité, feuilletons ou talk-shows.
    public static func top(_ type: TypeTitre, maintenant: Date = .now) -> CriteresDecouverte {
        var criteres = CriteresDecouverte()
        let aujourdhui = DateTMDB(maintenant)
        let ilYAUnAn = DateTMDB(maintenant.addingTimeInterval(-365 * 86_400))
        criteres.tri = .note
        switch type {
        case .film:
            criteres.sortieDepuis = ilYAUnAn
            criteres.sortieJusqua = aujourdhui
            criteres.votesMin = 300
            criteres.genresExclus = [99, 10770]
        case .serie:
            criteres.episodesDepuis = ilYAUnAn
            criteres.episodesJusqua = aujourdhui
            criteres.votesMin = 150
            criteres.genresExclus = [99] + genresTeleEcartes
        }
        return criteres
    }

    /// « Du moment » sur l'accueil (EF-01) : films sortis et séries avec un épisode diffusé depuis trente jours,
    /// les plus populaires d'abord, c'est-à-dire ceux dont on parle. Remplace tendances et nouveautés.
    public static func duMoment(_ type: TypeTitre, maintenant: Date = .now) -> CriteresDecouverte {
        var criteres = CriteresDecouverte()
        let (debut, aujourdhui) = bornesDuMoment(maintenant: maintenant)
        criteres.tri = .popularite
        criteres.votesMin = 10
        switch type {
        case .film:
            criteres.sortieDepuis = debut
            criteres.sortieJusqua = aujourdhui
        case .serie:
            criteres.episodesDepuis = debut
            criteres.episodesJusqua = aujourdhui
            criteres.genresExclus = genresTeleEcartes
        }
        return criteres
    }

    /// Les trente derniers jours, aujourd'hui compris, à l'heure suisse.
    public static func bornesDuMoment(maintenant: Date = .now) -> (debut: DateTMDB, fin: DateTMDB) {
        (DateTMDB(maintenant.addingTimeInterval(-29 * 86_400)), DateTMDB(maintenant))
    }
}

extension SerieDetail {
    /// L'épisode qui fait d'une série une nouveauté de la période : le dernier diffusé, sinon le
    /// prochain s'il tombe dans l'intervalle (TMDB met parfois à jour avec retard).
    public func episodeNouveau(depuis debut: DateTMDB, jusqua fin: DateTMDB) -> EpisodeTMDB? {
        [dernierEpisode, prochainEpisode]
            .compactMap { $0 }
            .first { episode in
                guard let date = episode.dateDiffusion else { return false }
                return date >= debut && date <= fin
            }
    }

    /// Vrai quand la série elle-même commence dans la période.
    public func commence(depuis debut: DateTMDB, jusqua fin: DateTMDB) -> Bool {
        guard let premiereDiffusion else { return false }
        return premiereDiffusion >= debut && premiereDiffusion <= fin
    }
}
