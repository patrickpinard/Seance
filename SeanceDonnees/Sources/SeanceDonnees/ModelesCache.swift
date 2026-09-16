import Foundation
import SeanceKit
import SwiftData

// Données reconstruites à la demande (configuration « Cache ») : jamais sauvegardées,
// purgées au plus tard après 6 mois comme l'exigent les conditions de TMDB (ENF-07).

/// Fiche TMDB complète gardée pour l'affichage hors ligne.
@Model
public final class TitreCache {
    public var tmdbID: Int = 0
    public var typeBrut: String = TypeTitre.film.rawValue
    /// Réponse TMDB brute, en JSON.
    public var donnees: Data = Data()
    public var majLe: Date = Date.now

    public init(reference: ReferenceTitre, donnees: Data, majLe: Date = .now) {
        tmdbID = reference.tmdbID
        typeBrut = reference.type.rawValue
        self.donnees = donnees
        self.majLe = majLe
    }
}

/// Un passage à la télé, rattaché à TMDB quand la correspondance est sûre (EF-46 à EF-51).
@Model
public final class Diffusion {
    public var chaine: String = ""
    public var debut: Date = Date.distantPast
    public var fin: Date = Date.distantPast
    public var titreGuide: String = ""
    public var anneeGuide: Int?
    public var saison: Int?
    public var episode: Int?
    public var typeBrut: String = TypeTitre.film.rawValue
    /// `nil` tant que la diffusion n'est pas rattachée : elle n'apparaît alors nulle part.
    public var tmdbID: Int?

    public init(programme: ProgrammeTV, rattachement: CandidatRattachement?) {
        chaine = programme.chaine
        debut = programme.debut
        fin = programme.fin
        titreGuide = programme.titre
        anneeGuide = programme.annee
        saison = programme.saison
        episode = programme.episode
        typeBrut = (programme.nature == .serie ? TypeTitre.serie : .film).rawValue
        tmdbID = rattachement?.tmdbID
    }
}

/// Dernier état connu des plateformes d'un titre suivi : un changement déclenche l'alerte EF-17.
@Model
public final class EtatPlateformes {
    public var tmdbID: Int = 0
    public var typeBrut: String = TypeTitre.film.rawValue
    public var fournisseurs: [Int] = []
    public var verifieLe: Date = Date.now

    public init(reference: ReferenceTitre, fournisseurs: [Int], verifieLe: Date = .now) {
        tmdbID = reference.tmdbID
        typeBrut = reference.type.rawValue
        self.fournisseurs = fournisseurs
        self.verifieLe = verifieLe
    }
}

/// Évite d'envoyer deux fois la même alerte.
@Model
public final class AlertePlanifiee {
    public var tmdbID: Int = 0
    public var typeBrut: String = TypeTitre.film.rawValue
    public var motif: String = ""
    public var date: Date = Date.now
    public var envoyee: Bool = false

    public init(reference: ReferenceTitre, motif: String, date: Date) {
        tmdbID = reference.tmdbID
        typeBrut = reference.type.rawValue
        self.motif = motif
        self.date = date
    }
}

/// Un film ou un épisode présent sur le NAS (EF-72 à EF-74).
@Model
public final class FichierNAS {
    public var tmdbID: Int?
    public var typeBrut: String = TypeTitre.film.rawValue
    public var saison: Int?
    public var episode: Int?
    public var chemin: String = ""
    /// « 4K », « 1080p », « 720p »…
    public var qualite: String?
    public var tailleOctets: Int64 = 0
    public var indexeLe: Date = Date.now

    public init(chemin: String, type: TypeTitre, tmdbID: Int? = nil, qualite: String? = nil, tailleOctets: Int64 = 0) {
        self.chemin = chemin
        typeBrut = type.rawValue
        self.tmdbID = tmdbID
        self.qualite = qualite
        self.tailleOctets = tailleOctets
    }
}
