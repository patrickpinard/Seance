import Foundation

/// Sous-genres proposés dans les filtres (EF-53) : des mots-clés TMDB regroupés sous un nom parlant.
public struct SousGenre: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let nom: String
    public let motsCles: [Int]

    /// Identifiants vérifiés avec `search/keyword` le 16 septembre 2026.
    public static let catalogue: [SousGenre] = [
        SousGenre(id: "artsMartiaux", nom: "Arts martiaux", motsCles: [779, 780]),
        SousGenre(id: "braquage", nom: "Braquage", motsCles: [10051, 15363]),
        SousGenre(id: "espionnage", nom: "Espionnage", motsCles: [470, 5265]),
        SousGenre(id: "survie", nom: "Survie", motsCles: [10349]),
        SousGenre(id: "tueurAGages", nom: "Tueur à gages", motsCles: [2708, 782]),
        SousGenre(id: "vengeance", nom: "Vengeance", motsCles: [9748]),
        SousGenre(id: "poursuites", nom: "Poursuites", motsCles: [382_327]),
        SousGenre(id: "commando", nom: "Forces spéciales", motsCles: [15218, 3070]),
        SousGenre(id: "seulContreTous", nom: "Seul contre tous", motsCles: [13116]),
        SousGenre(id: "evasion", nom: "Évasion", motsCles: [9777]),
        SousGenre(id: "postApo", nom: "Post-apocalyptique", motsCles: [4458, 4565]),
        SousGenre(id: "tueurEnSerie", nom: "Tueur en série", motsCles: [10714]),
        SousGenre(id: "superHeros", nom: "Super-héros", motsCles: [9715]),
        SousGenre(id: "cyberpunk", nom: "Cyberpunk", motsCles: [12190]),
    ]
}

/// Une personne retenue dans les filtres, avec de quoi afficher sa puce.
public struct PersonneFiltre: Sendable, Hashable, Codable, Identifiable {
    public let id: Int
    public let nom: String
    public let cheminPortrait: String?
    /// Un réalisateur se cherche dans l'équipe technique (`with_crew`), pas dans la distribution.
    public var estRealisateur = false

    public init(id: Int, nom: String, cheminPortrait: String?, estRealisateur: Bool = false) {
        self.id = id
        self.nom = nom
        self.cheminPortrait = cheminPortrait
        self.estRealisateur = estRealisateur
    }
}

/// Tous les réglages d'Explorer (EF-52 à EF-59) : ce que TMDB filtre, et ce que l'app filtre ensuite.
public struct FiltresExplorer: Sendable, Hashable, Codable {
    public var type: TypeTitre = .film
    public var genresInclus: [Int] = []
    public var genresExclus: [Int] = []
    public var sousGenres: [String] = []
    public var personnes: [PersonneFiltre] = []
    /// Toutes les personnes ensemble, ou au moins une.
    public var personnesEnsemble = true
    public var anneeDebut: Int?
    public var anneeFin: Int?
    /// Films seulement.
    public var typesSortie: [TypeSortie] = []
    public var noteMin: Double?
    public var votesMin: Int?
    public var dureeMax: Int?
    public var langue: String?
    public var mesPlateformes = false
    public var monetisations: [CriteresDecouverte.Monetisation] = []
    public var tri: CriteresDecouverte.Tri = .popularite
    public var decroissant = true
    public var locaux = FiltresLocaux()

    public init(type: TypeTitre = .film) {
        self.type = type
        // La règle de langue vaut pour les suggestions (EF-28) : Explorer montre tout.
        locaux.regleLangue = false
    }

    /// Langue originale « français ou anglais », comprise telle quelle par TMDB.
    public static let francaisOuAnglais = "fr|en"

    /// Explorer à l'ouverture : ce qui est regardable, en français ou en anglais, sur les plateformes cochées.
    /// Chaque critère est une puce qu'une croix retire ; « Réinitialiser » enlève tout.
    public static func parDefaut(type: TypeTitre = .film, avecPlateformes: Bool) -> FiltresExplorer {
        var filtres = FiltresExplorer(type: type)
        filtres.langue = francaisOuAnglais
        filtres.mesPlateformes = avecPlateformes
        return filtres
    }

    /// Identifiant d'un critère actif, pour sa puce et sa croix (EF-54).
    public enum Critere: Hashable, Sendable {
        case genre(Int)
        case genreExclu(Int)
        case sousGenre(String)
        case personne(Int)
        case periode
        case typesSortie
        case note
        case votes
        case duree
        case langue
        case plateformes
        case monetisation
        case obtention
        case tele
        case dejaVu
    }

    /// Critères actifs, dans l'ordre des puces. Le tri n'est pas un filtre et n'y figure pas.
    public var criteresActifs: [Critere] {
        var liste: [Critere] = personnes.map { .personne($0.id) }
        liste += genresInclus.map { .genre($0) }
        liste += genresExclus.map { .genreExclu($0) }
        liste += sousGenres.map { .sousGenre($0) }
        if anneeDebut != nil || anneeFin != nil { liste.append(.periode) }
        if type == .film, !typesSortie.isEmpty { liste.append(.typesSortie) }
        if noteMin != nil { liste.append(.note) }
        if votesMin != nil { liste.append(.votes) }
        if dureeMax != nil { liste.append(.duree) }
        if langue != nil { liste.append(.langue) }
        if mesPlateformes { liste.append(.plateformes) }
        if !monetisations.isEmpty { liste.append(.monetisation) }
        if locaux.obtention != .tous { liste.append(.obtention) }
        if locaux.tele != .indifferent { liste.append(.tele) }
        if locaux.dejaVu != .tous { liste.append(.dejaVu) }
        return liste
    }

