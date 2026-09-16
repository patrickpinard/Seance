import Foundation

public enum TypeAlerte: String, Sendable, Codable, CaseIterable {
    case arriveePlateforme
    case episode
    case sortieFilm
    case diffusionTele
    case bandeAnnonce
}

public enum MotifAlerte: Sendable, Hashable {
    case arriveeSurPlateforme(nom: String)
    case nouvelEpisode(NumeroEpisode)
    case nouvelleSaison(Int)
    case sortieSalles
    case sortieNumerique
    case diffusionTele(chaine: String, debut: Date)
    case rappelDiffusion(chaine: String, debut: Date)
    case bandeAnnonce

    public var type: TypeAlerte {
        switch self {
        case .arriveeSurPlateforme: .arriveePlateforme
        case .nouvelEpisode, .nouvelleSaison: .episode
        case .sortieSalles, .sortieNumerique: .sortieFilm
        case .diffusionTele, .rappelDiffusion: .diffusionTele
        case .bandeAnnonce: .bandeAnnonce
        }
    }

    /// Clé stable, stockée pour ne jamais envoyer deux fois la même alerte.
    public var cle: String {
        switch self {
        case .arriveeSurPlateforme(let nom): "plateforme:\(nom)"
        case .nouvelEpisode(let numero): "episode:\(numero)"
        case .nouvelleSaison(let saison): "saison:\(saison)"
        case .sortieSalles: "salles"
        case .sortieNumerique: "numerique"
        case .diffusionTele(let chaine, let debut): "tele:\(chaine):\(Int(debut.timeIntervalSince1970))"
        case .rappelDiffusion(let chaine, let debut): "rappel:\(chaine):\(Int(debut.timeIntervalSince1970))"
        case .bandeAnnonce: "bande-annonce"
        }
    }
}

public struct AlertePrevue: Sendable, Hashable {
    public var reference: ReferenceTitre
    public var titre: String
    public var motif: MotifAlerte
    public var date: Date

    public var cle: String { "\(reference):\(motif.cle)" }
}

public struct ReglagesAlertes: Sendable, Hashable {
    /// Heure d'envoi des alertes (EF-20).
    public var heure = 18
    public var minute = 0
    public var typesActifs = Set(TypeAlerte.allCases)
    public var rappelAvantDiffusion: TimeInterval = 15 * 60
    /// Horizon des programmes TV (EF-49).
    public var horizonTele: TimeInterval = 5 * 24 * 3600
    public var fuseau: TimeZone = .suisse

    public init() {}
}

/// Une notification locale, qui peut regrouper plusieurs alertes du même moment (EF-20).
public struct NotificationPrevue: Sendable, Hashable {
    public var date: Date
    public var titre: String
    public var corps: String
    public var alertes: [AlertePrevue]
}

/// Calcule les alertes à programmer ; l'app les confie ensuite aux notifications locales.
public enum PlanificateurAlertes {
    /// EF-17 : une plateforme cochée propose désormais le titre.
    public static func arriveesSurPlateformes(
        _ reference: ReferenceTitre, titre: String,
        avant: Set<Int>, apres: OffresRegion?, abonnements: Set<Int>,
        maintenant: Date, reglages: ReglagesAlertes
    ) -> [AlertePrevue] {
        guard let apres else { return [] }
        let date = prochainEnvoi(apres: maintenant, reglages: reglages)
        return (apres.abonnement + apres.gratuit + apres.avecPublicite)
            .filter { abonnements.contains($0.id) && !avant.contains($0.id) }
            .reduce(into: [Fournisseur]()) { liste, f in if !liste.contains(where: { $0.id == f.id }) { liste.append(f) } }
            .map { AlertePrevue(reference: reference, titre: titre, motif: .arriveeSurPlateforme(nom: $0.nom), date: date) }
            .filter { reglages.typesActifs.contains($0.motif.type) }
    }

    /// EF-18 : le prochain épisode annoncé d'une série suivie, le jour de sa diffusion.
    public static func episodes(_ serie: SerieDetail, maintenant: Date, reglages: ReglagesAlertes) -> [AlertePrevue] {
        guard reglages.typesActifs.contains(.episode),
              let prochain = serie.prochainEpisode, let jour = prochain.dateDiffusion,
              jour >= DateTMDB(maintenant, fuseau: reglages.fuseau)
        else { return [] }
        let motif: MotifAlerte = prochain.numero == 1 ? .nouvelleSaison(prochain.saison) : .nouvelEpisode(prochain.numeroEpisode)
        let date = jour.instant(heure: reglages.heure, minute: reglages.minute, fuseau: reglages.fuseau)
        guard date > maintenant else { return [] }
        return [AlertePrevue(reference: serie.reference, titre: serie.nom, motif: motif, date: date)]
    }

