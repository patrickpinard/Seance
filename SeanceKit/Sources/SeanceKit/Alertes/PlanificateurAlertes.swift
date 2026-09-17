import Foundation

public enum TypeAlerte: String, Sendable, Codable, CaseIterable {
    case arriveePlateforme
    case episode
    case sortieFilm
    case diffusionTele
    case bandeAnnonce
}

/// Ce qu'une série surveillée déclenche (cloche de la fiche).
public enum ModeAlerteSerie: String, Sendable, Codable, CaseIterable {
    /// Veille et jour de chaque épisode, annonce des nouvelles saisons.
    case episodes
    /// Seulement l'annonce et le début des nouvelles saisons.
    case saisons
}

public enum MotifAlerte: Sendable, Hashable {
    case arriveeSurPlateforme(nom: String)
    case disponibleEnLocation(nom: String)
    case nouvelEpisode(NumeroEpisode)
    case nouvelleSaison(Int)
    case veilleEpisode(NumeroEpisode)
    case annonceSaison(saison: Int, date: DateTMDB)
    case sortieSalles
    case sortieNumerique
    /// Date de sortie mondiale, faute de date en Suisse, en France ou en Allemagne.
    case sortie
    case veilleSortie(salles: Bool)
    case annonceSortie(date: DateTMDB)
    case diffusionTele(chaine: String, debut: Date)
    case rappelDiffusion(chaine: String, debut: Date)
    case bandeAnnonce
    /// « Suivre un acteur » : un film où il joue vient d'apparaître dans sa filmographie.
    case nouveauFilmActeur(nom: String, date: DateTMDB?)

    public var type: TypeAlerte {
        switch self {
        case .arriveeSurPlateforme, .disponibleEnLocation: .arriveePlateforme
        case .nouvelEpisode, .nouvelleSaison, .veilleEpisode, .annonceSaison: .episode
        case .sortieSalles, .sortieNumerique, .sortie, .veilleSortie, .annonceSortie, .nouveauFilmActeur: .sortieFilm
        case .diffusionTele, .rappelDiffusion: .diffusionTele
        case .bandeAnnonce: .bandeAnnonce
        }
    }

    /// Alerte née d'un changement constaté (annonce, arrivée) : elle ne se recalcule pas, elle est
    /// gardée jusqu'à son envoi. Les autres découlent d'une date et se recalculent à chaque passage.
    public var ponctuelle: Bool {
        switch self {
        case .annonceSaison, .annonceSortie, .arriveeSurPlateforme, .disponibleEnLocation, .nouveauFilmActeur: true
        default: false
        }
    }

    /// Clé stable, stockée pour ne jamais envoyer deux fois la même alerte.
    public var cle: String {
        switch self {
        case .arriveeSurPlateforme(let nom): "plateforme:\(nom)"
        case .disponibleEnLocation(let nom): "location:\(nom)"
        case .nouvelEpisode(let numero): "episode:\(numero)"
        case .nouvelleSaison(let saison): "saison:\(saison)"
        case .veilleEpisode(let numero): "veille:\(numero)"
        case .annonceSaison(let saison, let date): "annonce-saison:\(saison):\(date)"
        case .sortieSalles: "salles"
        case .sortieNumerique: "numerique"
        case .sortie: "sortie"
        case .veilleSortie(let salles): salles ? "veille-salles" : "veille-sortie"
        case .annonceSortie(let date): "annonce-sortie:\(date)"
        case .diffusionTele(let chaine, let debut): "tele:\(chaine):\(Int(debut.timeIntervalSince1970))"
        case .rappelDiffusion(let chaine, let debut): "rappel:\(chaine):\(Int(debut.timeIntervalSince1970))"
        case .bandeAnnonce: "bande-annonce"
        case .nouveauFilmActeur(let nom, _): "acteur:\(nom)"
        }
    }
}

public struct AlertePrevue: Sendable, Hashable {
    public var reference: ReferenceTitre
    public var titre: String
    public var motif: MotifAlerte
    public var date: Date

    public init(reference: ReferenceTitre, titre: String, motif: MotifAlerte, date: Date) {
        self.reference = reference
        self.titre = titre
        self.motif = motif
        self.date = date
    }

