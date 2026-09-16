import Foundation
import SeanceKit
import SwiftData

/// « Ma soirée » : les titres retenus pour ce soir. Une soirée commence à 6 h et finit à 6 h le
/// lendemain : un titre ajouté à 1 h du matin appartient encore à la soirée de la veille.
@MainActor
public struct ServiceSoiree {
    public let contexte: ModelContext

    public init(contexte: ModelContext) {
        self.contexte = contexte
    }

    public static func soiree(_ maintenant: Date = .now) -> String {
        DateTMDB(maintenant.addingTimeInterval(-6 * 3600)).description
    }

    public func selection(maintenant: Date = .now) throws -> [SelectionSoir] {
        let soiree = Self.soiree(maintenant)
        return try contexte.fetch(FetchDescriptor<SelectionSoir>(
            predicate: #Predicate { $0.soiree == soiree }, sortBy: [SortDescriptor(\.ajouteLe)]
        ))
    }

    public func estRetenu(_ reference: ReferenceTitre, maintenant: Date = .now) throws -> Bool {
        try selection(maintenant: maintenant).contains { $0.reference == reference }
    }

    /// Ajoute le titre à la soirée, sans doublon ; les soirées passées sont effacées au passage.
    public func retenir(_ reference: ReferenceTitre, titre: String, cheminAffiche: String?, maintenant: Date = .now) throws {
        let soiree = Self.soiree(maintenant)
        try contexte.delete(model: SelectionSoir.self, where: #Predicate { $0.soiree != soiree })
        guard try !estRetenu(reference, maintenant: maintenant) else { return }
        contexte.insert(SelectionSoir(reference: reference, titre: titre, cheminAffiche: cheminAffiche, soiree: soiree))
        try contexte.save()
    }

    public func retirer(_ reference: ReferenceTitre, maintenant: Date = .now) throws {
        for selection in try selection(maintenant: maintenant) where selection.reference == reference {
            contexte.delete(selection)
        }
        try contexte.save()
    }

    /// Le prochain épisode de chaque série de la liste préparée pour les widgets, d'après les épisodes
    /// cochés depuis : les séries de la soirée d'abord, puis les plus récemment regardées.
    public func prochainsEpisodes(_ instantane: InstantaneWidgets?, maintenant: Date = .now) throws -> [InstantaneWidgets.Prochain] {
        guard let instantane else { return [] }
        let suivi = ServiceSuivi(contexte: contexte)
        var vus: [Int: Set<NumeroEpisode>] = [:]
        var derniers: [Int: Date] = [:]
        for serie in instantane.series {
            let visionnages = try suivi.visionnages(serie.reference)
            vus[serie.id] = Set(visionnages.compactMap { v in
                guard let saison = v.saison, let episode = v.episode else { return nil }
                return NumeroEpisode(saison: saison, episode: episode)
            })
            derniers[serie.id] = visionnages.last?.vuLe
        }
        let soiree = Set(try selection(maintenant: maintenant).filter { $0.reference.type == .serie }.map(\.tmdbID))
        return instantane.prochains(vus: vus, derniersVisionnages: derniers, soiree: soiree)
    }

    /// La réponse à « Qu'est-ce que je regarde ce soir ? ».
    public func phrase(_ instantane: InstantaneWidgets?, maintenant: Date = .now) throws -> String {
        let soiree = try selection(maintenant: maintenant).map { PhraseSoiree.Titre(reference: $0.reference, nom: $0.titre) }
        let aVoir = StatutSuivi.aVoir.rawValue
        let liste = try contexte.fetch(FetchDescriptor<Suivi>(
            predicate: #Predicate { $0.statutBrut == aVoir }, sortBy: [SortDescriptor(\.ajouteLe, order: .reverse)]
        ))
        return PhraseSoiree.texte(soiree: soiree, prochains: try prochainsEpisodes(instantane, maintenant: maintenant), aVoir: liste.map(\.titre))
    }
}
