import Foundation
import SeanceKit
import SwiftData

/// Statistiques et bilan de l'année (EF-34 à EF-37), à partir des visionnages enregistrés.
@MainActor
public struct ServiceStatistiques {
    public let contexte: ModelContext

    public init(contexte: ModelContext) {
        self.contexte = contexte
    }

    public struct MeilleurTitre: Sendable, Hashable {
        public let reference: ReferenceTitre
        public let titre: String
        public let cheminAffiche: String?
        public let note: Int
    }

    /// Chaque visionnage daté, avec les genres et acteurs copiés sur le titre suivi. Un titre « déjà vu avant »
    /// n'a pas de date : il reste hors des statistiques.
    public func visionnages() throws -> [VisionnageStat] {
        let suivis = Dictionary(try contexte.fetch(FetchDescriptor<Suivi>()).map { ($0.reference, $0) }, uniquingKeysWith: { premier, _ in premier })
        return try contexte.fetch(FetchDescriptor<Visionnage>(predicate: #Predicate { $0.anterieur == false })).map { v in
            let reference = ReferenceTitre(type: v.type, tmdbID: v.tmdbID)
            let suivi = suivis[reference]
            return VisionnageStat(reference: reference, dureeMinutes: v.dureeMinutes, vuLe: v.vuLe,
                                  genres: suivi?.genres ?? [], acteurs: suivi?.acteursPrincipaux ?? [],
                                  acteursIDs: suivi?.acteursPrincipauxIDs ?? [])
        }
    }

    /// Bilan d'une année, ou de tout l'historique quand `annee` est `nil`.
    /// Remet les statistiques à zéro sans rien perdre : chaque visionnage compté devient « déjà vu avant », que les
    /// statistiques ignorent. Les titres restent vus, notés, et comptent toujours dans les goûts. Renvoie les
    /// visionnages touchés, pour pouvoir annuler.
    @discardableResult
    public func remettreAZero() throws -> [Visionnage] {
        let comptes = try contexte.fetch(FetchDescriptor<Visionnage>(predicate: #Predicate { !$0.anterieur }))
        comptes.forEach { $0.anterieur = true }
        try contexte.save()
        return comptes
    }

    /// Annule une remise à zéro : ces visionnages comptent de nouveau.
    public func retablir(_ visionnages: [Visionnage]) throws {
        visionnages.forEach { $0.anterieur = false }
        try contexte.save()
    }

    public func bilan(annee: Int?, fuseau: TimeZone = .suisse) throws -> BilanStatistiques {
        Statistiques.calculer(try visionnages(), entre: annee.map { Self.bornes($0, fuseau: fuseau) }, fuseau: fuseau)
    }

    /// Années où quelque chose a été regardé, la plus récente d'abord.
    public func annees(fuseau: TimeZone = .suisse) throws -> [Int] {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = fuseau
        return Set(try contexte.fetch(FetchDescriptor<Visionnage>(predicate: #Predicate { $0.anterieur == false }))
            .map { calendrier.component(.year, from: $0.vuLe) }).sorted(by: >)
    }

    /// Le film vu dans l'année avec la meilleure note ; à note égale, le plus récent.
    public func meilleurFilm(annee: Int, fuseau: TimeZone = .suisse) throws -> MeilleurTitre? {
        let bornes = Self.bornes(annee, fuseau: fuseau)
        let debut = bornes.lowerBound
        let fin = bornes.upperBound
        let film = TypeTitre.film.rawValue
        let vus = try contexte.fetch(FetchDescriptor<Visionnage>(predicate: #Predicate { $0.typeBrut == film && $0.anterieur == false && $0.vuLe >= debut && $0.vuLe <= fin }))
        let suivis = Dictionary(try contexte.fetch(FetchDescriptor<Suivi>()).map { ($0.reference, $0) }, uniquingKeysWith: { premier, _ in premier })
        return vus.compactMap { v -> (MeilleurTitre, Date)? in
            let reference = ReferenceTitre(type: .film, tmdbID: v.tmdbID)
            guard let note = v.note ?? suivis[reference]?.note else { return nil }
            return (MeilleurTitre(reference: reference, titre: suivis[reference]?.titre ?? "", cheminAffiche: suivis[reference]?.cheminAffiche, note: note), v.vuLe)
        }
        .max { ($0.0.note, $0.1) < ($1.0.note, $1.1) }?.0
    }

    /// Le bilan s'ouvre dès le 1er décembre (EF-36) ; avant, il montre l'année en cours.
    public nonisolated static func bilanOuvert(maintenant: Date = .now, fuseau: TimeZone = .suisse) -> Bool {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = fuseau
        return calendrier.component(.month, from: maintenant) == 12
    }

    nonisolated static func bornes(_ annee: Int, fuseau: TimeZone) -> ClosedRange<Date> {
        let debut = DateTMDB(annee: annee, mois: 1, jour: 1).instant(fuseau: fuseau)
        let fin = DateTMDB(annee: annee + 1, mois: 1, jour: 1).instant(fuseau: fuseau).addingTimeInterval(-1)
        return debut...fin
    }
}