    public var cle: String { "\(reference):\(motif.cle)" }
}

/// Ce que le calcul des alertes demande à TMDB ; `TMDBClient` le fournit, les tests le simulent.
/// Une seule fiche par titre : dates de sortie et plateformes arrivent dans le même appel.
public protocol SourceAlertes: Sendable {
    func film(_ id: Int, complements: Set<ComplementFiche>) async throws -> FicheFilm
    func serie(_ id: Int, complements: Set<ComplementFiche>) async throws -> SerieDetail
    /// Pour les acteurs suivis.
    func filmographie(personne id: Int) async throws -> Filmographie
}

extension TMDBClient: SourceAlertes {}

public struct ReglagesAlertes: Sendable, Hashable, Codable {
    /// Heure d'envoi des alertes (EF-20).
    public var heure = 18
    public var minute = 0
    public var typesActifs = Set(TypeAlerte.allCases)
    public var rappelAvantDiffusion: TimeInterval = 15 * 60
    /// Horizon des programmes TV (EF-49).
    public var horizonTele: TimeInterval = 5 * 24 * 3600
    public var fuseau: TimeZone = .suisse
    /// Prévenir la veille d'un épisode ou d'une sortie.
    public var veille = true
    /// Prévenir dès qu'une nouvelle saison ou une date de sortie est annoncée.
    public var annonces = true

    public init() {}

    /// Libellé des types dans les réglages ; les bandes-annonces (EF-68) ne sont pas encore surveillées.
    public static let typesProposes: [TypeAlerte] = [.episode, .sortieFilm, .arriveePlateforme, .diffusionTele]

    enum CodingKeys: String, CodingKey {
        case heure, minute, typesActifs, rappelAvantDiffusion, horizonTele, fuseau, veille, annonces
    }

    /// Les réglages enregistrés par une version précédente restent valables : les champs ajoutés
    /// depuis prennent leur valeur par défaut.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaut = ReglagesAlertes()
        heure = try c.decodeIfPresent(Int.self, forKey: .heure) ?? defaut.heure
        minute = try c.decodeIfPresent(Int.self, forKey: .minute) ?? defaut.minute
        typesActifs = try c.decodeIfPresent(Set<TypeAlerte>.self, forKey: .typesActifs) ?? defaut.typesActifs
        rappelAvantDiffusion = try c.decodeIfPresent(TimeInterval.self, forKey: .rappelAvantDiffusion) ?? defaut.rappelAvantDiffusion
        horizonTele = try c.decodeIfPresent(TimeInterval.self, forKey: .horizonTele) ?? defaut.horizonTele
        fuseau = try c.decodeIfPresent(TimeZone.self, forKey: .fuseau) ?? defaut.fuseau
        veille = try c.decodeIfPresent(Bool.self, forKey: .veille) ?? defaut.veille
        annonces = try c.decodeIfPresent(Bool.self, forKey: .annonces) ?? defaut.annonces
    }
}

extension TypeAlerte {
    public var libelle: String {
        switch self {
        case .arriveePlateforme: "Arrivée sur tes plateformes et en location"
        case .episode: "Nouveaux épisodes et saisons"
        case .sortieFilm: "Sorties de films"
        case .diffusionTele: "Passages à la télé"
        case .bandeAnnonce: "Nouvelles bandes-annonces"
        }
    }
}

/// Une notification locale, qui peut regrouper plusieurs alertes du même moment (EF-20).
public struct NotificationPrevue: Sendable, Hashable {
    public var date: Date
    public var titre: String
    public var corps: String
    public var alertes: [AlertePrevue]
    /// Identifiant de la notification dans iOS, stable d'un calcul à l'autre.
    public var identifiant: String
    /// Titre ouvert quand on touche la notification.
    public var reference: ReferenceTitre?

    public init(date: Date, titre: String, corps: String, alertes: [AlertePrevue], identifiant: String? = nil, reference: ReferenceTitre? = nil) {
        self.date = date
        self.titre = titre
        self.corps = corps
        self.alertes = alertes
        self.identifiant = identifiant ?? alertes.map(\.cle).joined(separator: "|")
        self.reference = reference ?? alertes.first?.reference
    }
}

