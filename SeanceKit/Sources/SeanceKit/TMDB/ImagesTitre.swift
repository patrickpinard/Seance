import Foundation

/// Toutes les images d'un titre sur TMDB (8.7) : fonds, affiches et logos, avec leur langue et leurs votes. La tête de
/// l'accueil y choisit une image qui représente vraiment le titre — l'image de fond des listes est souvent une scène
/// quelconque, parfois barrée de texte.
public struct ImagesTitre: Decodable, Sendable, Hashable {
    public struct Image: Decodable, Sendable, Hashable {
        public let chemin: String
        /// `nil` : l'image ne porte aucun texte.
        public let langue: String?
        public let largeur: Int
        public let hauteur: Int
        public let moyenne: Double
        public let votes: Int

        enum CodingKeys: String, CodingKey {
            case chemin = "file_path", langue = "iso_639_1", largeur = "width", hauteur = "height"
            case moyenne = "vote_average", votes = "vote_count"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            chemin = try c.decode(String.self, forKey: .chemin)
            langue = try c.decodeIfPresent(String.self, forKey: .langue)
            largeur = try c.decodeIfPresent(Int.self, forKey: .largeur) ?? 0
            hauteur = try c.decodeIfPresent(Int.self, forKey: .hauteur) ?? 0
            moyenne = try c.decodeIfPresent(Double.self, forKey: .moyenne) ?? 0
            votes = try c.decodeIfPresent(Int.self, forKey: .votes) ?? 0
        }
    }

    public let fonds: [Image]
    public let affiches: [Image]
    public let logos: [Image]

    enum CodingKeys: String, CodingKey {
        case fonds = "backdrops", affiches = "posters", logos
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fonds = try c.decodeIfPresent([Image].self, forKey: .fonds) ?? []
        affiches = try c.decodeIfPresent([Image].self, forKey: .affiches) ?? []
        logos = try c.decodeIfPresent([Image].self, forKey: .logos) ?? []
    }

    /// La meilleure image sans texte, assez grande pour l'écran entier : la mieux notée, puis la plus votée.
    private static func meilleure(_ images: [Image], largeurMin: Int) -> Image? {
        let propres = images.filter { $0.langue == nil }
        let grandes = propres.filter { $0.largeur >= largeurMin }
        return (grandes.isEmpty ? propres : grandes).max { ($0.moyenne, $0.votes) < ($1.moyenne, $1.votes) }
    }

    /// Un fond sans texte, pour les écrans larges (iPad, Mac, Apple TV).
    public var fondSansTexte: String? { Self.meilleure(fonds, largeurMin: 1920)?.chemin }

    /// L'affiche sans texte : l'image verticale du titre, qui remplit la page de l'iPhone.
    public var afficheSansTexte: String? { Self.meilleure(affiches, largeurMin: 1000)?.chemin }

    /// Le logo du titre — en français, sinon en anglais —, en PNG (le SVG ne s'affiche pas).
    public var logo: String? {
        let lisibles = logos.filter { $0.chemin.lowercased().hasSuffix(".png") }
        for langue in ["fr", "en"] {
            if let logo = lisibles.filter({ $0.langue == langue }).max(by: { ($0.moyenne, $0.votes) < ($1.moyenne, $1.votes) }) {
                return logo.chemin
            }
        }
        return nil
    }
}

extension TMDBClient {
    /// Les images d'un titre : sans texte, en français et en anglais.
    public func images(_ type: TypeTitre, id: Int) async throws -> ImagesTitre {
        try await envoyerPublic("/3/\(type.segmentTMDB)/\(id)/images", [URLQueryItem(name: "include_image_language", value: "fr,en,null")])
    }
}
