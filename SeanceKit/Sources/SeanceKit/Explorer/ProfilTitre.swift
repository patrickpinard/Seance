import Foundation

/// Ce qu'il faut savoir d'un titre pour lui appliquer tous les critères d'Explorer sans `discover`.
///
/// Quand les résultats partent d'une liste locale (films du NAS, programmes TV, titres vus), TMDB ne
/// peut pas filtrer : l'app lit la fiche de chaque titre et applique elle-même les critères (EF-59).
public struct ProfilTitre: Sendable, Hashable {
    public var resume: TitreResume
    public var motsCles: Set<Int>
    public var acteurs: Set<Int>
    public var realisateurs: Set<Int>
    /// Durée d'un film, ou d'un épisode pour une série.
    public var dureeMinutes: Int?
    public var offres: OffresRegion?
    /// Films seulement : types de sortie connus dans la région.
    public var typesSortie: Set<TypeSortie>

    public init(film: FicheFilm, region: String = "CH") {
        resume = TitreResume(
            reference: film.reference, titre: film.titre, titreOriginal: film.titreOriginal, langueOriginale: film.langueOriginale,
            synopsis: film.synopsis, genres: film.genres.map(\.id), cheminAffiche: film.cheminAffiche, cheminFond: film.cheminFond,
            noteMoyenne: film.noteMoyenne, nombreVotes: film.nombreVotes, date: film.dateSortie
        )
        motsCles = Set(film.motsCles?.ids ?? [])
        acteurs = Set(film.casting?.acteurs.map(\.id) ?? [])
        realisateurs = Set(film.casting?.realisateurs.map(\.id) ?? [])
        dureeMinutes = film.dureeMinutes
        offres = film.fournisseurs?.offres(region: region)
        typesSortie = Set(film.datesDeSortie?.sorties(region: region).compactMap(\.type) ?? [])
    }

    public init(serie: SerieDetail, region: String = "CH") {
        resume = TitreResume(
            reference: serie.reference, titre: serie.nom, titreOriginal: serie.nomOriginal, langueOriginale: serie.langueOriginale,
            synopsis: serie.synopsis, genres: serie.genres.map(\.id), cheminAffiche: serie.cheminAffiche, cheminFond: serie.cheminFond,
            noteMoyenne: serie.noteMoyenne, nombreVotes: serie.nombreVotes, date: serie.premiereDiffusion
        )
        motsCles = Set(serie.motsCles?.ids ?? [])
        acteurs = Set(serie.casting?.acteurs.map(\.id) ?? [])
        realisateurs = []
        dureeMinutes = serie.dureesEpisode.min()
        offres = serie.fournisseurs?.offres(region: region)
        typesSortie = []
    }
}

extension FiltresExplorer {
    /// Les critères TMDB, appliqués par l'app avec la même logique que `discover`.
    public func retient(_ profil: ProfilTitre, abonnements: [Int]) -> Bool {
        let titre = profil.resume
        guard titre.reference.type == type else { return false }

        // Genres et mots-clés : au moins un (barre verticale chez TMDB).
        if !genresInclus.isEmpty, Set(genresInclus).isDisjoint(with: titre.genres) { return false }
        if !Set(genresExclus).isDisjoint(with: titre.genres) { return false }
        let motsClesVoulus = Set(SousGenre.catalogue.filter { sousGenres.contains($0.id) }.flatMap(\.motsCles))
        if !motsClesVoulus.isEmpty, motsClesVoulus.isDisjoint(with: profil.motsCles) { return false }

        if !personnes.isEmpty {
            let presentes = personnes.map { personne in
                personne.estRealisateur && type == .film
                    ? profil.realisateurs.contains(personne.id)
                    : profil.acteurs.contains(personne.id)
            }
            if personnesEnsemble ? presentes.contains(false) : !presentes.contains(true) { return false }
        }

        let annee = titre.date?.annee
        if let anneeDebut, (annee ?? .min) < anneeDebut { return false }
        if let anneeFin, (annee ?? .max) > anneeFin { return false }
        if type == .film, !typesSortie.isEmpty, Set(typesSortie).isDisjoint(with: profil.typesSortie) { return false }
        if let noteMin, titre.noteMoyenne < noteMin { return false }
        if let votesMin, titre.nombreVotes < votesMin { return false }
        if let dureeMax, (profil.dureeMinutes ?? .max) > dureeMax { return false }
        // « fr|en » est la syntaxe de TMDB pour « français ou anglais » : ici, c'est l'app qui compare.
        if let langue, !langue.split(separator: "|").map(String.init).contains(titre.langueOriginale ?? "") { return false }

        if mesPlateformes || !monetisations.isEmpty {
            let types = monetisations.isEmpty ? [CriteresDecouverte.Monetisation.abonnement, .gratuit, .avecPublicite] : monetisations
            let fournisseurs = Set(types.flatMap { offres(profil.offres, $0) }.map(\.id))
            let retenus = mesPlateformes ? fournisseurs.intersection(abonnements) : fournisseurs
            if retenus.isEmpty { return false }
        }
        return true
    }

    private func offres(_ offres: OffresRegion?, _ type: CriteresDecouverte.Monetisation) -> [Fournisseur] {
        guard let offres else { return [] }
        switch type {
        case .abonnement: return offres.abonnement
        case .gratuit: return offres.gratuit
        case .avecPublicite: return offres.avecPublicite
        case .location: return offres.location
        case .achat: return offres.achat
        }
    }

    /// Les filtres dont la liste de départ est locale : NAS, télé, titres vus. Parcourir les pages
    /// de `discover` pour les retrouver serait long et incomplet.
    public var partDUneListeLocale: Bool {
        locaux.obtention == .surNAS || locaux.tele != .indifferent || locaux.dejaVu == .vus
    }

    /// Trie des titres comme TMDB le ferait.
    public func trier(_ titres: [TitreResume]) -> [TitreResume] {
        let croissant = !decroissant
        return titres.sorted { a, b in
            let avant: Bool
            switch tri {
            case .popularite, .votes: avant = a.nombreVotes > b.nombreVotes
            case .note: avant = a.noteMoyenne > b.noteMoyenne
            case .date: avant = (a.date?.description ?? "") > (b.date?.description ?? "")
            case .titre: avant = a.titre.localizedStandardCompare(b.titre) == .orderedDescending
            }
            return avant != croissant
        }
    }
}