/// Un rendez-vous d'un titre surveillé, pour l'écran « À venir » et le widget des prochaines sorties.
public struct EcheancePrevue: Sendable, Hashable {
    public enum Nature: String, Sendable, Codable {
        case episode
        case saison
        case sortie
        case tele
    }

    public var reference: ReferenceTitre
    public var titre: String
    public var date: Date
    public var libelle: String
    public var nature: Nature

    public init(reference: ReferenceTitre, titre: String, date: Date, libelle: String, nature: Nature) {
        self.reference = reference
        self.titre = titre
        self.date = date
        self.libelle = libelle
        self.nature = nature
    }
}

/// Calcule les alertes à programmer ; l'app les confie ensuite aux notifications locales.
public enum PlanificateurAlertes {
    /// Régions consultées pour la sortie d'un film : la Suisse d'abord, puis ses voisins francophone
    /// et germanophone, dont les dates sont souvent les mêmes.
    public static let regionsSortie = ["CH", "FR", "DE"]

    /// EF-17 : une plateforme cochée propose désormais le titre.
    public static func arriveesSurPlateformes(
        _ reference: ReferenceTitre, titre: String,
        avant: Set<Int>, apres: OffresRegion?, abonnements: Set<Int>,
        maintenant: Date, reglages: ReglagesAlertes
    ) -> [AlertePrevue] {
        guard let apres else { return [] }
        let date = prochainEnvoi(apres: maintenant, reglages: reglages)
        return uniques(apres.abonnement + apres.gratuit + apres.avecPublicite)
            .filter { abonnements.contains($0.id) && !avant.contains($0.id) }
            .map { AlertePrevue(reference: reference, titre: titre, motif: .arriveeSurPlateforme(nom: $0.nom), date: date) }
            .filter { reglages.typesActifs.contains($0.motif.type) }
    }

    /// Un film devient disponible en location ou à l'achat en Suisse : la sortie numérique est là.
    /// Une seule alerte, même si plusieurs boutiques l'ajoutent le même jour.
    public static func arriveesEnLocation(
        _ reference: ReferenceTitre, titre: String, avant: Set<Int>, apres: OffresRegion?,
        maintenant: Date, reglages: ReglagesAlertes
    ) -> [AlertePrevue] {
        guard reglages.typesActifs.contains(.arriveePlateforme), let apres, avant.isEmpty,
              let premiere = uniques(apres.location + apres.achat).sorted(by: { $0.priorite < $1.priorite }).first
        else { return [] }
        return [AlertePrevue(reference: reference, titre: titre, motif: .disponibleEnLocation(nom: premiere.nom),
                             date: prochainEnvoi(apres: maintenant, reglages: reglages))]
    }

    /// EF-18 : le prochain épisode annoncé d'une série suivie, la veille et le jour de sa diffusion.
    /// En mode « saisons », seul le premier épisode d'une saison compte.
    public static func episodes(
        _ serie: SerieDetail, mode: ModeAlerteSerie = .episodes, maintenant: Date, reglages: ReglagesAlertes
    ) -> [AlertePrevue] {
        guard reglages.typesActifs.contains(.episode),
              let prochain = serie.prochainEpisode, let jour = prochain.dateDiffusion,
              jour >= DateTMDB(maintenant, fuseau: reglages.fuseau),
              mode == .episodes || prochain.numero == 1
        else { return [] }
        var alertes: [AlertePrevue] = []
        if reglages.veille, let veille = jour.instant(heure: reglages.heure, minute: reglages.minute, fuseau: reglages.fuseau).veille(reglages.fuseau),
           veille > maintenant {
            alertes.append(AlertePrevue(reference: serie.reference, titre: serie.nom, motif: .veilleEpisode(prochain.numeroEpisode), date: veille))
        }
        let date = jour.instant(heure: reglages.heure, minute: reglages.minute, fuseau: reglages.fuseau)
        if date > maintenant {
            let motif: MotifAlerte = prochain.numero == 1 ? .nouvelleSaison(prochain.saison) : .nouvelEpisode(prochain.numeroEpisode)
            alertes.append(AlertePrevue(reference: serie.reference, titre: serie.nom, motif: motif, date: date))
        }
        return alertes
    }

