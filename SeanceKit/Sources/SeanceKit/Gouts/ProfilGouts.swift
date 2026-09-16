import Foundation

/// Un signal de goût : un intérêt coché au premier lancement (EF-60), une note donnée
/// (EF-61, EF-66) ou un titre regardé (EF-14, EF-15).
public struct ObservationGout: Sendable, Hashable {
    public enum Origine: Sendable, Hashable {
        /// Coché sur la grille illustrée : une préférence déclarée, sans date.
        case interetDeclare
        /// De 1 à 10. Le signal le plus sûr, et le seul qui puisse être négatif.
        case note(Int)
        /// Un film vu ou un épisode coché, sans note : positif, mais faible.
        case visionnage
        /// « Jamais » : Patrick a écarté ce titre pour de bon (EF-26).
        case rejet
    }

    public var origine: Origine
    public var genres: [Int]
    public var acteurs: [Int]
    /// Noms des acteurs cités, pour les phrases d'explication.
    public var nomsActeurs: [Int: String]
    public var type: TypeTitre?
    public var dureeMinutes: Int?
    /// Quand le signal a été émis ; `nil` vaut « aujourd'hui ».
    public var date: Date?
    /// Poids du signal : celui de l'intérêt coché (EF-60), ou le nombre d'épisodes d'une série
    /// ramené à une échelle de 1 à 2, pour qu'une série dévorée pèse plus qu'un épisode isolé.
    public var poids: Double

    public init(
        origine: Origine, genres: [Int] = [], acteurs: [Int] = [], nomsActeurs: [Int: String] = [:],
        type: TypeTitre? = nil, dureeMinutes: Int? = nil, date: Date? = nil, poids: Double = 1
    ) {
        self.origine = origine
        self.genres = genres
        self.acteurs = acteurs
        self.nomsActeurs = nomsActeurs
        self.type = type
        self.dureeMinutes = dureeMinutes
        self.date = date
        self.poids = poids
    }

    /// De -1 (rejeté) à 1 (adoré). Une note de 6 sur 10 est neutre.
    var valeur: Double {
        switch origine {
        case .interetDeclare: 1
        case .note(let note): min(1, max(-1, (Double(note) - 6) / 4))
        case .visionnage: 0.4
        case .rejet: -0.8
        }
    }

    /// Ce que le signal pèse avant la décote du temps.
    var force: Double {
        switch origine {
        case .interetDeclare: max(0, poids)
        case .note: max(0, poids)
        case .visionnage: 0.6 * max(0, poids)
        case .rejet: 0.8 * max(0, poids)
        }
    }

    /// Un goût ancien compte moins qu'un goût récent, sans jamais disparaître.
    /// Un intérêt coché ne se démode pas : il reste à plein poids.
    func poidsTemps(maintenant: Date, demiVieJours: Double) -> Double {
        guard case .interetDeclare = origine else {
            guard let date, date < maintenant, demiVieJours > 0 else { return 1 }
            let jours = maintenant.timeIntervalSince(date) / 86_400
            return max(0.15, pow(0.5, jours / demiVieJours))
        }
        return 1
    }
}

/// Ce que Séance a compris des goûts de Patrick, à partir de ses intérêts, de ses notes
/// et de ce qu'il a regardé (EF-62). Tout est calculé sur l'iPhone : rien ne sort de l'app.
public struct ProfilGouts: Sendable, Hashable {
    /// Affinité par genre TMDB, de -1 (évité) à 1 (adoré).
    public var genres: [Int: Double] = [:]
    /// Affinité par acteur TMDB, même échelle.
    public var acteurs: [Int: Double] = [:]
    public var nomsActeurs: [Int: String] = [:]
    /// Durée habituelle des films retenus, en minutes.
    public var dureeHabituelleMinutes: Int?
    /// Écart accepté de part et d'autre de cette durée.
    public var ecartDureeMinutes: Int = 30
    /// Part des séries dans les titres regardés : 0 = que des films, 1 = que des séries.
    public var partSeries: Double = 0
    /// Moyenne des notes données, quand Patrick note.
    public var noteMoyenne: Double?
    /// Nombre de signaux retenus.
    public var observations: Int = 0

    public init() {}

    /// Un profil jeune ne doit pas décider seul : sous vingt signaux, il pèse moins.
    public var maturite: Double {
        min(1, Double(observations) / 20)
    }

