import Foundation

/// Réunit les candidats du soir avec TMDB (EF-23) : dans les abonnements de Patrick,
/// en français ou en anglais (EF-28), pas encore vus, ni exclus, ni écartés hier soir.
public struct CollecteurCandidats: Sendable {
    /// Ce que le magasin de l'app sait déjà, et que TMDB ignore.
    public struct Contexte: Sendable {
        public var abonnements: [Int]
        public var dejaVus: Set<ReferenceTitre>
        /// « Jamais » et « Ni VF ni sous-titres FR » (EF-26, EF-29).
        public var exclus: Set<ReferenceTitre>
        /// « Pas ce soir » : écarté jusqu'à demain.
        public var reportes: Set<ReferenceTitre>

        public init(
            abonnements: [Int] = [], dejaVus: Set<ReferenceTitre> = [],
            exclus: Set<ReferenceTitre> = [], reportes: Set<ReferenceTitre> = []
        ) {
            self.abonnements = abonnements
            self.dejaVus = dejaVus
            self.exclus = exclus
            self.reportes = reportes
        }
    }

    public let client: TMDBClient
    public var region: String
    public var votesMin: Int

    public init(client: TMDBClient, region: String = "CH", votesMin: Int = 50) {
        self.client = client
        self.region = region
        self.votesMin = votesMin
    }

    /// Quand la phrase nomme un genre (« un film de guerre »), toutes les passes s'y tiennent :
    /// la demande l'emporte sur le profil. Sinon, trois passes complémentaires : les genres préférés,
    /// les acteurs suivis, puis une passe large qui évite d'enfermer Patrick dans ce qu'il a déjà aimé.
    public func candidats(
        pour demande: DemandeCeSoir, profil: ProfilGouts, contexte: Contexte, maximum: Int = ClientClaude.candidatsMax
    ) async throws -> [CandidatSuggestion] {
        let envie = demande.interpretation
        let type = demande.typeEffectif
        var resumes: [TitreResume] = []

        if envie.aDesGenres {
            resumes += try await titres(type) { t in
                var criteres = criteresBase(demande, profil, contexte, type: t)
                criteres.genresInclus = envie.genres(pour: t)
                return criteres.genresInclus.isEmpty ? nil : criteres
            }
            // Les mieux notés du même genre, pour ne pas s'en tenir aux plus populaires.
            resumes += try await titres(type) { t in
                var criteres = criteresBase(demande, profil, contexte, type: t)
                criteres.genresInclus = envie.genres(pour: t)
                criteres.tri = .note
                criteres.votesMin = max(votesMin, 300)
                return criteres.genresInclus.isEmpty ? nil : criteres
            }
        } else {
            let genres = Array(profil.genresPreferes.prefix(3))
            if !genres.isEmpty {
                resumes += try await titres(type) { t in
                    var criteres = criteresBase(demande, profil, contexte, type: t)
                    criteres.genresInclus = genres
                    return criteres
                }
            }
        }

        let acteurs = Array(profil.acteursPreferes.prefix(3))
        if !acteurs.isEmpty, type != .serie, !envie.aDesGenres || !envie.genresFilms.isEmpty {
            var parActeurs = criteresBase(demande, profil, contexte, type: .film)
            parActeurs.acteurs = acteurs
            parActeurs.combinaisonPersonnes = .auMoinsUn
            parActeurs.genresInclus = envie.genresFilms
            // Une passe qui peut ne rien donner : elle ne doit pas faire échouer la demande.
            resumes += (try? await client.decouvrirFilms(parActeurs).resultats.map(\.titreResume)) ?? []
        }

        if !envie.aDesGenres {
            resumes += try await titres(type) { t in
                criteresBase(demande, profil, contexte, type: t)
            }
        }

        var vues = Set<ReferenceTitre>()
        return resumes
            .filter { resume in
                guard vues.insert(resume.reference).inserted else { return false }
                guard !contexte.dejaVus.contains(resume.reference),
                      !contexte.exclus.contains(resume.reference),
                      !contexte.reportes.contains(resume.reference) else { return false }
                return RegleLangue.accepte(langueOriginale: resume.langueOriginale, exclu: false)
            }
            .prefix(maximum)
            .map { CandidatSuggestion(titre: $0) }
    }

    func criteresBase(_ demande: DemandeCeSoir, _ profil: ProfilGouts, _ contexte: Contexte, type: TypeTitre) -> CriteresDecouverte {
        var criteres = CriteresDecouverte()
        criteres.region = region
        criteres.votesMin = votesMin
        criteres.tri = .popularite
        var exclus = demande.interpretation.genresExclus(pour: type)
        for genre in profil.genresEvites.prefix(4) where !exclus.contains(genre) {
            exclus.append(genre)
        }
        criteres.genresExclus = exclus
        criteres.dureeMax = demande.dureeMaxEffective
        if !contexte.abonnements.isEmpty {
            criteres.fournisseurs = contexte.abonnements
            criteres.monetisations = [.abonnement, .gratuit, .avecPublicite]
        }
        return criteres
    }

    /// TMDB sépare films et séries, et leurs genres n'ont pas les mêmes identifiants : chaque type
    /// reçoit ses propres critères. Une demande sans préférence interroge les deux.
    func titres(_ type: TypeTitre?, _ criteres: (TypeTitre) -> CriteresDecouverte?) async throws -> [TitreResume] {
        let pourFilms = type != .serie ? criteres(.film) : nil
        let pourSeries = type != .film ? criteres(.serie) : nil
        async let films = films(pourFilms)
        async let series = series(pourSeries)
        return try await films + series
    }

    private func films(_ criteres: CriteresDecouverte?) async throws -> [TitreResume] {
        guard let criteres else { return [] }
        return try await client.decouvrirFilms(criteres).resultats.map(\.titreResume)
    }

    private func series(_ criteres: CriteresDecouverte?) async throws -> [TitreResume] {
        guard let criteres else { return [] }
        return try await client.decouvrirSeries(criteres).resultats.map(\.titreResume)
    }
}
