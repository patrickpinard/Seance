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

    /// Trois passes complémentaires : les genres préférés, les acteurs suivis, puis une passe
    /// large qui évite d'enfermer Patrick dans ce qu'il a déjà aimé.
    public func candidats(
        pour demande: DemandeCeSoir, profil: ProfilGouts, contexte: Contexte, maximum: Int = ClientClaude.candidatsMax
    ) async throws -> [CandidatSuggestion] {
        var criteres = criteresBase(demande, profil, contexte)
        var resumes: [TitreResume] = []

        let genres = Array(profil.genresPreferes.prefix(3))
        if !genres.isEmpty {
            criteres.genresInclus = genres
            resumes += try await titres(criteres, demande.type)
        }

        let acteurs = Array(profil.acteursPreferes.prefix(3))
        if !acteurs.isEmpty, demande.type != .serie {
            var parActeurs = criteresBase(demande, profil, contexte)
            parActeurs.acteurs = acteurs
            parActeurs.combinaisonPersonnes = .auMoinsUn
            // Une passe qui peut ne rien donner : elle ne doit pas faire échouer la demande.
            resumes += (try? await titres(parActeurs, .film)) ?? []
        }

        var large = criteresBase(demande, profil, contexte)
        large.genresInclus = []
        resumes += try await titres(large, demande.type)

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

    func criteresBase(_ demande: DemandeCeSoir, _ profil: ProfilGouts, _ contexte: Contexte) -> CriteresDecouverte {
        var criteres = CriteresDecouverte()
        criteres.region = region
        criteres.votesMin = votesMin
        criteres.tri = .popularite
        criteres.genresExclus = Array(profil.genresEvites.prefix(4))
        criteres.dureeMax = demande.dureeMaxMinutes
        if !contexte.abonnements.isEmpty {
            criteres.fournisseurs = contexte.abonnements
            criteres.monetisations = [.abonnement, .gratuit, .avecPublicite]
        }
        return criteres
    }

    /// TMDB sépare films et séries : une demande sans préférence interroge les deux.
    func titres(_ criteres: CriteresDecouverte, _ type: TypeTitre?) async throws -> [TitreResume] {
        switch type {
        case .film:
            return try await client.decouvrirFilms(criteres).resultats.map(\.titreResume)
        case .serie:
            return try await client.decouvrirSeries(criteres).resultats.map(\.titreResume)
        case nil:
            async let films = client.decouvrirFilms(criteres)
            async let series = client.decouvrirSeries(criteres)
            return try await films.resultats.map(\.titreResume) + series.resultats.map(\.titreResume)
        }
    }
}
