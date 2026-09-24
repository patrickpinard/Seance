import Foundation

/// La réponse de Siri à « Qu'est-ce que je regarde ce soir ? » : une phrase à dire à voix haute,
/// donc sans « S02E06 » ni liste interminable.
public enum PhraseSoiree {
    public struct Titre: Sendable, Hashable {
        public var reference: ReferenceTitre
        public var nom: String

        public init(reference: ReferenceTitre, nom: String) {
            self.reference = reference
            self.nom = nom
        }
    }

    public static func texte(soiree: [Titre], prochains: [InstantaneWidgets.Prochain], aVoir: [String]) -> String {
        let episodes = Dictionary(prochains.map { ($0.serie.id, $0.episode) }, uniquingKeysWith: { premier, _ in premier })
        if !soiree.isEmpty {
            let noms = soiree.prefix(4).map { titre in
                guard titre.reference.type == .serie, let episode = episodes[titre.reference.tmdbID] else { return titre.nom }
                return "\(titre.nom), \(aDire(episode))"
            }
            let reste = soiree.count > 4 ? " et \(soiree.count - 4) autre\(soiree.count - 4 > 1 ? "s" : "")" : ""
            // Un point-virgule sépare les titres dès qu'un épisode ajoute sa propre virgule.
            let separateur = noms.contains { $0.contains(", ") } ? " ; " : ", "
            return "Ce soir, tu as prévu \(enumerer(noms, separateur: separateur))\(reste)."
        }
        if let premier = prochains.first {
            var phrase = "Rien de prévu ce soir. Tu pourrais continuer \(premier.serie.nom) : \(aDire(premier.episode))"
            if prochains.count > 1 {
                phrase += ", ou \(prochains[1].serie.nom)"
            }
            return phrase + "."
        }
        if !aVoir.isEmpty {
            return "Rien de prévu ce soir. Dans ta liste à voir : \(enumerer(Array(aVoir.prefix(3)), separateur: ", "))."
        }
        return "Rien de prévu ce soir. Ouvre Séance : Regarder te propose des suggestions selon tes goûts."
    }

    /// « saison 2, épisode 6 »
    static func aDire(_ episode: InstantaneWidgets.Episode) -> String {
        "saison \(episode.saison), épisode \(episode.numero)"
    }

    static func enumerer(_ elements: [String], separateur: String) -> String {
        guard elements.count > 1 else { return elements.first ?? "" }
        return elements.dropLast().joined(separator: separateur) + " et " + elements.last!
    }
}