    public var estVide: Bool {
        genres.isEmpty && acteurs.isEmpty
    }

    public func affinite(genre: Int) -> Double {
        genres[genre] ?? 0
    }

    public func affinite(acteur: Int) -> Double {
        acteurs[acteur] ?? 0
    }

    /// Genres nettement appréciés, du plus au moins.
    public var genresPreferes: [Int] {
        genres.filter { $0.value >= 0.25 }.sorted { classer($0, $1) }.map(\.key)
    }

    /// Genres nettement rejetés : ils sortent des critères d'Explorer et de « Ce soir ».
    public var genresEvites: [Int] {
        genres.filter { $0.value <= -0.25 }.sorted { $0.value < $1.value }.map(\.key)
    }

    public var acteursPreferes: [Int] {
        acteurs.filter { $0.value >= 0.25 }.sorted { classer($0, $1) }.map(\.key)
    }

    public func nom(acteur: Int) -> String {
        nomsActeurs[acteur] ?? "acteur \(acteur)"
    }

    /// Ordre stable : la meilleure affinité d'abord, puis l'identifiant le plus petit.
    private func classer(_ a: (key: Int, value: Double), _ b: (key: Int, value: Double)) -> Bool {
        a.value != b.value ? a.value > b.value : a.key < b.key
    }

    // MARK: - Calcul

    /// Réunit les signaux en un profil. La somme des signaux passe par une tangente
    /// hyperbolique : trois signaux forts suffisent à marquer un goût, et rien ne dépasse 1.
    public static func calculer(
        _ observations: [ObservationGout], maintenant: Date = .now, demiVieJours: Double = 365
    ) -> ProfilGouts {
        var profil = ProfilGouts()
        profil.observations = observations.count
        guard !observations.isEmpty else { return profil }

        var totalGenres: [Int: Double] = [:]
        var totalActeurs: [Int: Double] = [:]
        var notes: [Int] = []
        var dureesRetenues: [Int] = []
        var films = 0
        var episodes = 0

        for observation in observations {
            let poids = observation.force * observation.poidsTemps(maintenant: maintenant, demiVieJours: demiVieJours)
            let apport = observation.valeur * poids
            for genre in observation.genres {
                totalGenres[genre, default: 0] += apport
            }
            for acteur in observation.acteurs {
                totalActeurs[acteur, default: 0] += apport
            }
            profil.nomsActeurs.merge(observation.nomsActeurs) { ancien, _ in ancien }
            if case .note(let note) = observation.origine {
                notes.append(note)
            }
            if case .visionnage = observation.origine {
                switch observation.type {
                case .film: films += 1
                case .serie: episodes += 1
                case nil: break
                }
            }
            if observation.valeur > 0, observation.type == .film, let duree = observation.dureeMinutes, duree > 0 {
                dureesRetenues.append(duree)
            }
        }

        profil.genres = totalGenres.mapValues { tanh($0 / 3) }
        profil.acteurs = totalActeurs.mapValues { tanh($0 / 2) }
        let acteursConnus = profil.acteurs
        profil.nomsActeurs = profil.nomsActeurs.filter { acteursConnus[$0.key] != nil }
        if !notes.isEmpty {
            profil.noteMoyenne = Double(notes.reduce(0, +)) / Double(notes.count)
        }
        if films + episodes > 0 {
            profil.partSeries = Double(episodes) / Double(films + episodes)
        }
        // Nom distinct de la fonction mediane(_:), que la variable masquerait.
        if let valeurMediane = mediane(dureesRetenues) {
            profil.dureeHabituelleMinutes = valeurMediane
            let ecarts = dureesRetenues.map { abs($0 - valeurMediane) }
            profil.ecartDureeMinutes = max(20, mediane(ecarts) ?? 30)
        }
        return profil
    }

    /// Médiane entière ; la moyenne des deux valeurs centrales quand le nombre est pair.
    static func mediane(_ valeurs: [Int]) -> Int? {
        guard !valeurs.isEmpty else { return nil }
        let triees = valeurs.sorted()
        let milieu = triees.count / 2
        return triees.count.isMultiple(of: 2) ? (triees[milieu - 1] + triees[milieu]) / 2 : triees[milieu]
    }
}
