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

    /// EF-14 : un film vu, avec sa note facultative.
    public func marquerVu(film: FicheFilm, note: Int? = nil, le date: Date = .now) throws {
        let suivi = try suivre(film: film, statut: .termine)
        let visionnage = Visionnage(reference: film.reference, dureeMinutes: film.dureeMinutes ?? 0, vuLe: date)
        visionnage.note = note
        contexte.insert(visionnage)
        if let note { suivi.note = note }
        try contexte.save()
    }

    /// EF-11 : coche les épisodes donnés, sans doublon ; renvoie le nombre d'épisodes ajoutés.
    @discardableResult
    public func cocher(_ episodes: [EpisodeTMDB], serie: SerieDetail, le date: Date = .now) throws -> Int {
        let dejaVus = try episodesVus(serie.reference)
        let suivi = try suivre(serie: serie, statut: .enCours)
        var ajoutes = 0
        for episode in episodes where episode.saison > 0 && !dejaVus.contains(episode.numeroEpisode) {
            let duree = episode.dureeMinutes ?? serie.dureesEpisode.first ?? 0
            contexte.insert(Visionnage(reference: serie.reference, saison: episode.saison, episode: episode.numero, dureeMinutes: duree, vuLe: date))
            ajoutes += 1
        }
        if suivi.statut == .aVoir { suivi.statut = .enCours }
        try contexte.save()
        return ajoutes
    }

    public func decocher(_ numero: NumeroEpisode, serie: ReferenceTitre) throws {
        for visionnage in try visionnages(serie) where visionnage.saison == numero.saison && visionnage.episode == numero.episode {
            contexte.delete(visionnage)
        }
        try contexte.save()
    }

    /// EF-66 : note d'un épisode déjà vu.
    public func noter(_ numero: NumeroEpisode, serie: ReferenceTitre, note: Int) throws {
        for visionnage in try visionnages(serie) where visionnage.saison == numero.saison && visionnage.episode == numero.episode {
            visionnage.note = note
        }
        try contexte.save()
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
