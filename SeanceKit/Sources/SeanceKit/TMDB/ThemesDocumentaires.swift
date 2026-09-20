import Foundation

/// Les thèmes de documentaires (EF-152). TMDB n'a pas de sous-genres de documentaires : un thème est donc un jeu de
/// mots-clés, cherchés par leur nom anglais la première fois puis gardés sur l'appareil. Un thème qui ne trouve aucun
/// mot-clé s'en tient au genre « Documentaire », plutôt que de ne rien montrer.
public enum ThemeDocumentaire: String, Codable, Sendable, CaseIterable, Identifiable {
    case animauxEtNature
    case sciencesEtEspace
    case histoire
    case societeEtEnquetes
    case sport
    case musique
    case voyages
    case cuisine
    case art
    case technologie

    public var id: String { rawValue }

    public var libelle: String {
        switch self {
        case .animauxEtNature: "Animaux et nature"
        case .sciencesEtEspace: "Sciences et espace"
        case .histoire: "Histoire"
        case .societeEtEnquetes: "Société et enquêtes"
        case .sport: "Sport"
        case .musique: "Musique"
        case .voyages: "Voyages"
        case .cuisine: "Cuisine"
        case .art: "Art"
        case .technologie: "Technologie"
        }
    }

    public var symbole: String {
        switch self {
        case .animauxEtNature: "leaf.fill"
        case .sciencesEtEspace: "sparkles"
        case .histoire: "building.columns.fill"
        case .societeEtEnquetes: "magnifyingglass"
        case .sport: "figure.run"
        case .musique: "music.note"
        case .voyages: "airplane"
        case .cuisine: "fork.knife"
        case .art: "paintpalette.fill"
        case .technologie: "cpu"
        }
    }

    /// Les mots-clés TMDB à chercher, en anglais : c'est la langue dans laquelle ils sont posés.
    public var termes: [String] {
        switch self {
        case .animauxEtNature: ["nature", "wildlife", "animal"]
        case .sciencesEtEspace: ["science", "space", "astronomy"]
        case .histoire: ["history", "world war ii", "ancient history"]
        case .societeEtEnquetes: ["investigation", "true crime", "politics"]
        case .sport: ["sport", "football", "athlete"]
        case .musique: ["music", "concert", "band"]
        case .voyages: ["travel", "adventure", "expedition"]
        case .cuisine: ["food", "cooking", "chef"]
        case .art: ["art", "painting", "photography"]
        case .technologie: ["technology", "computer", "artificial intelligence"]
        }
    }
}

/// Un mot-clé TMDB, tel que `/search/keyword` le rend.
public struct MotCleTMDB: Codable, Sendable, Hashable, Identifiable {
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

public extension CriteresDecouverte {
    /// Le genre « Documentaire » de TMDB, films comme séries.
    static let genreDocumentaire = 99

    /// Des documentaires disponibles sur les plateformes cochées, au besoin resserrés sur des mots-clés de thème.
    /// Sans mot-clé, ce sont tous les documentaires — c'est ce qui se passe au premier lancement, avant que les
    /// thèmes ne soient résolus.
    static func documentaires(_ type: TypeTitre, motsCles: [Int] = [], maintenant: Date = .now) -> CriteresDecouverte {
        var criteres = CriteresDecouverte()
        criteres.genresInclus = [genreDocumentaire]
        criteres.motsCles = motsCles
        criteres.tri = .popularite
        criteres.votesMin = 5
        let ilYADixAns = DateTMDB(maintenant.addingTimeInterval(-3650 * 86_400))
        switch type {
        case .film:
            criteres.sortieDepuis = ilYADixAns
        case .serie:
            criteres.episodesDepuis = ilYADixAns
        }
        return criteres
    }
}
