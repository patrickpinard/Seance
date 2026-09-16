import Foundation

/// La recherche TMDB dont le rattachement a besoin ; `TMDBClient` la fournit, les tests la simulent.
public protocol RechercheTMDB: Sendable {
    func rechercherFilms(_ texte: String, page: Int) async throws -> PageTMDB<FilmResume>
    func rechercherSeries(_ texte: String, page: Int) async throws -> PageTMDB<SerieResume>
}

extension TMDBClient: RechercheTMDB {}

public struct ProgrammeRattache: Sendable, Hashable {
    public var programme: ProgrammeTV
    public var candidat: CandidatRattachement?
}

/// Rattache les programmes TV à TMDB (EF-51). Un même titre n'est cherché qu'une fois, même s'il
/// passe plusieurs fois ou d'un jour à l'autre ; un programme sans année n'est pas cherché, puisqu'il
/// ne peut pas être rattaché avec certitude.
public actor RattachementGuide {
    private let recherche: any RechercheTMDB
    private var candidatsParTitre: [String: [CandidatRattachement]] = [:]
    public private(set) var recherchesEnEchec = 0

    public init(recherche: any RechercheTMDB) {
        self.recherche = recherche
    }

    public func rattacher(_ programmes: [ProgrammeTV]) async throws -> [ProgrammeRattache] {
        var resultat: [ProgrammeRattache] = []
        for programme in programmes {
            try Task.checkCancellation()
            resultat.append(ProgrammeRattache(programme: programme, candidat: try await rattacher(programme)))
        }
        return resultat
    }

    private func rattacher(_ programme: ProgrammeTV) async throws -> CandidatRattachement? {
        let type: TypeTitre
        switch programme.nature {
        case .film: type = .film
        case .serie: type = .serie
        case .autre: return nil
        }
        guard programme.annee != nil else { return nil }
        let candidats = try await candidats(pour: programme.titre, type: type)
        return programme.rattacher(parmi: candidats)
    }

    private func candidats(pour titre: String, type: TypeTitre) async throws -> [CandidatRattachement] {
        let cle = "\(type.rawValue)|\(NormalisationTitre.normaliser(titre))"
        if let connus = candidatsParTitre[cle] { return connus }
        let trouves: [CandidatRattachement]
        do {
            switch type {
            case .film: trouves = try await recherche.rechercherFilms(titre, page: 1).resultats.map(\.candidat)
            case .serie: trouves = try await recherche.rechercherSeries(titre, page: 1).resultats.map(\.candidat)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Un titre introuvable ne doit pas empêcher de rattacher les autres ; il sera retenté demain.
            recherchesEnEchec += 1
            return []
        }
        candidatsParTitre[cle] = trouves
        return trouves
    }
}
