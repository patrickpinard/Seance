import Foundation

public enum ErreurTMDB: Error, Equatable {
    /// Clé ou jeton refusé (HTTP 401).
    case identifiantsRefuses
    /// HTTP 429 encore renvoyé après toutes les tentatives.
    case limiteDepassee
    case http(code: Int, message: String?)
    case decodage(String)
}

/// Client de l'API TMDB v3 (EF-01 à EF-19). Une limite de débit (HTTP 429) entraîne une attente
/// puis un nouvel essai, sans remonter d'erreur tant qu'il reste des tentatives (ENF-05).
public actor TMDBClient {
    public enum Identifiants: Sendable {
        /// Jeton de lecture de l'API (v4), envoyé dans l'en-tête `Authorization`. Recommandé par TMDB.
        case jetonLecture(String)
        /// Clé d'API v3, envoyée en paramètre `api_key`.
        case cleAPI(String)

        /// Reconnaît le format collé par Patrick : le jeton v4 est un JWT (« eyJ… »), la clé v3 32 caractères hexadécimaux.
        public static func depuis(_ texte: String) -> Identifiants {
            let propre = texte.trimmingCharacters(in: .whitespacesAndNewlines)
            return propre.hasPrefix("eyJ") && propre.contains(".") ? .jetonLecture(propre) : .cleAPI(propre)
        }
    }

    public static let urlBase = URL(string: "https://api.themoviedb.org")!

    private let identifiants: Identifiants
    private let transport: any TransportHTTP
    private let langue: String
    private let tentativesMax: Int
    private let attendre: @Sendable (Duration) async throws -> Void

    public init(
        identifiants: Identifiants,
        transport: any TransportHTTP = URLSession.shared,
        langue: String = "fr-FR",
        tentativesMax: Int = 3,
        attendre: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.identifiants = identifiants
        self.transport = transport
        self.langue = langue
        self.tentativesMax = max(1, tentativesMax)
        self.attendre = attendre
    }

    // MARK: - Découverte et recherche

    public func decouvrirFilms(_ criteres: CriteresDecouverte) async throws -> PageTMDB<FilmResume> {
        try await envoyer("/3/discover/movie", criteres.parametres(pour: .film))
    }

    public func decouvrirSeries(_ criteres: CriteresDecouverte) async throws -> PageTMDB<SerieResume> {
        try await envoyer("/3/discover/tv", criteres.parametres(pour: .serie))
    }

    public func rechercherFilms(_ texte: String, page: Int = 1) async throws -> PageTMDB<FilmResume> {
        try await envoyer("/3/search/movie", [
            URLQueryItem(name: "query", value: texte),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "page", value: String(page)),
        ])
    }

    public func rechercherSeries(_ texte: String, page: Int = 1) async throws -> PageTMDB<SerieResume> {
        try await envoyer("/3/search/tv", [
            URLQueryItem(name: "query", value: texte),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "page", value: String(page)),
        ])
    }

    // MARK: - Fiches

    public func fournisseurs(_ type: TypeTitre, id: Int) async throws -> FournisseursParPays {
        try await envoyer("/3/\(type.segmentTMDB)/\(id)/watch/providers", [])
    }

    public func datesDeSortie(film id: Int) async throws -> DatesDeSortie {
        try await envoyer("/3/movie/\(id)/release_dates", [])
    }

    /// Fiche d'une série ; les compléments arrivent dans le même appel (ENF-03).
    public func serie(_ id: Int, complements: Set<ComplementFiche> = []) async throws -> SerieDetail {
        try await envoyer("/3/tv/\(id)", Self.parametresComplements(complements, type: .serie))
    }

    /// Fiche d'un film ; les compléments arrivent dans le même appel (ENF-03).
    public func film(_ id: Int, complements: Set<ComplementFiche> = Set(ComplementFiche.allCases)) async throws -> FicheFilm {
        try await envoyer("/3/movie/\(id)", Self.parametresComplements(complements, type: .film))
    }

    /// Rôles d'une personne, films et séries confondus (EF-30, EF-59).
    public func filmographie(personne id: Int) async throws -> Filmographie {
        try await envoyer("/3/person/\(id)/combined_credits", [])
    }

    static func parametresComplements(_ complements: Set<ComplementFiche>, type: TypeTitre) -> [URLQueryItem] {
        let valeurs = ComplementFiche.allCases.filter(complements.contains).compactMap { $0.valeurTMDB(pour: type) }
        return valeurs.isEmpty ? [] : [URLQueryItem(name: "append_to_response", value: valeurs.joined(separator: ","))]
    }

    public func saison(_ numero: Int, serie id: Int) async throws -> SaisonDetail {
        try await envoyer("/3/tv/\(id)/season/\(numero)", [])
    }

    // MARK: - Référentiels

    public func genres(_ type: TypeTitre) async throws -> [Genre] {
        let liste: ListeGenres = try await envoyer("/3/genre/\(type.segmentTMDB)/list", [])
        return liste.genres
    }

    public func catalogueFournisseurs(_ type: TypeTitre, region: String = "CH") async throws -> [FournisseurCatalogue] {
        let liste: ListeFournisseurs = try await envoyer(
            "/3/watch/providers/\(type.segmentTMDB)",
            [URLQueryItem(name: "watch_region", value: region)]
        )
        return liste.resultats
    }

    // MARK: - Transport

    func requete(_ chemin: String, _ parametres: [URLQueryItem]) -> URLRequest {
        var composants = URLComponents(url: Self.urlBase.appending(path: chemin), resolvingAgainstBaseURL: false)!
        var items = parametres + [URLQueryItem(name: "language", value: langue)]
        if case .cleAPI(let cle) = identifiants {
            items.append(URLQueryItem(name: "api_key", value: cle))
        }
        composants.queryItems = items
        var requete = URLRequest(url: composants.url!)
        requete.setValue("application/json", forHTTPHeaderField: "Accept")
        if case .jetonLecture(let jeton) = identifiants {
            requete.setValue("Bearer \(jeton)", forHTTPHeaderField: "Authorization")
        }
        return requete
    }

    func envoyerPublic<Reponse: Decodable & Sendable>(_ chemin: String, _ parametres: [URLQueryItem]) async throws -> Reponse {
        try await envoyer(chemin, parametres)
    }

    private func envoyer<Reponse: Decodable & Sendable>(
        _ chemin: String, _ parametres: [URLQueryItem]
    ) async throws -> Reponse {
        let requete = requete(chemin, parametres)
        for tentative in 1...tentativesMax {
            let (donnees, reponse) = try await transport.envoyer(requete)
            switch reponse.statusCode {
            case 200..<300:
                do {
                    return try JSONDecoder().decode(Reponse.self, from: donnees)
                } catch {
                    throw ErreurTMDB.decodage(String(describing: error))
                }
            case 401:
                throw ErreurTMDB.identifiantsRefuses
            case 429 where tentative < tentativesMax:
                let secondes = reponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init) ?? 1
                try await attendre(.seconds(max(1, secondes)))
            case 429:
                throw ErreurTMDB.limiteDepassee
            default:
                throw ErreurTMDB.http(code: reponse.statusCode, message: Self.messageErreur(donnees))
            }
        }
        throw ErreurTMDB.limiteDepassee
    }

    /// TMDB détaille ses erreurs dans `status_message`.
    private static func messageErreur(_ donnees: Data) -> String? {
        struct Corps: Decodable { let status_message: String? }
        return (try? JSONDecoder().decode(Corps.self, from: donnees))?.status_message
    }
}
