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
            ajouterValeur("primary_release_date.gte", sortieDepuis)
            ajouterValeur("primary_release_date.lte", sortieJusqua)
            if !typesSortie.isEmpty {
                ajouterListe("with_release_type", typesSortie.map(\.rawValue), .auMoinsUn)
                p.append(URLQueryItem(name: "region", value: region))
            }
        case .serie:
            ajouterValeur("first_air_date.gte", sortieDepuis)
            ajouterValeur("first_air_date.lte", sortieJusqua)
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
        }
    }
}
