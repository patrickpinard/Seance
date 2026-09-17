import Foundation

/// Ce qu'on peut dire d'un film absent des plateformes suisses, plutôt que « introuvable » : il est peut-être
/// au cinéma, annoncé en streaming, ou simplement trop récent.
public enum EtatSortie: Sendable, Equatable {
    /// En salle depuis moins de quatre mois ; la sortie en streaming, si elle est déjà datée.
    case auCinema(depuis: DateTMDB, numerique: DateTMDB?)
    case bientotAuCinema(le: DateTMDB)
    case sortieNumerique(le: DateTMDB)
    /// Sortie prévue, sans détail salle ou streaming.
    case aVenir(le: DateTMDB)
    /// Sorti depuis moins d'un an, sans date de streaming connue.
    case pasEncoreEnStreaming

    /// `nil` pour un film ancien : il est alors vraiment introuvable légalement en Suisse.
    public static func etat(dates: DatesDeSortie?, dateMondiale: DateTMDB?, aujourdhui: DateTMDB) -> EtatSortie? {
        let jours = PlanificateurAlertes.joursDeSortie(dates)
        let numeriqueAVenir = jours?.numerique.flatMap { $0 > aujourdhui ? $0 : nil }
        if let salles = jours?.salles {
            if salles > aujourdhui { return .bientotAuCinema(le: salles) }
            if salles >= aujourdhui.decale(jours: -120), jours?.numerique.map({ $0 > aujourdhui }) ?? true {
                return .auCinema(depuis: salles, numerique: numeriqueAVenir)
            }
        }
        if let numeriqueAVenir { return .sortieNumerique(le: numeriqueAVenir) }
        if let dateMondiale {
            if dateMondiale > aujourdhui { return .aVenir(le: dateMondiale) }
            if dateMondiale >= aujourdhui.decale(jours: -365) { return .pasEncoreEnStreaming }
        }
        return nil
    }
}

extension DateTMDB {
    /// Le même jour, décalé d'un nombre de jours, à l'heure suisse.
    func decale(jours: Int) -> DateTMDB {
        DateTMDB(instant(heure: 12).addingTimeInterval(Double(jours) * 86_400))
    }
}
