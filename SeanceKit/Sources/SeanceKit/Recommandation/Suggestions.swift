import Foundation

/// La demande de Patrick : son envie en toutes lettres, et les deux précisions du cahier (EF-22).
public struct DemandeCeSoir: Sendable, Hashable, Codable {
    /// Écrit au clavier ou dicté ; peut rester vide.
    public var envie: String
    /// `nil` = film ou série, peu importe.
    public var type: TypeTitre?
    public var dureeMaxMinutes: Int?

    public init(envie: String = "", type: TypeTitre? = nil, dureeMaxMinutes: Int? = nil) {
        self.envie = envie
        self.type = type
        self.dureeMaxMinutes = dureeMaxMinutes
    }

    public var envieNettoyee: String {
        envie.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Un titre proposé au classement : ce que l'app sait de lui sans ouvrir sa fiche.
public struct CandidatSuggestion: Codable, Sendable, Equatable, Identifiable {
    public var titre: TitreResume
    public var dureeMinutes: Int?
    public var acteurs: [Int]
    public var nomsActeurs: [Int: String]
    /// Renseignée quand l'app a déjà calculé « Où regarder » (EF-73) ; sinon `nil`.
    public var disponibilite: EtatDisponibilite?

    public init(
        titre: TitreResume, dureeMinutes: Int? = nil, acteurs: [Int] = [],
        nomsActeurs: [Int: String] = [:], disponibilite: EtatDisponibilite? = nil
    ) {
        self.titre = titre
        self.dureeMinutes = dureeMinutes
        self.acteurs = acteurs
        self.nomsActeurs = nomsActeurs
        self.disponibilite = disponibilite
    }

    public var reference: ReferenceTitre { titre.reference }
    public var id: ReferenceTitre { titre.reference }
}

/// Pourquoi un titre remonte, ou pourquoi il descend : chaque raison se dit en français à l'écran.
public enum RaisonAffinite: Codable, Sendable, Equatable, Hashable {
    /// Le genre nommé dans la demande du soir.
    case demande(Int)
    case genreAime(Int)
    case acteurAime(Int)
    case dureeQuiVaBien(Int)
    case bienNote(Int)
    case regardableMaintenant
    case genreEvite(Int)
}

/// Le score local d'un candidat : une valeur de 0 à 1, et ce qui l'explique.
public struct ScoreAffinite: Codable, Sendable, Equatable {
    public var valeur: Double
    public var raisons: [RaisonAffinite]

    public init(valeur: Double, raisons: [RaisonAffinite] = []) {
        self.valeur = valeur
        self.raisons = raisons
    }
}

/// Un titre retenu, avec sa phrase d'explication (EF-24).
public struct SuggestionClassee: Codable, Sendable, Equatable, Identifiable {
    public var candidat: CandidatSuggestion
    public var score: ScoreAffinite
    /// Une phrase, de Claude ou construite à partir des raisons locales.
    public var phrase: String

    public init(candidat: CandidatSuggestion, score: ScoreAffinite, phrase: String) {
        self.candidat = candidat
        self.score = score
        self.phrase = phrase
    }

    public var reference: ReferenceTitre { candidat.reference }
    public var id: ReferenceTitre { candidat.reference }
}

/// Note de 0 à 1 d'un candidat au regard du profil (EF-62). Aucun réseau, aucun modèle :
/// la même entrée donne toujours la même sortie, ce qui la rend testable et explicable.
public enum ScoreurAffinite {
    /// Un titre neutre, sans aucun goût connu, part de là.
    static let base = 0.5

    public static func score(_ candidat: CandidatSuggestion, profil: ProfilGouts) -> ScoreAffinite {
        var valeur = base
        var raisons: [RaisonAffinite] = []

        // Genres : la moyenne des affinités, pour qu'un film à cinq genres ne gagne pas d'office.
        let affinitesGenres = candidat.titre.genres.map(profil.affinite(genre:))
        if !affinitesGenres.isEmpty {
            let moyenne = affinitesGenres.reduce(0, +) / Double(affinitesGenres.count)
            valeur += 0.30 * moyenne * profil.maturite
            if let meilleur = candidat.titre.genres.max(by: { profil.affinite(genre: $0) < profil.affinite(genre: $1) }),
               profil.affinite(genre: meilleur) >= 0.25 {
                raisons.append(.genreAime(meilleur))
            }
            if let pire = candidat.titre.genres.min(by: { profil.affinite(genre: $0) < profil.affinite(genre: $1) }),
               profil.affinite(genre: pire) <= -0.25 {
                raisons.append(.genreEvite(pire))
            }
        }

        // Acteurs : seul le meilleur compte, et seulement en positif.
        if let meilleur = candidat.acteurs.max(by: { profil.affinite(acteur: $0) < profil.affinite(acteur: $1) }) {
            let affinite = profil.affinite(acteur: meilleur)
            if affinite > 0 {
                valeur += 0.20 * affinite * profil.maturite
                if affinite >= 0.25 { raisons.append(.acteurAime(meilleur)) }
            }
        }

        // Note TMDB, à partir de cinquante votes : en dessous, elle ne veut rien dire.
        if candidat.titre.nombreVotes >= 50 {
            valeur += 0.20 * (candidat.titre.noteMoyenne / 10 - 0.5)
            let pourcentage = Int((candidat.titre.noteMoyenne * 10).rounded())
            if pourcentage >= 70 { raisons.append(.bienNote(pourcentage)) }
        }

        // Durée habituelle des soirées.
        if let duree = candidat.dureeMinutes, let habituelle = profil.dureeHabituelleMinutes,
           abs(duree - habituelle) <= profil.ecartDureeMinutes {
            valeur += 0.08
            raisons.append(.dureeQuiVaBien(duree))
        }

        // Regardable sans rien louer ni attendre.
        switch candidat.disponibilite {
        case .some(.surNAS), .some(.dansAbonnements):
            valeur += 0.07
            raisons.append(.regardableMaintenant)
        default:
            break
        }

        return ScoreAffinite(valeur: min(1, max(0, valeur)), raisons: raisons)
    }
}

/// Le classement local : il sert de repli quand Claude est injoignable (EF-27), et il prépare
/// toujours la liste des candidats envoyés à Claude.
public enum ClassementLocal {
    /// Écarte ce que la demande exclut, puis trie par affinité décroissante. À score égal,
    /// l'identifiant TMDB le plus petit passe devant : l'ordre ne bouge pas d'un appel à l'autre.
    public static func classer(
        _ candidats: [CandidatSuggestion], profil: ProfilGouts,
        demande: DemandeCeSoir = DemandeCeSoir(), nomsGenres: [Int: String] = [:]
    ) -> [SuggestionClassee] {
        candidats
            .filter { retient($0, demande: demande) }
            .map { candidat in
                var score = ScoreurAffinite.score(candidat, profil: profil)
                // Le genre demandé passe devant les goûts habituels et s'annonce en premier.
                if let genre = genreDemande(candidat, demande: demande) {
                    score.valeur = min(1, score.valeur + 0.15)
                    score.raisons.insert(.demande(genre), at: 0)
                }
                return SuggestionClassee(
                    candidat: candidat,
                    score: score,
                    phrase: Phrases.explication(score.raisons, profil: profil, candidat: candidat, nomsGenres: nomsGenres)
                )
            }
            .sorted { a, b in
                a.score.valeur != b.score.valeur
                    ? a.score.valeur > b.score.valeur
                    : a.reference.tmdbID < b.reference.tmdbID
            }
    }

    /// Le premier genre demandé que le candidat possède, s'il y en a un.
    static func genreDemande(_ candidat: CandidatSuggestion, demande: DemandeCeSoir) -> Int? {
        demande.interpretation.genres(pour: candidat.reference.type).first { candidat.titre.genres.contains($0) }
    }

    static func retient(_ candidat: CandidatSuggestion, demande: DemandeCeSoir) -> Bool {
        if let type = demande.typeEffectif, candidat.reference.type != type { return false }
        let envie = demande.interpretation
        let type = candidat.reference.type
        if envie.aDesGenres {
            guard genreDemande(candidat, demande: demande) != nil else { return false }
        }
        if !Set(envie.genresExclus(pour: type)).isDisjoint(with: candidat.titre.genres) { return false }
        // Une durée inconnue ne fait pas écarter le titre : TMDB ne la donne pas dans ses listes.
        if let maximum = demande.dureeMaxEffective, let duree = candidat.dureeMinutes, duree > maximum { return false }
        if candidat.disponibilite == .introuvable { return false }
        return true
    }
}

/// Les phrases du classement local. Quand Claude répond, ce sont les siennes qui s'affichent (EF-24).
public enum Phrases {
    public static func explication(
        _ raisons: [RaisonAffinite], profil: ProfilGouts,
        candidat: CandidatSuggestion, nomsGenres: [Int: String] = [:]
    ) -> String {
        // Les genres sont regroupés : « action et aventure, des genres que tu aimes » plutôt que deux fois « comme tu aimes ».
        var demandes: [String] = []
        var aimes: [String] = []
        var acteurs: [String] = []
        var autres: [String] = []
        for raison in raisons {
            switch raison {
            case .demande(let genre):
                if let nom = nomsGenres[genre] { demandes.append(nom.lowercased()) }
            case .genreAime(let genre):
                if let nom = nomsGenres[genre] { aimes.append(nom.lowercased()) }
            case .acteurAime(let acteur):
                acteurs.append(candidat.nomsActeurs[acteur] ?? profil.nom(acteur: acteur))
            case .dureeQuiVaBien(let minutes):
                autres.append("\(minutes) min, la longueur de tes soirées")
            case .bienNote(let pourcentage):
                autres.append("\(pourcentage) % sur TMDB")
            case .regardableMaintenant:
                autres.append("déjà chez toi")
            case .genreEvite:
                break
            }
        }
        var morceaux: [String] = []
        if !demandes.isEmpty {
            morceaux.append("\(liste(demandes)), comme tu l'as demandé")
        }
        if !aimes.isEmpty {
            morceaux.append(aimes.count == 1 ? "\(aimes[0]), un genre que tu aimes" : "\(liste(aimes)), des genres que tu aimes")
        }
        if !acteurs.isEmpty {
            morceaux.append("avec \(liste(acteurs))")
        }
        morceaux += autres
        guard let premier = morceaux.first else {
            return "Proposé sur sa popularité : tes goûts ne disent encore rien de ce titre."
        }
        let majuscule = premier.prefix(1).uppercased() + String(premier.dropFirst())
        return ([majuscule] + morceaux.dropFirst()).joined(separator: " · ") + "."
    }

    /// « action », « action et aventure », « action, aventure et thriller ».
    static func liste(_ elements: [String]) -> String {
        switch elements.count {
        case 0: ""
        case 1: elements[0]
        default: elements.dropLast().joined(separator: ", ") + " et " + elements[elements.count - 1]
        }
    }
}
