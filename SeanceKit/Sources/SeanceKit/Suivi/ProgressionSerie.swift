import Foundation

/// Où en est Patrick dans une série (EF-12, EF-13).
public enum EtatSerie: Sendable, Equatable {
    /// Un épisode déjà diffusé attend d'être regardé.
    case aSuivre(EpisodeTMDB)
    /// Tout ce qui est diffusé a été vu ; la suite est annoncée ou la série continue.
    case enAttente(prochaineDiffusion: DateTMDB?)
    /// Tout a été vu et la série est terminée ou annulée.
    case terminee
}

public enum ProgressionSerie {
    /// Statuts TMDB d'une série qui n'aura plus d'épisodes.
    static let statutsFinaux: Set<String> = ["Ended", "Canceled"]

    /// - Parameters:
    ///   - episodes: les épisodes connus, toutes saisons confondues ; les épisodes spéciaux (saison 0) sont ignorés.
    ///   - vus: les épisodes déjà cochés.
    ///   - serie: la fiche, pour le prochain épisode annoncé et le statut.
    public static func etat(
        episodes: [EpisodeTMDB],
        vus: Set<NumeroEpisode>,
        serie: SerieDetail?,
        aujourdhui: DateTMDB
    ) -> EtatSerie {
        let ordonnes = episodesOrdonnes(episodes)
        if let prochain = ordonnes.first(where: { !vus.contains($0.numeroEpisode) }) {
            if let diffusion = prochain.dateDiffusion, diffusion <= aujourdhui {
                return .aSuivre(prochain)
            }
            return .enAttente(prochaineDiffusion: prochain.dateDiffusion)
        }
        if let annonce = serie?.prochainEpisode {
            return .enAttente(prochaineDiffusion: annonce.dateDiffusion)
        }
        if let statut = serie?.statut, statutsFinaux.contains(statut) {
            return .terminee
        }
        return .enAttente(prochaineDiffusion: nil)
    }

    /// Tous les épisodes jusqu'à la cible incluse, pour « cocher jusqu'ici » (EF-11).
    public static func episodes(jusqua cible: NumeroEpisode, parmi episodes: [EpisodeTMDB]) -> [EpisodeTMDB] {
        episodesOrdonnes(episodes).filter { $0.numeroEpisode <= cible }
    }

    static func episodesOrdonnes(_ episodes: [EpisodeTMDB]) -> [EpisodeTMDB] {
        episodes.filter { $0.saison > 0 }.sorted { $0.numeroEpisode < $1.numeroEpisode }
    }
}

extension EpisodeTMDB {
    public var numeroEpisode: NumeroEpisode {
        NumeroEpisode(saison: saison, episode: numero)
    }
}
