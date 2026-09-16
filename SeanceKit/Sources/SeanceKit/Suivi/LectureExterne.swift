import Foundation

/// Une vidéo du NAS confiée à une app de lecture (Infuse, VLC, lecteur du Mac). Au retour dans
/// Séance, l'app propose de la marquer comme vue plutôt que de laisser cocher à la main.
public struct LectureExterne: Codable, Sendable, Hashable, Identifiable {
    public var reference: ReferenceTitre
    public var titre: String
    public var episode: NumeroEpisode?
    public var debut: Date

    public var id: String { "\(reference)|\(episode?.description ?? "")|\(Int(debut.timeIntervalSince1970))" }

    public init(reference: ReferenceTitre, titre: String, episode: NumeroEpisode?, debut: Date) {
        self.reference = reference
        self.titre = titre
        self.episode = episode
        self.debut = debut
    }

    public enum Decision: Sendable, Equatable {
        /// Retour trop rapide : sans doute un essai, la question attendra le prochain retour.
        case attendre
        case demander
        /// Trop ancienne pour être encore d'actualité.
        case oublier
    }

    public static let dureeMinimale: TimeInterval = 10 * 60
    public static let dureeMaximale: TimeInterval = 12 * 3600

    public func decision(maintenant: Date) -> Decision {
        let ecoule = maintenant.timeIntervalSince(debut)
        if ecoule > Self.dureeMaximale { return .oublier }
        return ecoule >= Self.dureeMinimale ? .demander : .attendre
    }

    /// « Heat » ou « Reacher S01E03 ».
    public var libelle: String {
        episode.map { "\(titre) \($0)" } ?? titre
    }
}