    /// EF-19 : sortie en salle puis en numérique, en Suisse.
    public static func sortiesFilm(
        _ reference: ReferenceTitre, titre: String, dates: DatesDeSortie,
        maintenant: Date, reglages: ReglagesAlertes, region: String = "CH"
    ) -> [AlertePrevue] {
        guard reglages.typesActifs.contains(.sortieFilm) else { return [] }
        let sorties = dates.sorties(region: region)
        func premiere(_ types: Set<TypeSortie>, _ motif: MotifAlerte) -> AlertePrevue? {
            // TMDB date les sorties à minuit UTC : seul le jour compte.
            let jours = sorties.filter { $0.type.map(types.contains) ?? false }.compactMap(\.date).map { DateTMDB($0, fuseau: TimeZone(identifier: "UTC")!) }
            guard let jour = jours.min() else { return nil }
            let date = jour.instant(heure: reglages.heure, minute: reglages.minute, fuseau: reglages.fuseau)
            guard date > maintenant else { return nil }
            return AlertePrevue(reference: reference, titre: titre, motif: motif, date: date)
        }
        return [premiere([.salles, .sallesLimitees], .sortieSalles), premiere([.numerique], .sortieNumerique)].compactMap { $0 }
    }

    /// EF-49 : un titre attendu passe à la télé dans les 5 jours ; alerte à 18 h le jour même, puis rappel.
    public static func diffusions(
        _ reference: ReferenceTitre, titre: String, diffusions: [DiffusionPrevue],
        maintenant: Date, reglages: ReglagesAlertes
    ) -> [AlertePrevue] {
        guard reglages.typesActifs.contains(.diffusionTele) else { return [] }
        let limite = maintenant.addingTimeInterval(reglages.horizonTele)
        return diffusions.filter { $0.debut > maintenant && $0.debut <= limite }.flatMap { diffusion -> [AlertePrevue] in
            var alertes: [AlertePrevue] = []
            let jour = DateTMDB(diffusion.debut, fuseau: reglages.fuseau)
            let envoi = jour.instant(heure: reglages.heure, minute: reglages.minute, fuseau: reglages.fuseau)
            if envoi > maintenant, envoi < diffusion.debut {
                alertes.append(AlertePrevue(reference: reference, titre: titre,
                                            motif: .diffusionTele(chaine: diffusion.chaine, debut: diffusion.debut), date: envoi))
            }
            let rappel = diffusion.debut.addingTimeInterval(-reglages.rappelAvantDiffusion)
            if rappel > maintenant {
                alertes.append(AlertePrevue(reference: reference, titre: titre,
                                            motif: .rappelDiffusion(chaine: diffusion.chaine, debut: diffusion.debut), date: rappel))
            }
            return alertes
        }
    }

    /// Retire les alertes déjà envoyées, puis regroupe celles qui tombent au même moment (EF-20).
    public static func notifications(_ alertes: [AlertePrevue], dejaEnvoyees: Set<String>, reglages: ReglagesAlertes) -> [NotificationPrevue] {
        let aEnvoyer = alertes
            .filter { !dejaEnvoyees.contains($0.cle) }
            .reduce(into: [AlertePrevue]()) { liste, a in if !liste.contains(where: { $0.cle == a.cle }) { liste.append(a) } }
        return Dictionary(grouping: aEnvoyer, by: \.date)
            .sorted { $0.key < $1.key }
            .map { date, groupe in
                let groupe = groupe.sorted { $0.titre < $1.titre }
                if groupe.count == 1, let seule = groupe.first {
                    return NotificationPrevue(date: date, titre: seule.titre, corps: texte(seule.motif, fuseau: reglages.fuseau), alertes: groupe)
                }
                return NotificationPrevue(
                    date: date,
                    titre: "Séance : \(groupe.count) nouveautés",
                    corps: groupe.map { "\($0.titre) — \(texte($0.motif, fuseau: reglages.fuseau))" }.joined(separator: "\n"),
                    alertes: groupe
                )
            }
    }

    /// Prochaine heure d'envoi : aujourd'hui si elle n'est pas passée, sinon demain.
    static func prochainEnvoi(apres maintenant: Date, reglages: ReglagesAlertes) -> Date {
        let aujourdhui = DateTMDB(maintenant, fuseau: reglages.fuseau)
        let envoi = aujourdhui.instant(heure: reglages.heure, minute: reglages.minute, fuseau: reglages.fuseau)
        if envoi > maintenant { return envoi }
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = reglages.fuseau
        return calendrier.date(byAdding: .day, value: 1, to: envoi)!
    }

    static func texte(_ motif: MotifAlerte, fuseau: TimeZone) -> String {
        let heure = Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "fr_CH"), timeZone: fuseau)
        switch motif {
        case .arriveeSurPlateforme(let nom): return "Maintenant sur \(nom)"
        case .nouvelEpisode(let numero): return "Nouvel épisode \(numero) disponible"
        case .nouvelleSaison(let saison): return "La saison \(saison) commence aujourd'hui"
        case .sortieSalles: return "Sort aujourd'hui au cinéma"
        case .sortieNumerique: return "Sort aujourd'hui en numérique"
        case .diffusionTele(let chaine, let debut): return "Ce soir sur \(chaine) à \(debut.formatted(heure))"
        case .rappelDiffusion(let chaine, _): return "Commence dans 15 minutes sur \(chaine)"
        case .bandeAnnonce: return "Nouvelle bande-annonce"
        }
    }
}
