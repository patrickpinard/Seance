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

    /// Le prochain épisode à regarder sans charger les saisons (EF-12) : celui qui suit le dernier vu,
    /// d'après le nombre d'épisodes de chaque saison. Disponible s'il est déjà diffusé, d'après le
    /// dernier épisode diffusé annoncé par TMDB. `nil` quand tout ce qui existe a été vu.
    public static func suivant(
        vus: Set<NumeroEpisode>, saisons: [SaisonResume], dernierDiffuse: EpisodeTMDB?
    ) -> (numero: NumeroEpisode, disponible: Bool)? {
        let reelles = saisons.filter { $0.numero > 0 && $0.nombreEpisodes > 0 }.sorted { $0.numero < $1.numero }
        let candidat: NumeroEpisode?
        if let dernierVu = vus.filter({ $0.saison > 0 }).max() {
            if let saison = reelles.first(where: { $0.numero == dernierVu.saison }), dernierVu.episode < saison.nombreEpisodes {
                candidat = NumeroEpisode(saison: dernierVu.saison, episode: dernierVu.episode + 1)
            } else {
                candidat = reelles.first { $0.numero > dernierVu.saison }.map { NumeroEpisode(saison: $0.numero, episode: 1) }
            }
        } else {
            candidat = reelles.first.map { NumeroEpisode(saison: $0.numero, episode: 1) }
        }
        guard let candidat else { return nil }
        let disponible = dernierDiffuse.map { candidat <= $0.numeroEpisode } ?? false
        return (candidat, disponible)
    }

    /// Nombre d'épisodes connus, saisons spéciales exclues.
    public static func total(_ saisons: [SaisonResume]) -> Int {
        saisons.filter { $0.numero > 0 }.reduce(0) { $0 + $1.nombreEpisodes }
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
