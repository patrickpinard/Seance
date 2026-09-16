import Foundation

/// La recherche TMDB dont le rattachement a besoin ; `TMDBClient` la fournit, les tests la simulent.
public protocol RechercheTMDB: Sendable {
    func rechercherFilms(_ texte: String, page: Int) async throws -> PageTMDB<FilmResume>
    /// Recherche restreinte à l'année de sortie principale.
    func rechercherFilms(_ texte: String, annee: Int, page: Int) async throws -> PageTMDB<FilmResume>
    func rechercherSeries(_ texte: String, page: Int) async throws -> PageTMDB<SerieResume>
}

extension RechercheTMDB {
    public func rechercherFilms(_ texte: String, annee: Int, page: Int) async throws -> PageTMDB<FilmResume> {
        try await rechercherFilms(texte, page: page)
    }
}

extension TMDBClient: RechercheTMDB {}

public struct ProgrammeRattache: Sendable, Hashable {
    public var programme: ProgrammeTV
    public var candidat: CandidatRattachement?
}

/// Rattache les programmes TV à TMDB (EF-51). Un même titre n'est cherché qu'une fois, même s'il
/// passe plusieurs fois ou d'un jour à l'autre. Sans année, seul un titre TMDB unique est retenu.
public actor RattachementGuide {
    /// Une semaine de sept chaînes compte près de 200 titres : quelques recherches à la fois
    /// raccourcissent l'attente sans approcher la limite de TMDB.
    static let recherchesSimultanees = 6

    struct Requete: Sendable {
        var titre: String
        var type: TypeTitre
        /// Présente pour la seconde recherche, restreinte à l'année de sortie.
        var annee: Int?

        var cle: String {
            "\(type.rawValue)|\(NormalisationTitre.normaliser(titre))|\(annee.map(String.init) ?? "")"
        }
    }

    private let recherche: any RechercheTMDB
    private var candidatsParCle: [String: [CandidatRattachement]] = [:]
    public private(set) var recherchesEnEchec = 0

    public init(recherche: any RechercheTMDB) {
        self.recherche = recherche
    }

    public func rattacher(_ programmes: [ProgrammeTV]) async throws -> [ProgrammeRattache] {
        let requetes = programmes.map { programme in
            Self.type(de: programme).map { Requete(titre: programme.titre, type: $0) }
        }
        try await chercher(requetes.compactMap { $0 })
        var resultat = zip(programmes, requetes).map { programme, requete in
            ProgrammeRattache(programme: programme, candidat: requete.flatMap { programme.rattacher(parmi: connus($0)) })
        }

        // Titre courant (« Le Pari », « Taken ») : les homonymes récents cachent parfois le film
        // diffusé. Une seconde recherche, limitée à son année, le retrouve.
        let secondes: [(Int, Requete)] = resultat.indices.compactMap { i in
            guard resultat[i].candidat == nil, var requete = requetes[i], requete.type == .film,
                  let annee = programmes[i].annee, !connus(requete).isEmpty else { return nil }
            requete.annee = annee
            return (i, requete)
        }
        try await chercher(secondes.map(\.1))
        for (i, requete) in secondes {
            resultat[i].candidat = programmes[i].rattacher(parmi: connus(requete))
        }

        // Une rediffusion sans année reprend le rattachement d'un passage daté du même titre,
        // pourvu qu'il n'y en ait qu'un : « Two Lovers » (2008) mercredi, sans année lundi.
        var dates: [String: [CandidatRattachement]] = [:]
        for (r, requete) in zip(resultat, requetes) {
            guard let candidat = r.candidat, r.programme.annee != nil, let cle = requete?.cle else { continue }
            if dates[cle]?.contains(where: { $0.tmdbID == candidat.tmdbID }) != true {
                dates[cle, default: []].append(candidat)
            }
        }
        for i in resultat.indices where resultat[i].candidat == nil && programmes[i].annee == nil {
            guard let cle = requetes[i]?.cle, let uniques = dates[cle], uniques.count == 1 else { continue }
            resultat[i].candidat = uniques[0]
        }
        return resultat
    }

    private static func type(de programme: ProgrammeTV) -> TypeTitre? {
        switch programme.nature {
        case .film: .film
        case .serie: .serie
        case .autre: nil
        }
    }

    private func connus(_ requete: Requete) -> [CandidatRattachement] {
        candidatsParCle[requete.cle] ?? []
    }

    private func chercher(_ requetes: [Requete]) async throws {
        var vues = Set<String>()
        var reste = requetes.filter { candidatsParCle[$0.cle] == nil && vues.insert($0.cle).inserted }[...]
        let recherche = self.recherche
        try await withThrowingTaskGroup(of: (Requete, [CandidatRattachement]?).self) { groupe in
            for _ in 0..<Self.recherchesSimultanees {
                guard let requete = reste.popFirst() else { break }
                groupe.addTask { (requete, try await Self.trouver(requete, avec: recherche)) }
            }
            while let (requete, trouves) = try await groupe.next() {
                if let trouves {
                    candidatsParCle[requete.cle] = trouves
                } else {
                    recherchesEnEchec += 1
                }
                if let suivante = reste.popFirst() {
                    groupe.addTask { (suivante, try await Self.trouver(suivante, avec: recherche)) }
                }
            }
        }
    }

    /// `nil` quand la recherche échoue : un titre introuvable ne doit pas empêcher de rattacher
    /// les autres ; il sera retenté à la prochaine lecture du guide.
    private static func trouver(_ requete: Requete, avec recherche: any RechercheTMDB) async throws -> [CandidatRattachement]? {
        do {
            switch (requete.type, requete.annee) {
            case (.film, let annee?):
                return try await recherche.rechercherFilms(requete.titre, annee: annee, page: 1).resultats.map(\.candidat)
            case (.film, nil):
                return try await recherche.rechercherFilms(requete.titre, page: 1).resultats.map(\.candidat)
            case (.serie, _):
                return try await recherche.rechercherSeries(requete.titre, page: 1).resultats.map(\.candidat)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }
}