    /// EF-19 : sortie en salle puis en numérique, en Suisse, sinon en France ou en Allemagne ;
    /// à défaut, la date de sortie mondiale. Alerte la veille et le jour même.
    public static func sortiesFilm(
        _ reference: ReferenceTitre, titre: String, dates: DatesDeSortie?, dateMondiale: DateTMDB? = nil,
        maintenant: Date, reglages: ReglagesAlertes
    ) -> [AlertePrevue] {
        guard reglages.typesActifs.contains(.sortieFilm) else { return [] }
        var jours: [(MotifAlerte, DateTMDB)] = []
        if let (salles, numerique) = joursDeSortie(dates) {
            if let salles { jours.append((.sortieSalles, salles)) }
            if let numerique { jours.append((.sortieNumerique, numerique)) }
        } else if let dateMondiale {
            jours.append((.sortie, dateMondiale))
        }
        return jours.flatMap { motif, jour -> [AlertePrevue] in
            var alertes: [AlertePrevue] = []
            let date = jour.instant(heure: reglages.heure, minute: reglages.minute, fuseau: reglages.fuseau)
            if reglages.veille, motif != .sortieNumerique, let veille = date.veille(reglages.fuseau), veille > maintenant {
                alertes.append(AlertePrevue(reference: reference, titre: titre, motif: .veilleSortie(salles: motif == .sortieSalles), date: veille))
            }
            if date > maintenant {
                alertes.append(AlertePrevue(reference: reference, titre: titre, motif: motif, date: date))
            }
            return alertes
        }
    }

    /// Premiers jours de sortie en salle et en numérique, dans la première région qui en connaît.
    public static func joursDeSortie(_ dates: DatesDeSortie?) -> (salles: DateTMDB?, numerique: DateTMDB?)? {
        guard let dates else { return nil }
        for region in regionsSortie {
            let sorties = dates.sorties(region: region)
            guard !sorties.isEmpty else { continue }
            // TMDB date les sorties à minuit UTC : seul le jour compte.
            func premier(_ types: Set<TypeSortie>) -> DateTMDB? {
                sorties.filter { $0.type.map(types.contains) ?? false }.compactMap(\.date)
                    .map { DateTMDB($0, fuseau: TimeZone(identifier: "UTC")!) }.min()
            }
            let salles = premier([.salles, .sallesLimitees])
            let numerique = premier([.numerique])
            if salles != nil || numerique != nil { return (salles, numerique) }
        }
        return nil
    }

    /// Ce qu'un titre a d'annoncé : la date d'une nouvelle saison, ou la prochaine sortie d'un film.
    /// La clé change quand TMDB publie ou modifie la date ; `aucune` quand rien n'est annoncé.
    public static func annonceSerie(_ serie: SerieDetail) -> (cle: String, saison: Int, date: DateTMDB)? {
        guard let prochain = serie.prochainEpisode, prochain.numero == 1, let date = prochain.dateDiffusion else { return nil }
        return ("saison:\(prochain.saison)@\(date)", prochain.saison, date)
    }

    public static func annonceFilm(dates: DatesDeSortie?, dateMondiale: DateTMDB?, aujourdhui: DateTMDB) -> (cle: String, date: DateTMDB)? {
        let candidats: [DateTMDB]
        if let (salles, numerique) = joursDeSortie(dates) {
            candidats = [salles, numerique].compactMap { $0 }
        } else {
            candidats = [dateMondiale].compactMap { $0 }
        }
        guard let prochaine = candidats.filter({ $0 >= aujourdhui }).min() else { return nil }
        return ("sortie@\(prochaine)", prochaine)
    }

    public static let aucuneAnnonce = "aucune"

