import Foundation
import SeanceKit
import SwiftData

/// Lit dans le magasin ce qui dit les goûts de Patrick — intérêts cochés, notes, visionnages,
/// titres écartés — et en fait un profil (EF-60 à EF-62). Rien ne quitte l'iPhone à ce stade.
@MainActor
public struct ServiceGouts {
    public let contexte: ModelContext

    public init(contexte: ModelContext) {
        self.contexte = contexte
    }

    public func profil(maintenant: Date = .now) throws -> ProfilGouts {
        ProfilGouts.calculer(try observations(), maintenant: maintenant)
    }

    /// Un signal par intérêt coché, par titre noté, par film vu et par série suivie.
    /// Une série compte pour un titre, quel que soit le nombre d'épisodes, mais pèse plus
    /// lourd quand elle a été dévorée.
    func observations() throws -> [ObservationGout] {
        let suivis = try contexte.fetch(FetchDescriptor<Suivi>())
        let visionnages = try contexte.fetch(FetchDescriptor<Visionnage>())
        let interets = try contexte.fetch(FetchDescriptor<Interet>())
        let parReference = Dictionary(suivis.map { ($0.reference, $0) }, uniquingKeysWith: { premier, _ in premier })
        var observations: [ObservationGout] = []
        var titresCouverts = Set<ReferenceTitre>()

        for interet in interets {
            guard let genre = interet.genreID else { continue }
            observations.append(ObservationGout(origine: .interetDeclare, genres: [genre], poids: interet.poids))
        }

        for visionnage in visionnages where visionnage.type == .film {
            let reference = ReferenceTitre(type: .film, tmdbID: visionnage.tmdbID)
            titresCouverts.insert(reference)
            observations.append(observation(
                origine: (visionnage.note ?? parReference[reference]?.note).map(ObservationGout.Origine.note) ?? .visionnage,
                suivi: parReference[reference], reference: reference,
                duree: visionnage.dureeMinutes, date: visionnage.vuLe
            ))
        }

        let episodesParSerie = Dictionary(grouping: visionnages.filter { $0.type == .serie }) {
            ReferenceTitre(type: .serie, tmdbID: $0.tmdbID)
        }
        for (reference, episodes) in episodesParSerie {
            titresCouverts.insert(reference)
            let notes = episodes.compactMap(\.note)
            let moyenne = notes.isEmpty ? nil : Int((Double(notes.reduce(0, +)) / Double(notes.count)).rounded())
            // La note de la série entière dit plus que la moyenne de quelques épisodes notés.
            observations.append(observation(
                origine: (parReference[reference]?.note ?? moyenne).map(ObservationGout.Origine.note) ?? .visionnage,
                suivi: parReference[reference], reference: reference,
                duree: nil, date: episodes.map(\.vuLe).max(),
                poids: min(2, max(1, Double(episodes.count) / 6))
            ))
        }

        // 👍 « J'aime » : vaut une bonne note (8 sur 10), sauf si une vraie note ou un visionnage parle déjà du titre.
        let notes = Set(suivis.filter { $0.note != nil }.map(\.reference))
        for aime in try contexte.fetch(FetchDescriptor<TitreAime>()) where !titresCouverts.contains(aime.reference) && !notes.contains(aime.reference) {
            observations.append(ObservationGout(
                origine: .note(8), genres: aime.genres, acteurs: aime.acteursIDs,
                nomsActeurs: Dictionary(zip(aime.acteursIDs, aime.acteurs), uniquingKeysWith: { premier, _ in premier }),
                type: aime.reference.type, dureeMinutes: nil, date: aime.aimeLe, poids: 1
            ))
        }

        for suivi in suivis {
            // « Jamais » : un rejet en dit autant qu'une bonne note, dans l'autre sens.
            // Une exclusion de langue (EF-29) ne dit rien des goûts : elle reste dehors.
            if suivi.statut == .exclu, !suivi.exclusionLangue {
                observations.append(observation(origine: .rejet, suivi: suivi, reference: suivi.reference,
                                                duree: nil, date: suivi.ajouteLe))
                continue
            }
            // La note du titre ne compte que si aucun visionnage ne la porte déjà.
            if let note = suivi.note, !titresCouverts.contains(suivi.reference) {
                observations.append(observation(origine: .note(note), suivi: suivi, reference: suivi.reference,
                                                duree: nil, date: suivi.ajouteLe))
            }
        }
        return observations
    }

