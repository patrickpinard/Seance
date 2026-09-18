import Foundation
import SeanceKit
import SwiftData

/// « Ma soirée » : les titres retenus pour ce soir, ou prévus pour une soirée à venir. Une soirée commence à 6 h
/// et finit à 6 h le lendemain : un titre ajouté à 1 h du matin appartient encore à la soirée de la veille.
/// Un titre n'est prévu que pour une soirée à la fois : le prévoir ailleurs le déplace.
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

    /// La soirée d'un jour choisi dans un calendrier, par exemple « 2026-09-20 ».
    public static func soiree(jour: Date, fuseau: TimeZone = .suisse) -> String {
        DateTMDB(jour, fuseau: fuseau).description
    }

    /// Le jour d'une soirée, à midi, pour l'afficher ou le proposer dans un calendrier.
    public static func jour(_ soiree: String, fuseau: TimeZone = .suisse) -> Date? {
        DateTMDB(texte: soiree)?.instant(heure: 12, fuseau: fuseau)
    }

    /// Les titres prévus pour les soirées à venir, la plus proche d'abord.
    public func aVenir(maintenant: Date = .now) throws -> [SelectionSoir] {
        let aujourdhui = Self.soiree(maintenant)
        return try contexte.fetch(FetchDescriptor<SelectionSoir>(sortBy: [SortDescriptor(\.soiree), SortDescriptor(\.ajouteLe)]))
            .filter { $0.soiree > aujourdhui }
    }

    /// Une soirée passée reste une semaine, le temps de demander « regardé ? » ; au-delà, elle s'efface.
    public static let memoireDesSoirees = 7

    private static func limiteDesSoirees(_ maintenant: Date) -> String {
        soiree(maintenant.addingTimeInterval(-Double(memoireDesSoirees) * 86_400))
    }

    /// Les soirées passées de la semaine qui n'ont pas été tranchées : « Hier soir : Heat, regardé ? ».
    /// Celles dont le titre a été vu entre-temps (film marqué vu, épisode coché ce soir-là ou après) se règlent seules.
    public func enAttente(maintenant: Date = .now) throws -> [SelectionSoir] {
        let aujourdhui = Self.soiree(maintenant)
        let limite = Self.limiteDesSoirees(maintenant)
        let suivi = ServiceSuivi(contexte: contexte)
        var restantes: [SelectionSoir] = []
        var reglees = false
        for selection in try contexte.fetch(FetchDescriptor<SelectionSoir>(sortBy: [SortDescriptor(\.soiree, order: .reverse), SortDescriptor(\.ajouteLe)]))
        where selection.soiree < aujourdhui {
            let debut = Self.jour(selection.soiree)?.addingTimeInterval(-6 * 3600) ?? .distantPast
            let vuDepuis = try suivi.visionnages(selection.reference).contains { $0.vuLe >= debut }
            if selection.soiree < limite || vuDepuis {
                contexte.delete(selection)
                reglees = true
            } else {
                restantes.append(selection)
            }
        }
        if reglees { try contexte.save() }
        return restantes
    }

    /// Ajoute le titre à la soirée de ce soir, ou à celle du jour donné ; prévu ailleurs, il est déplacé.
    /// Les soirées passées depuis plus d'une semaine sont effacées au passage, jamais celles à venir.
    public func retenir(
        _ reference: ReferenceTitre, titre: String, cheminAffiche: String?, soiree choisie: String? = nil, maintenant: Date = .now
    ) throws {
        let aujourdhui = Self.soiree(maintenant)
        let limite = Self.limiteDesSoirees(maintenant)
        let soiree = max(choisie ?? aujourdhui, aujourdhui)
        var dejaPrevu = false
        // Objet par objet : une suppression en lot ne prévient pas les listes affichées.
        for selection in try contexte.fetch(FetchDescriptor<SelectionSoir>()) {
            if selection.soiree < limite || (selection.soiree < aujourdhui && selection.reference == reference) {
                // Trop ancienne, ou le même titre reprévu : la soirée passée n'a plus rien à demander.
                contexte.delete(selection)
            } else if selection.reference == reference {
                if selection.soiree == soiree { dejaPrevu = true } else { contexte.delete(selection) }
            }
        }
        if !dejaPrevu {
            contexte.insert(SelectionSoir(reference: reference, titre: titre, cheminAffiche: cheminAffiche, soiree: soiree))
        }
        try contexte.save()
    }

    /// Retire le titre de la soirée de ce soir, ou de celle donnée.
    public func retirer(_ reference: ReferenceTitre, soiree choisie: String? = nil, maintenant: Date = .now) throws {
        let soiree = choisie ?? Self.soiree(maintenant)
        for selection in try contexte.fetch(FetchDescriptor<SelectionSoir>(predicate: #Predicate { $0.soiree == soiree }))
        where selection.reference == reference {
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
