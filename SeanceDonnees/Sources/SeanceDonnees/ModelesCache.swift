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
    /// Images TMDB du titre rattaché, puis vignette du guide TV en secours.
    public var cheminFond: String?
    public var cheminAffiche: String?
    public var imageGuide: String?

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
        cheminFond = rattachement?.cheminFond
        cheminAffiche = rattachement?.cheminAffiche
        imageGuide = programme.image?.absoluteString
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

/// Un film ou un épisode présent sur le NAS (EF-72 à EF-74). Titre et affiche sont recopiés de TMDB
/// à l'analyse : la bibliothèque s'affiche sans réseau.
@Model
public final class FichierNAS {
    public var tmdbID: Int?
    public var typeBrut: String = TypeTitre.film.rawValue
    public var saison: Int?
    public var episode: Int?
    /// Chemin relatif au partage : « Films/Heat.1995.mkv ».
    public var chemin: String = ""
    /// « 4K », « 1080p », « 720p »…
    public var qualite: String?
    public var tailleOctets: Int64 = 0
    public var indexeLe: Date = Date.now
    /// Premier dossier du chemin : « Films », « NEW », « Séries ».
    public var dossier: String = ""
    /// Titre TMDB s'il est reconnu, sinon celui lu dans le nom du fichier.
    public var titre: String = ""
    public var annee: Int?
    public var cheminAffiche: String?
    public var cheminFond: String?
    public var noteMoyenne: Double = 0
    public var nombreVotes: Int = 0

    public init(chemin: String, type: TypeTitre, tmdbID: Int? = nil, qualite: String? = nil, tailleOctets: Int64 = 0) {
        self.chemin = chemin
        typeBrut = type.rawValue
        self.tmdbID = tmdbID
        self.qualite = qualite
        self.tailleOctets = tailleOctets
        // Forme composée : « Séries » écrit depuis un Mac se compare alors comme celui tapé sur l'iPhone.
        dossier = (chemin.split(separator: "/").first.map(String.init) ?? "").precomposedStringWithCanonicalMapping
        titre = (chemin as NSString).lastPathComponent
    }

    public var type: TypeTitre {
        TypeTitre(rawValue: typeBrut) ?? .film
    }

    public var reference: ReferenceTitre? {
        tmdbID.map { ReferenceTitre(type: type, tmdbID: $0) }
    }

    public var nomFichier: String {
        (chemin as NSString).lastPathComponent
    }
}
