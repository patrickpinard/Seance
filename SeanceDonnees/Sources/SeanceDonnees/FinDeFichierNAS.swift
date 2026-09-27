import Foundation
import SeanceKit
import SwiftData

/// Ce que le lecteur fait au bout d'un film ou d'un épisode du NAS (8.1), le même sur l'iPhone, l'iPad et l'Apple TV :
/// marquer vu sans poser de question, et trouver l'épisode suivant sur le NAS.
@MainActor
public enum FinDeFichierNAS {
    /// Le film ou l'épisode que ce fichier contient ; `nil` pour un fichier que l'analyse n'a pas reconnu.
    public static func lecture(_ fichier: FichierNAS) -> LectureExterne? {
        guard let reference = fichier.reference else { return nil }
        let episode = fichier.saison.flatMap { saison in fichier.episode.map { NumeroEpisode(saison: saison, episode: $0) } }
        if reference.type == .serie, episode == nil { return nil }
        return LectureExterne(reference: reference, titre: fichier.titre, episode: episode, debut: .now)
    }

    /// Marque vu : le film (sa fiche TMDB en donne la durée et les genres), ou l'épisode par son seul numéro.
    /// `false` si c'était déjà fait ou impossible.
    @discardableResult
    public static func marquerVu(_ lecture: LectureExterne, dureeSecondes: Double, contexte: ModelContext,
                                 tmdb: TMDBClient?) async throws -> Bool {
        let service = ServiceSuivi(contexte: contexte)
        switch (lecture.reference.type, lecture.episode) {
        case (.film, _):
            guard let tmdb, try !service.estVu(lecture.reference) else { return false }
            try service.marquerVu(film: try await tmdb.film(lecture.reference.tmdbID, complements: []))
            return true
        case (.serie, let numero?):
            let vu = try service.cocher(numero, serie: lecture.reference, dureeMinutes: max(Int(dureeSecondes / 60), 1))
            if vu, let tmdb, let serie = try? await tmdb.serie(lecture.reference.tmdbID) {
                _ = try? service.rangerSiTerminee(serie)
            }
            return vu
        case (.serie, nil):
            return false
        }
    }

    /// L'épisode qui suit celui-ci et qui est sur le NAS : le suivant de la saison, sinon le premier de la saison
    /// d'après. `nil` pour un film, ou à la fin de ce que le NAS contient.
    public static func episodeSuivant(_ fichier: FichierNAS, contexte: ModelContext) -> FichierNAS? {
        guard fichier.type == .serie, let id = fichier.tmdbID, let saison = fichier.saison, let episode = fichier.episode else { return nil }
        let type = TypeTitre.serie.rawValue
        let tous = (try? contexte.fetch(FetchDescriptor<FichierNAS>(predicate: #Predicate { $0.tmdbID == id && $0.typeBrut == type }))) ?? []
        return tous
            .filter { ($0.saison ?? 0, $0.episode ?? 0) > (saison, episode) && ($0.saison ?? 0) > 0 }
            .min { ($0.saison ?? 0, $0.episode ?? 0) < ($1.saison ?? 0, $1.episode ?? 0) }
    }
}

/// Les actions du menu d'un titre qui doivent faire la même chose sur l'iPhone et sur l'Apple TV (8.2.15).
@MainActor
public enum ActionsCommunes {
    /// « Déjà vu avant » : un film rejoint les vus (hors statistiques) ; une série voit tous ses épisodes déjà diffusés
    /// cochés, et passe dans Terminés — même encore en cours —, ce qui la sort des Nouveautés.
    public static func dejaVuAvant(_ reference: ReferenceTitre, contexte: ModelContext, tmdb: TMDBClient) async throws {
        let suivi = ServiceSuivi(contexte: contexte)
        switch reference.type {
        case .film:
            try suivi.marquerVu(film: try await tmdb.film(reference.tmdbID, complements: [.casting]), anterieur: true)
        case .serie:
            let serie = try await tmdb.serie(reference.tmdbID, complements: [.casting])
            let aujourdhui = DateTMDB(.now)
            var episodes: [EpisodeTMDB] = []
            for saison in serie.saisons where saison.numero > 0 && saison.nombreEpisodes > 0 {
                episodes += try await tmdb.saison(saison.numero, serie: serie.id).episodes
            }
            try Task.checkCancellation()
            try suivi.cocher(episodes.filter { $0.dateDiffusion.map { $0 <= aujourdhui } ?? false }, serie: serie, anterieur: true)
            if let suiviSerie = try suivi.suivi(reference) {
                suiviSerie.statut = .termine
                try contexte.save()
            }
        }
    }
}
