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

    /// Les titres notés 8 ou plus, le mieux noté puis le plus récent d'abord : « Parce que tu as aimé… ».
    public func titresAimes(maximum: Int = 6) throws -> [TitreAime] {
        try contexte.fetch(FetchDescriptor<Suivi>(sortBy: [SortDescriptor(\.ajouteLe, order: .reverse)]))
            .filter { ($0.note ?? 0) >= TitresSimilaires.noteMinimale && $0.statut != .exclu }
            .sorted { ($0.note ?? 0) > ($1.note ?? 0) }
            .prefix(maximum)
            .map { TitreAime(reference: $0.reference, titre: $0.titre, note: $0.note ?? 0) }
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

    /// « Jamais » : le titre sort des suggestions pour de bon, et le profil l'apprend.
    public func jamais(_ reference: ReferenceTitre, titre: String) throws {
        let suivi = try ServiceSuivi(contexte: contexte).suivi(reference) ?? {
            let nouveau = Suivi(reference: reference, titre: titre, statut: .exclu)
            contexte.insert(nouveau)
            return nouveau
        }()
        suivi.statut = .exclu
        try contexte.save()
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