    /// Alerte d'annonce quand la clé change ; la première observation d'un titre ne dit rien.
    public static func annonce(
        _ reference: ReferenceTitre, titre: String, avant: String?, apres: String, motif: MotifAlerte,
        maintenant: Date, reglages: ReglagesAlertes
    ) -> [AlertePrevue] {
        guard reglages.annonces, reglages.typesActifs.contains(motif.type), let avant, avant != apres, apres != aucuneAnnonce else { return [] }
        return [AlertePrevue(reference: reference, titre: titre, motif: motif, date: prochainEnvoi(apres: maintenant, reglages: reglages))]
    }

    /// « Suivre un acteur » : les films où il joue, apparus depuis la dernière vérification et pas encore sortis
    /// (ou sans date). La première vérification mémorise la filmographie sans rien signaler ; les apparitions
    /// « dans son propre rôle » et les voix ne comptent pas.
    public static func nouveauxFilms(
        acteur nom: String, connus: Set<Int>?, filmographie: Filmographie,
        maintenant: Date, reglages: ReglagesAlertes
    ) -> (alertes: [AlertePrevue], connus: Set<Int>) {
        let films = AnalyseFilmographie.significatifs(filmographie.roles).filter { $0.type == .film }
        let tous = Set(filmographie.roles.filter { $0.type == .film }.map(\.tmdbID))
        guard let connus, reglages.annonces, reglages.typesActifs.contains(.sortieFilm) else { return ([], tous.union(connus ?? [])) }
        let aujourdhui = DateTMDB(maintenant, fuseau: reglages.fuseau)
        let envoi = prochainEnvoi(apres: maintenant, reglages: reglages)
        let alertes = films
            .filter { !connus.contains($0.tmdbID) && ($0.date.map { $0 >= aujourdhui } ?? true) }
            .map { AlertePrevue(reference: $0.reference, titre: $0.titre, motif: .nouveauFilmActeur(nom: nom, date: $0.date), date: envoi) }
        return (alertes, tous.union(connus))
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

    public static func texte(_ motif: MotifAlerte, fuseau: TimeZone) -> String {
        let heure = Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "fr_CH"), timeZone: fuseau)
        switch motif {
        case .arriveeSurPlateforme(let nom): return "Maintenant sur \(nom)"
        case .disponibleEnLocation(let nom): return "Disponible en location ou à l'achat, notamment sur \(nom)"
        case .nouvelEpisode(let numero): return "Nouvel épisode \(numero) disponible"
        case .nouvelleSaison(let saison): return "La saison \(saison) commence aujourd'hui"
        case .veilleEpisode(let numero):
            return numero.episode == 1 ? "La saison \(numero.saison) commence demain" : "Demain : épisode \(numero)"
        case .annonceSaison(let saison, let date): return "La saison \(saison) arrive le \(jour(date))"
        case .sortieSalles: return "Sort aujourd'hui au cinéma"
        case .sortieNumerique: return "Sort aujourd'hui en numérique"
        case .sortie: return "Sort aujourd'hui"
        case .veilleSortie(let salles): return salles ? "Sort demain au cinéma" : "Sort demain"
        case .annonceSortie(let date): return "Sortie annoncée le \(jour(date))"
        case .diffusionTele(let chaine, let debut): return "Ce soir sur \(chaine) à \(debut.formatted(heure))"
        case .rappelDiffusion(let chaine, let debut): return "Commence à \(debut.formatted(heure)) sur \(chaine)"
        case .bandeAnnonce: return "Nouvelle bande-annonce"
        case .nouveauFilmActeur(let nom, let date):
            return date.map { "Nouveau film avec \(nom), sortie prévue le \(jour($0))" } ?? "Nouveau film annoncé avec \(nom)"
        }
    }

    /// « 12 mars 2027 ».
    static func jour(_ date: DateTMDB) -> String {
        date.instant(heure: 12).formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "fr_CH")))
    }

    private static func uniques(_ fournisseurs: [Fournisseur]) -> [Fournisseur] {
        fournisseurs.reduce(into: [Fournisseur]()) { liste, f in if !liste.contains(where: { $0.id == f.id }) { liste.append(f) } }
    }
}

extension Date {
    /// La même heure, la veille.
    func veille(_ fuseau: TimeZone) -> Date? {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = fuseau
        return calendrier.date(byAdding: .day, value: -1, to: self)
    }
}
