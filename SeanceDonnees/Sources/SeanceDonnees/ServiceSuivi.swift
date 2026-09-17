import Foundation
import SeanceKit
import SwiftData

/// Enregistre ce que Patrick suit et regarde (EF-11, EF-14 à EF-16, EF-29, EF-66).
@MainActor
public struct ServiceSuivi {
    public let contexte: ModelContext

    public init(contexte: ModelContext) {
        self.contexte = contexte
    }

    // MARK: - Lecture

    public func suivi(_ reference: ReferenceTitre) throws -> Suivi? {
        let id = reference.tmdbID
        let type = reference.type.rawValue
        var requete = FetchDescriptor<Suivi>(predicate: #Predicate { $0.tmdbID == id && $0.typeBrut == type })
        requete.fetchLimit = 1
        return try contexte.fetch(requete).first
    }

    public func visionnages(_ reference: ReferenceTitre) throws -> [Visionnage] {
        let id = reference.tmdbID
        let type = reference.type.rawValue
        return try contexte.fetch(FetchDescriptor<Visionnage>(
            predicate: #Predicate { $0.tmdbID == id && $0.typeBrut == type },
            sortBy: [SortDescriptor(\.vuLe)]
        ))
    }

    public func episodesVus(_ serie: ReferenceTitre) throws -> Set<NumeroEpisode> {
        Set(try visionnages(serie).compactMap { v in
            guard let saison = v.saison, let episode = v.episode else { return nil }
            return NumeroEpisode(saison: saison, episode: episode)
        })
    }

    public func estVu(_ reference: ReferenceTitre) throws -> Bool {
        !(try visionnages(reference)).isEmpty
    }

    // MARK: - Suivi

    /// Ajoute le film aux listes, ou met à jour les copies prises depuis TMDB.
    @discardableResult
    public func suivre(film: FicheFilm, statut: StatutSuivi = .aVoir) throws -> Suivi {
        try enregistrer(film.reference, titre: film.titre, affiche: film.cheminAffiche,
                        casting: film.casting, genres: film.genres, statut: statut)
    }

    @discardableResult
    public func suivre(serie: SerieDetail, statut: StatutSuivi = .aVoir) throws -> Suivi {
        try enregistrer(serie.reference, titre: serie.nom, affiche: serie.cheminAffiche,
                        casting: serie.casting, genres: serie.genres, statut: statut)
    }

    /// « Ni VF ni sous-titres FR » : le titre sort de toutes les suggestions (EF-29).
    public func exclureLangue(_ reference: ReferenceTitre, titre: String) throws {
        let suivi = try suivi(reference) ?? inserer(Suivi(reference: reference, titre: titre, statut: .exclu))
        suivi.exclusionLangue = true
        try contexte.save()
    }

    // MARK: - Visionnages

    /// EF-14 : un film vu, avec sa note facultative. `anterieur` : déjà vu avant, hors statistiques.
    public func marquerVu(film: FicheFilm, note: Int? = nil, le date: Date = .now, anterieur: Bool = false) throws {
        let suivi = try suivre(film: film, statut: .termine)
        let visionnage = Visionnage(reference: film.reference, dureeMinutes: film.dureeMinutes ?? 0, vuLe: date, anterieur: anterieur)
        visionnage.note = note
        contexte.insert(visionnage)
        if let note { suivi.note = note }
        try contexte.save()
    }

    /// Annule « Vu » ou « Déjà vu avant » touché par erreur : les visionnages et la note s'effacent, et le film
    /// reste dans Mes listes, « à voir ».
    public func marquerNonVu(film reference: ReferenceTitre) throws {
        for visionnage in try visionnages(reference) {
            contexte.delete(visionnage)
        }
        if let suivi = try suivi(reference) {
            suivi.note = nil
            if suivi.statut == .termine { suivi.statut = .aVoir }
        }
        try contexte.save()
    }

    /// EF-11 : coche les épisodes donnés, sans doublon ; renvoie le nombre d'épisodes ajoutés.
    /// `anterieur` : des épisodes déjà vus avant, hors statistiques.
    @discardableResult
    public func cocher(_ episodes: [EpisodeTMDB], serie: SerieDetail, le date: Date = .now, anterieur: Bool = false) throws -> Int {
        let dejaVus = try episodesVus(serie.reference)
        let suivi = try suivre(serie: serie, statut: .enCours)
        var ajoutes = 0
        for episode in episodes where episode.saison > 0 && !dejaVus.contains(episode.numeroEpisode) {
            let duree = episode.dureeMinutes ?? serie.dureesEpisode.first ?? 0
            contexte.insert(Visionnage(reference: serie.reference, saison: episode.saison, episode: episode.numero, dureeMinutes: duree,
                                       vuLe: date, anterieur: anterieur))
            ajoutes += 1
        }
        if suivi.statut == .aVoir { suivi.statut = .enCours }
        try contexte.save()
        return ajoutes
    }

    /// Coche un épisode connu par son seul numéro, depuis un widget ou Siri, sans fiche TMDB ;
    /// `false` s'il était déjà vu.
    @discardableResult
    public func cocher(_ numero: NumeroEpisode, serie: ReferenceTitre, dureeMinutes: Int, le date: Date = .now) throws -> Bool {
        guard numero.saison > 0, try !episodesVus(serie).contains(numero) else { return false }
        contexte.insert(Visionnage(reference: serie, saison: numero.saison, episode: numero.episode, dureeMinutes: dureeMinutes, vuLe: date))
        if let suivi = try suivi(serie), suivi.statut == .aVoir { suivi.statut = .enCours }
        try contexte.save()
        return true
    }

    public func decocher(_ numero: NumeroEpisode, serie: ReferenceTitre) throws {
        for visionnage in try visionnages(serie) where visionnage.saison == numero.saison && visionnage.episode == numero.episode {
            contexte.delete(visionnage)
        }
        try contexte.save()
        // Plus aucun épisode vu : la série redevient « à voir », comme avant le premier épisode coché.
        if try visionnages(serie).isEmpty, let suivi = try suivi(serie), suivi.statut == .enCours {
            suivi.statut = .aVoir
            try contexte.save()
        }
    }

    /// EF-66 : note d'un épisode déjà vu.
    public func noter(_ numero: NumeroEpisode, serie: ReferenceTitre, note: Int) throws {
        for visionnage in try visionnages(serie) where visionnage.saison == numero.saison && visionnage.episode == numero.episode {
            visionnage.note = note
        }
        try contexte.save()
    }

    /// Ta note du film, de 1 à 10, ou `nil` pour l'effacer : le signal le plus sûr pour les goûts.
    public func noter(film: FicheFilm, note: Int?) throws {
        let suivi = try suivre(film: film, statut: .termine)
        suivi.note = note.map { min(10, max(1, $0)) }
        for visionnage in try visionnages(film.reference) {
            visionnage.note = suivi.note
        }
        try contexte.save()
    }

    /// Ta note de la série dans son ensemble ; elle l'emporte sur la moyenne des épisodes notés.
    public func noter(serie: SerieDetail, note: Int?) throws {
        let suivi = try suivre(serie: serie, statut: try self.suivi(serie.reference)?.statut ?? .enCours)
        suivi.note = note.map { min(10, max(1, $0)) }
        try contexte.save()
    }

    // MARK: - Terminés

    /// Supprime des titres de la liste « Terminés » sans effacer leur historique : visionnages, note et goûts restent,
    /// et ils ne reviennent pas dans les suggestions.
    public func supprimerDesTermines(_ suivis: [Suivi]) throws {
        for suivi in suivis where suivi.statut == .termine {
            suivi.masque = true
        }
        try contexte.save()
    }

    /// Les titres que la liste « Terminés » affiche encore.
    public func termines() throws -> [Suivi] {
        let termine = StatutSuivi.termine.rawValue
        return try contexte.fetch(FetchDescriptor<Suivi>(predicate: #Predicate { $0.statutBrut == termine && !$0.masque }))
    }

    // MARK: - Interne

    private func enregistrer(
        _ reference: ReferenceTitre, titre: String, affiche: String?,
        casting: Casting?, genres: [Genre], statut: StatutSuivi
    ) throws -> Suivi {
        let suivi = try suivi(reference) ?? inserer(Suivi(reference: reference, titre: titre, statut: statut))
        suivi.titre = titre
        suivi.cheminAffiche = affiche
        if let casting {
            let principaux = casting.principaux(5)
            suivi.acteursPrincipaux = principaux.map(\.nom)
            suivi.acteursPrincipauxIDs = principaux.map(\.id)
        }
        if !genres.isEmpty { suivi.genres = genres.map(\.id) }
        // Un titre exclu ou terminé ne revient pas « à voir » par un simple ajout.
        if statut != .aVoir || suivi.statut == .aVoir { suivi.statut = statut }
        try contexte.save()
        return suivi
    }

    private func inserer(_ suivi: Suivi) -> Suivi {
        contexte.insert(suivi)
        return suivi
    }
}