    public mutating func retirer(_ critere: Critere) {
        switch critere {
        case .genre(let id): genresInclus.removeAll { $0 == id }
        case .genreExclu(let id): genresExclus.removeAll { $0 == id }
        case .sousGenre(let id): sousGenres.removeAll { $0 == id }
        case .personne(let id): personnes.removeAll { $0.id == id }
        case .periode: anneeDebut = nil; anneeFin = nil
        case .typesSortie: typesSortie = []
        case .note: noteMin = nil
        case .votes: votesMin = nil
        case .duree: dureeMax = nil
        case .langue: langue = nil
        case .plateformes: mesPlateformes = false
        case .monetisation: monetisations = []
        case .obtention: locaux.obtention = .tous
        case .tele: locaux.tele = .indifferent
        case .dejaVu: locaux.dejaVu = .tous
        }
    }

    /// Genre : neutre → inclus → exclu → neutre.
    public mutating func basculer(genre id: Int) {
        if genresInclus.contains(id) {
            genresInclus.removeAll { $0 == id }
        } else if genresExclus.contains(id) {
            genresExclus.removeAll { $0 == id }
        } else {
            genresInclus.append(id)
        }
    }

    /// Appui long : exclut directement, ou retire l'exclusion.
    public mutating func exclure(genre id: Int) {
        genresInclus.removeAll { $0 == id }
        if genresExclus.contains(id) {
            genresExclus.removeAll { $0 == id }
        } else {
            genresExclus.append(id)
        }
    }

    /// Les critères que l'app applique elle-même, après TMDB (EF-59).
    public var filtresAppActifs: Bool {
        locaux.obtention != .tous || locaux.tele != .indifferent || locaux.dejaVu != .tous || personnesParFilmographie
    }

    /// TMDB ne filtre pas les séries par personne : l'app passe alors par leurs filmographies.
    public var personnesParFilmographie: Bool {
        type == .serie && !personnes.isEmpty
    }

    /// Paramètres de `discover`. Changer de type garde les critères communs, mais les genres
    /// n'ont pas les mêmes identifiants : l'écran les vide au changement.
    public func criteres(abonnements: [Int], page: Int = 1) -> CriteresDecouverte {
        var c = CriteresDecouverte()
        c.genresInclus = genresInclus
        c.genresExclus = genresExclus
        c.motsCles = SousGenre.catalogue.filter { sousGenres.contains($0.id) }.flatMap(\.motsCles)
        if type == .film {
            c.acteurs = personnes.filter { !$0.estRealisateur }.map(\.id)
            c.realisateurs = personnes.filter(\.estRealisateur).map(\.id)
            c.combinaisonPersonnes = personnesEnsemble ? .tous : .auMoinsUn
            c.typesSortie = typesSortie
        }
        c.sortieDepuis = anneeDebut.map { DateTMDB(annee: $0, mois: 1, jour: 1) }
        c.sortieJusqua = anneeFin.map { DateTMDB(annee: $0, mois: 12, jour: 31) }
        c.noteMin = noteMin
        c.votesMin = votesMin
        c.dureeMax = dureeMax
        c.langueOriginale = langue
        if mesPlateformes { c.fournisseurs = abonnements }
        c.monetisations = monetisations
        if mesPlateformes && monetisations.isEmpty { c.monetisations = [.abonnement, .gratuit, .avecPublicite] }
        c.tri = tri
        c.decroissant = decroissant
        c.page = page
        return c
    }

    /// Applique aux crédits d'une filmographie les critères que TMDB aurait appliqués à `discover`.
    public func retient(_ credit: CreditPersonne) -> Bool {
        guard credit.type == type else { return false }
        if !genresInclus.isEmpty, Set(genresInclus).isDisjoint(with: credit.genres) { return false }
        if !Set(genresExclus).isDisjoint(with: credit.genres) { return false }
        let annee = credit.date?.annee
        if let anneeDebut, (annee ?? .min) < anneeDebut { return false }
        if let anneeFin, (annee ?? .max) > anneeFin { return false }
        if let noteMin, (credit.noteMoyenne ?? 0) < noteMin { return false }
        if let votesMin, (credit.nombreVotes ?? 0) < votesMin { return false }
        if let langue, credit.langueOriginale != langue { return false }
        return true
    }
}

extension CreditPersonne {
    public var titreResume: TitreResume {
        TitreResume(reference: reference, titre: titre, titreOriginal: titreOriginal, langueOriginale: langueOriginale,
                    synopsis: "", genres: genres, cheminAffiche: cheminAffiche, cheminFond: nil,
                    noteMoyenne: noteMoyenne ?? 0, nombreVotes: nombreVotes ?? 0, date: date)
    }
}

/// Raccourcis de période de la maquette : années 90, 2000, 2010, cette année.
public struct RaccourciPeriode: Sendable, Hashable, Identifiable {
    public let nom: String
    public let debut: Int
    public let fin: Int

    public var id: String { nom }

    public static func catalogue(anneeCourante: Int) -> [RaccourciPeriode] {
        [
            RaccourciPeriode(nom: "Années 80", debut: 1980, fin: 1989),
            RaccourciPeriode(nom: "Années 90", debut: 1990, fin: 1999),
            RaccourciPeriode(nom: "Années 2000", debut: 2000, fin: 2009),
            RaccourciPeriode(nom: "Années 2010", debut: 2010, fin: 2019),
            RaccourciPeriode(nom: "Années 2020", debut: 2020, fin: anneeCourante),
            RaccourciPeriode(nom: "Cette année", debut: anneeCourante, fin: anneeCourante),
        ]
    }
}