    private func observation(
        origine: ObservationGout.Origine, suivi: Suivi?, reference: ReferenceTitre,
        duree: Int?, date: Date?, poids: Double = 1
    ) -> ObservationGout {
        let acteurs = suivi?.acteursPrincipauxIDs ?? []
        let noms = suivi.map { suivi in
            Dictionary(zip(suivi.acteursPrincipauxIDs, suivi.acteursPrincipaux), uniquingKeysWith: { premier, _ in premier })
        } ?? [:]
        return ObservationGout(
            origine: origine, genres: suivi?.genres ?? [], acteurs: acteurs, nomsActeurs: noms,
            type: reference.type, dureeMinutes: duree, date: date, poids: poids
        )
    }

    // MARK: - Ce que TMDB ignore

    /// Ce que le collecteur de candidats doit écarter (EF-23, EF-26, EF-29).
    public func contexteCandidats(maintenant: Date = .now) throws -> CollecteurCandidats.Contexte {
        try purgerReports(maintenant: maintenant)
        let abonnements = try contexte.fetch(FetchDescriptor<Abonnement>(predicate: #Predicate { $0.actif }))
        let suivis = try contexte.fetch(FetchDescriptor<Suivi>())
        let visionnages = try contexte.fetch(FetchDescriptor<Visionnage>())
        let reports = try contexte.fetch(FetchDescriptor<SuggestionReportee>())
        return CollecteurCandidats.Contexte(
            abonnements: abonnements.map(\.providerID),
            // Vu : un visionnage enregistré, ou un titre marqué terminé (notation rapide, liste).
            dejaVus: Set(visionnages.map { ReferenceTitre(type: $0.type, tmdbID: $0.tmdbID) })
                .union(suivis.filter { $0.statut == .termine }.map(\.reference)),
            exclus: Set(suivis.filter { $0.statut == .exclu || $0.exclusionLangue }.map(\.reference)),
            reportes: Set(reports.filter { $0.jusquA > maintenant }.map(\.reference))
        )
    }

    // MARK: - Premier lancement (EF-60 à EF-62)

    /// Un goût choisi sur la grille : son nom, ses genres TMDB (films et séries), ses mots-clés.
    public struct InteretDeclare: Sendable, Hashable {
        public var libelle: String
        public var genres: [Int]
        public var motsCles: [Int]

        public init(libelle: String, genres: [Int], motsCles: [Int] = []) {
            self.libelle = libelle
            self.genres = genres
            self.motsCles = motsCles
        }
    }

    /// Vrai dès que Séance connaît quelque chose des goûts : intérêts, notes ou titres suivis.
    public func dejaPersonnalise() throws -> Bool {
        try contexte.fetchCount(FetchDescriptor<Interet>()) > 0 || contexte.fetchCount(FetchDescriptor<Suivi>()) > 0
    }

    public func interetsDeclares() throws -> Set<String> {
        Set(try contexte.fetch(FetchDescriptor<Interet>()).map(\.libelle))
    }

    /// Remplace les intérêts déclarés par la nouvelle sélection de la grille.
    public func declarer(_ interets: [InteretDeclare]) throws {
        try contexte.delete(model: Interet.self)
        for interet in interets {
            for genre in interet.genres {
                contexte.insert(Interet(libelle: interet.libelle, genreID: genre))
            }
            for motCle in interet.motsCles {
                contexte.insert(Interet(libelle: interet.libelle, motCleID: motCle))
            }
        }
        try contexte.save()
    }

    /// Notation rapide : un titre connu, déjà vu, noté de 1 à 10. Il rejoint les titres terminés
    /// sans compter dans les statistiques, faute de date de visionnage.
    @discardableResult
    public func noterTitreConnu(_ titre: TitreResume, note: Int) throws -> Suivi {
        let suivi = try ServiceSuivi(contexte: contexte).suivi(titre.reference) ?? {
            let nouveau = Suivi(reference: titre.reference, titre: titre.titre, statut: .termine, cheminAffiche: titre.cheminAffiche)
            contexte.insert(nouveau)
            return nouveau
        }()
        suivi.note = min(10, max(1, note))
        if suivi.statut == .aVoir { suivi.statut = .termine }
        if suivi.genres.isEmpty { suivi.genres = titre.genres }
        // Un titre noté par curiosité ne déclenche pas d'alertes.
        suivi.alertesActives = false
        try contexte.save()
        return suivi
    }

    // MARK: - Les trois boutons de « Ce soir » (EF-26)

    /// « Je regarde » : le titre entre dans « Mes listes », prêt à être coché après la séance.
    @discardableResult
    public func jeRegarde(_ candidat: CandidatSuggestion) throws -> Suivi {
        let titre = candidat.titre
        let suivi = try ServiceSuivi(contexte: contexte).suivi(candidat.reference) ?? {
            let nouveau = Suivi(reference: candidat.reference, titre: titre.titre, statut: .enCours)
            contexte.insert(nouveau)
            return nouveau
        }()
        suivi.titre = titre.titre
        suivi.cheminAffiche = titre.cheminAffiche
        if !titre.genres.isEmpty { suivi.genres = titre.genres }
        if suivi.statut == .aVoir { suivi.statut = .enCours }
        try contexte.save()
        return suivi
    }

    /// « Pas ce soir » : le titre revient après demain matin, sans rien changer aux goûts.
    public func reporter(_ reference: ReferenceTitre, maintenant: Date = .now) throws {
        let demainMatin = DateTMDB(maintenant).instant(heure: 6).addingTimeInterval(86_400)
        if let existant = try report(reference) {
            existant.jusquA = demainMatin
            existant.reporteLe = maintenant
        } else {
            contexte.insert(SuggestionReportee(reference: reference, jusquA: demainMatin))
        }
        try contexte.save()
    }

    /// Annule un « Pas ce soir » : le titre peut revenir dès maintenant.
    public func annulerReport(_ reference: ReferenceTitre) throws {
        if let existant = try report(reference) {
            contexte.delete(existant)
            try contexte.save()
        }
    }

    /// 👎 « Je n'aime pas » (« Jamais ») : le titre sort des propositions pour de bon, et le profil l'apprend — à
    /// condition de connaître ses genres, que l'appelant passe quand il les a. Un 👍 sur le même titre tombe.
    public func jamais(_ reference: ReferenceTitre, titre: String, genres: [Int] = [], cheminAffiche: String? = nil) throws {
        let suivi = try ServiceSuivi(contexte: contexte).suivi(reference) ?? {
            let nouveau = Suivi(reference: reference, titre: titre, statut: .exclu, cheminAffiche: cheminAffiche)
            contexte.insert(nouveau)
            return nouveau
        }()
        suivi.statut = .exclu
        if suivi.genres.isEmpty { suivi.genres = genres }
        if let aime = try aime(reference) { contexte.delete(aime) }
        try contexte.save()
    }

    // MARK: - 👍 J'aime

    public func estAime(_ reference: ReferenceTitre) throws -> Bool {
        try aime(reference) != nil
    }

    /// 👍 « J'aime » : le titre te plaît, vu ou non. Il n'entre dans aucune liste ; il oriente tes goûts. S'il avait été
    /// écarté (👎), il ne l'est plus. Les acteurs viennent du suivi quand le titre est déjà dans tes listes.
    public func aimer(_ reference: ReferenceTitre, titre: String, cheminAffiche: String?, genres: [Int],
                      acteursIDs: [Int] = [], acteurs: [String] = []) throws {
        let suivi = try ServiceSuivi(contexte: contexte).suivi(reference)
        if let suivi, suivi.statut == .exclu || suivi.exclusionLangue { try reproposer(reference) }
        guard try aime(reference) == nil else { return }
        let connu = try ServiceSuivi(contexte: contexte).suivi(reference)
        contexte.insert(TitreAime(
            reference: reference, titre: titre, cheminAffiche: cheminAffiche,
            genres: genres.isEmpty ? (connu?.genres ?? []) : genres,
            acteursIDs: acteursIDs.isEmpty ? (connu?.acteursPrincipauxIDs ?? []) : acteursIDs,
            acteurs: acteurs.isEmpty ? (connu?.acteursPrincipaux ?? []) : acteurs
        ))
        try contexte.save()
    }

    public func nePlusAimer(_ reference: ReferenceTitre) throws {
        guard let aime = try aime(reference) else { return }
        contexte.delete(aime)
        try contexte.save()
    }

    /// Tes « J'aime », le plus récent d'abord.
    public func aimes() throws -> [TitreAime] {
        try contexte.fetch(FetchDescriptor<TitreAime>(sortBy: [SortDescriptor(\.aimeLe, order: .reverse)]))
    }

    private func aime(_ reference: ReferenceTitre) throws -> TitreAime? {
        let id = reference.tmdbID
        let type = reference.type.rawValue
        var requete = FetchDescriptor<TitreAime>(predicate: #Predicate { $0.tmdbID == id && $0.typeBrut == type })
        requete.fetchLimit = 1
        return try contexte.fetch(requete).first
    }

    /// Les titres écartés à la main (« Je n'aime pas », « Jamais », ni VF ni sous-titres) : ils ne sont plus proposés nulle part.
    public func ecartes() throws -> [Suivi] {
        let exclu = StatutSuivi.exclu.rawValue
        return try contexte.fetch(FetchDescriptor<Suivi>(predicate: #Predicate { $0.statutBrut == exclu || $0.exclusionLangue },
                                                        sortBy: [SortDescriptor(\.titre)]))
    }

    /// Un titre écarté peut de nouveau être proposé. S'il a été regardé ou noté, il retourne dans « Terminés » ;
    /// sinon sa trace disparaît : il n'avait été noté nulle part ailleurs.
    public func reproposer(_ reference: ReferenceTitre) throws {
        guard let suivi = try ServiceSuivi(contexte: contexte).suivi(reference) else { return }
        reintegrer(suivi)
        try contexte.save()
    }

    /// Réglages › « Tout reproposer » : toutes les exclusions sont levées d'un coup ; renvoie leur nombre.
    @discardableResult
    public func reproposerTout() throws -> Int {
        let tous = try ecartes()
        tous.forEach(reintegrer)
        try contexte.save()
        return tous.count
    }

    private func reintegrer(_ suivi: Suivi) {
        suivi.exclusionLangue = false
        guard suivi.statut == .exclu else { return }
        let id = suivi.tmdbID
        let type = suivi.typeBrut
        let vus = (try? contexte.fetchCount(FetchDescriptor<Visionnage>(predicate: #Predicate { $0.tmdbID == id && $0.typeBrut == type }))) ?? 0
        if vus > 0 || suivi.note != nil {
            suivi.statut = .termine
        } else {
            contexte.delete(suivi)
        }
    }

    private func report(_ reference: ReferenceTitre) throws -> SuggestionReportee? {
        let id = reference.tmdbID
        let type = reference.type.rawValue
        var requete = FetchDescriptor<SuggestionReportee>(predicate: #Predicate { $0.tmdbID == id && $0.typeBrut == type })
        requete.fetchLimit = 1
        return try contexte.fetch(requete).first
    }

    private func purgerReports(maintenant: Date) throws {
        let perimes = try contexte.fetch(FetchDescriptor<SuggestionReportee>(predicate: #Predicate { $0.jusquA <= maintenant }))
        guard !perimes.isEmpty else { return }
        perimes.forEach(contexte.delete)
        try contexte.save()
    }
}
