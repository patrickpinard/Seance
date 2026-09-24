import Foundation

/// Ce que Séance sait d'un fichier du NAS en plus de ce que le magasin garde (6.4) : quand il est arrivé sur le NAS,
/// et les genres de son titre. Deux renseignements qui servent à ranger la bibliothèque — par ajouts, par genre.
///
/// Ils vivent dans un fichier à part, pas dans SwiftData : la bibliothèque du NAS est du cache, effacée et refaite
/// à chaque analyse, et ces deux champs auraient demandé une version de schéma pour des données qui ne survivent
/// pas à la prochaine lecture du NAS. Le fichier se range à côté des réglages partagés, avec la sauvegarde.
public struct DetailsNAS: Codable, Sendable, Equatable {
    /// Chemin du fichier sur le partage → date du fichier sur le NAS.
    public var ajouts: [String: Date]
    /// Identifiant TMDB du titre → genres TMDB.
    public var genres: [Int: [Int]]

    public init(ajouts: [String: Date] = [:], genres: [Int: [Int]] = [:]) {
        self.ajouts = ajouts
        self.genres = genres
    }

    public static let cle = "nas.details"

    public func encoder() throws -> Data {
        let encodeur = JSONEncoder()
        encodeur.dateEncodingStrategy = .iso8601
        return try encodeur.encode(self)
    }

    public static func decoder(_ donnees: Data) -> DetailsNAS? {
        let decodeur = JSONDecoder()
        decodeur.dateDecodingStrategy = .iso8601
        return try? decodeur.decode(DetailsNAS.self, from: donnees)
    }

    /// La date d'ajout d'une œuvre : celle de son fichier le plus récent — une série arrivée par épisodes compte
    /// par le dernier reçu.
    public func ajout(_ chemins: [String]) -> Date? {
        chemins.compactMap { ajouts[$0] }.max()
    }
}
