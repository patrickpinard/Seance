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

/// Ce qu'on peut dire d'une série absente des plateformes suisses, plutôt que « introuvable » : elle passe
/// peut-être à la TV ce soir, ou revient bientôt.
public enum EtatDiffusionSerie: Sendable, Equatable {
    /// Un épisode diffusé aujourd'hui.
    case episodeAujourdhui(NumeroEpisode, reseau: String?)
    case prochainEpisode(NumeroEpisode, le: DateTMDB, reseau: String?)
    /// La série n'a pas encore commencé.
    case commence(le: DateTMDB, reseau: String?)
    /// En cours, sans prochain épisode daté.
    case enCours(reseau: String?)
    case terminee(reseau: String?)

    public static func etat(serie: SerieDetail, aujourdhui: DateTMDB) -> EtatDiffusionSerie {
        let reseau = serie.reseaux?.first?.nom
        if let prochain = serie.prochainEpisode, let date = prochain.dateDiffusion {
            if date == aujourdhui { return .episodeAujourdhui(prochain.numeroEpisode, reseau: reseau) }
            if date > aujourdhui { return .prochainEpisode(prochain.numeroEpisode, le: date, reseau: reseau) }
        }
        if let dernier = serie.dernierEpisode, dernier.dateDiffusion == aujourdhui {
            return .episodeAujourdhui(dernier.numeroEpisode, reseau: reseau)
        }
        if let premiere = serie.premiereDiffusion, premiere > aujourdhui {
            return .commence(le: premiere, reseau: reseau)
        }
        if ["Ended", "Canceled"].contains(serie.statut) { return .terminee(reseau: reseau) }
        return .enCours(reseau: reseau)
    }

    public var reseau: String? {
        switch self {
        case .episodeAujourdhui(_, let r), .prochainEpisode(_, _, let r), .commence(_, let r), .enCours(let r), .terminee(let r): r
        }
    }
}
