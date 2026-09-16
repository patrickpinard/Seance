import Foundation

/// Ce que les widgets savent des séries en cours. L'app le prépare (les widgets n'ont pas la clé TMDB)
/// et l'écrit dans le conteneur partagé ; les widgets le croisent avec les épisodes cochés depuis.
public struct InstantaneWidgets: Codable, Sendable, Equatable {
    public struct Episode: Codable, Sendable, Hashable {
        public var saison: Int
        public var numero: Int
        public var titre: String?
        public var dureeMinutes: Int

        public init(saison: Int, numero: Int, titre: String?, dureeMinutes: Int) {
            self.saison = saison
            self.numero = numero
            self.titre = titre
            self.dureeMinutes = dureeMinutes
        }

        public var numeroEpisode: NumeroEpisode {
            NumeroEpisode(saison: saison, episode: numero)
        }
    }

    public struct Serie: Codable, Sendable, Hashable, Identifiable {
        public var id: Int
        public var nom: String
        public var cheminAffiche: String?
        /// Les prochains épisodes déjà diffusés, dans l'ordre.
        public var episodes: [Episode]

        public init(id: Int, nom: String, cheminAffiche: String?, episodes: [Episode]) {
            self.id = id
            self.nom = nom
            self.cheminAffiche = cheminAffiche
            self.episodes = episodes
        }

        public var reference: ReferenceTitre {
            ReferenceTitre(type: .serie, tmdbID: id)
        }
    }

    public struct Prochain: Sendable, Hashable, Identifiable {
        public var serie: Serie
        public var episode: Episode

        public var id: Int { serie.id }
    }

    public var series: [Serie]
    public var miseAJour: Date

    public init(series: [Serie], miseAJour: Date = .now) {
        self.series = series
        self.miseAJour = miseAJour
    }

    public static let nomFichier = "widgets.json"

    /// Le prochain épisode encore à voir de chaque série : les titres de la soirée d'abord, puis les
    /// séries regardées le plus récemment.
    public func prochains(vus: [Int: Set<NumeroEpisode>], derniersVisionnages: [Int: Date] = [:], soiree: Set<Int> = []) -> [Prochain] {
        series.compactMap { serie in
            let dejaVus = vus[serie.id] ?? []
            return serie.episodes.first { !dejaVus.contains($0.numeroEpisode) }.map { Prochain(serie: serie, episode: $0) }
        }
        .sorted { a, b in
            let aSoiree = soiree.contains(a.serie.id)
            let bSoiree = soiree.contains(b.serie.id)
            if aSoiree != bSoiree { return aSoiree }
            let aDate = derniersVisionnages[a.serie.id] ?? .distantPast
            let bDate = derniersVisionnages[b.serie.id] ?? .distantPast
            if aDate != bDate { return aDate > bDate }
            return a.serie.nom.localizedStandardCompare(b.serie.nom) == .orderedAscending
        }
    }

    /// Les épisodes d'une saison à partir de `depuis`, déjà diffusés, pour la liste d'une série.
    public static func episodes(
        _ saison: [EpisodeTMDB], depuis: NumeroEpisode, aujourdhui: DateTMDB, dureeParDefaut: Int, limite: Int = 8
    ) -> [Episode] {
        saison
            .filter { $0.saison > 0 && $0.numeroEpisode >= depuis }
            .filter { episode in episode.dateDiffusion.map { $0 <= aujourdhui } ?? false }
            .sorted { $0.numeroEpisode < $1.numeroEpisode }
            .prefix(limite)
            .map { Episode(saison: $0.saison, numero: $0.numero, titre: $0.nom.isEmpty ? nil : $0.nom, dureeMinutes: ($0.dureeMinutes ?? 0) > 0 ? $0.dureeMinutes! : dureeParDefaut) }
    }

    public static func lire(dossier: URL) -> InstantaneWidgets? {
        guard let donnees = try? Data(contentsOf: dossier.appending(path: nomFichier)) else { return nil }
        let decodeur = JSONDecoder()
        decodeur.dateDecodingStrategy = .iso8601
        return try? decodeur.decode(InstantaneWidgets.self, from: donnees)
    }

    public func ecrire(dossier: URL) throws {
        let encodeur = JSONEncoder()
        encodeur.dateEncodingStrategy = .iso8601
        try encodeur.encode(self).write(to: dossier.appending(path: Self.nomFichier), options: .atomic)
    }
}
