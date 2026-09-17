import Foundation

/// Un titre que Patrick a noté 8 ou plus : TMDB en déduit des titres proches.
public struct TitreAime: Sendable, Hashable {
    public var reference: ReferenceTitre
    public var titre: String
    public var note: Int

    public init(reference: ReferenceTitre, titre: String, note: Int) {
        self.reference = reference
        self.titre = titre
        self.note = note
    }
}

/// Un titre proposé parce qu'il ressemble à un titre aimé.
public struct TitreSimilaire: Sendable, Hashable, Identifiable {
    public var titre: TitreResume
    /// Le titre aimé le mieux noté qui le recommande.
    public var parceQue: TitreAime
    /// Nombre de titres aimés qui le recommandent.
    public var sources: Int

    public var id: ReferenceTitre { titre.reference }

    /// « Comme Heat », ou « Comme Heat et 2 autres ».
    public var phrase: String {
        sources > 1 ? "Comme \(parceQue.titre) et \(sources - 1) autre\(sources > 2 ? "s" : "")" : "Comme \(parceQue.titre)"
    }
}

/// « Parce que tu as aimé… » : les recommandations TMDB des titres notés 8 ou plus, sans ce qui est
/// déjà vu, écarté ou hors des langues regardables (EF-28).
public enum TitresSimilaires {
    public static let noteMinimale = 8

    /// Un titre recommandé par plusieurs titres aimés passe devant ; puis la note du titre aimé,
    /// puis l'ordre de TMDB. Les recommandations d'un même titre aimé restent alternées avec les autres.
    public static func selectionner(
        aimes: [TitreAime],
        recommandations: [ReferenceTitre: [TitreResume]],
        exclus: Set<ReferenceTitre>,
        maximum: Int = 15
    ) -> [TitreSimilaire] {
        let sources = Set(aimes.map(\.reference))
        var parReference: [ReferenceTitre: (similaire: TitreSimilaire, rang: Int)] = [:]
        for aime in aimes.sorted(by: { $0.note > $1.note }) {
            for (rang, titre) in (recommandations[aime.reference] ?? []).enumerated() {
                guard titre.cheminAffiche != nil, !exclus.contains(titre.reference), !sources.contains(titre.reference),
                      RegleLangue.accepte(langueOriginale: titre.langueOriginale, exclu: false) else { continue }
                if var existant = parReference[titre.reference] {
                    existant.similaire.sources += 1
                    existant.rang = min(existant.rang, rang)
                    parReference[titre.reference] = existant
                } else {
                    parReference[titre.reference] = (TitreSimilaire(titre: titre, parceQue: aime, sources: 1), rang)
                }
            }
        }
        return parReference.values
            .sorted { a, b in
                if a.similaire.sources != b.similaire.sources { return a.similaire.sources > b.similaire.sources }
                if a.rang != b.rang { return a.rang < b.rang }
                if a.similaire.parceQue.note != b.similaire.parceQue.note { return a.similaire.parceQue.note > b.similaire.parceQue.note }
                return a.similaire.titre.reference.tmdbID < b.similaire.titre.reference.tmdbID
            }
            .prefix(maximum)
            .map(\.similaire)
    }
}

extension TMDBClient {
    /// Les titres que TMDB rapproche d'un film ou d'une série, du même type.
    public func recommandations(_ reference: ReferenceTitre) async throws -> [TitreResume] {
        switch reference.type {
        case .film:
            let page: PageTMDB<FilmResume> = try await envoyerPublic("/3/movie/\(reference.tmdbID)/recommendations", [])
            return page.resultats.map(\.titreResume)
        case .serie:
            let page: PageTMDB<SerieResume> = try await envoyerPublic("/3/tv/\(reference.tmdbID)/recommendations", [])
            return page.resultats.map(\.titreResume)
        }
    }
}
