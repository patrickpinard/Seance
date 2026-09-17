import Foundation
import SeanceKit
import SwiftData

// Données de Patrick, incluses dans la sauvegarde (configuration « Utilisateur »).
// Règles CloudKit respectées dès maintenant pour pouvoir activer iCloud plus tard sans migration :
// pas d'attribut `.unique`, une valeur par défaut pour chaque propriété, relations optionnelles.
// Les énumérations sont stockées en texte brut, lisible dans les prédicats.

public enum StatutSuivi: String, Codable, Sendable, CaseIterable {
    case aVoir
    case enCours
    case termine
    case exclu
}

/// Un film ou une série dans les listes de Patrick.
@Model
public final class Suivi {
    public var tmdbID: Int = 0
    public var typeBrut: String = TypeTitre.film.rawValue
    public var statutBrut: String = StatutSuivi.aVoir.rawValue
    /// De 1 à 10.
    public var note: Int?
    /// « Ni VF ni sous-titres FR » (EF-29).
    public var exclusionLangue: Bool = false
    public var ajouteLe: Date = Date.now
    // Copies prises à l'ajout, pour afficher la liste sans réseau.
    public var titre: String = ""
    public var cheminAffiche: String?
    public var acteursPrincipaux: [String] = []
    /// Identifiants TMDB des mêmes acteurs : le profil de goûts et les critères TMDB les exigent (EF-62).
    public var acteursPrincipauxIDs: [Int] = []
    public var genres: [Int] = []
    /// Cloche de la fiche : les alertes restent actives même quand le titre est terminé.
    public var alertesActives: Bool = true
    public var modeAlertesBrut: String = ModeAlerteSerie.episodes.rawValue

    public var modeAlertes: ModeAlerteSerie {
        get { ModeAlerteSerie(rawValue: modeAlertesBrut) ?? .episodes }
        set { modeAlertesBrut = newValue.rawValue }
    }

    public var type: TypeTitre {
        get { TypeTitre(rawValue: typeBrut) ?? .film }
        set { typeBrut = newValue.rawValue }
    }

    public var statut: StatutSuivi {
        get { StatutSuivi(rawValue: statutBrut) ?? .aVoir }
        set { statutBrut = newValue.rawValue }
    }

    public var reference: ReferenceTitre {
        ReferenceTitre(type: type, tmdbID: tmdbID)
    }

    public init(reference: ReferenceTitre, titre: String, statut: StatutSuivi = .aVoir, cheminAffiche: String? = nil) {
        tmdbID = reference.tmdbID
        typeBrut = reference.type.rawValue
        statutBrut = statut.rawValue
        self.titre = titre
        self.cheminAffiche = cheminAffiche
    }
}

/// Un film ou un épisode vu : source des statistiques (EF-15, EF-34).
@Model
public final class Visionnage {
    public var tmdbID: Int = 0
    public var typeBrut: String = TypeTitre.film.rawValue
    public var saison: Int?
    public var episode: Int?
    /// Copiée au moment du visionnage : les statistiques restent justes après la purge du cache.
    public var dureeMinutes: Int = 0
    public var note: Int?
    public var vuLe: Date = Date.now
    /// « Déjà vu avant », à une date oubliée : le titre sort des suggestions et nourrit les goûts,
    /// mais n'entre pas dans les statistiques. `vuLe` est alors le moment où il a été marqué.
    public var anterieur: Bool = false

    public var type: TypeTitre {
        TypeTitre(rawValue: typeBrut) ?? .film
    }

    public init(
        reference: ReferenceTitre, saison: Int? = nil, episode: Int? = nil, dureeMinutes: Int, vuLe: Date = .now, anterieur: Bool = false
    ) {
        tmdbID = reference.tmdbID
        typeBrut = reference.type.rawValue
        self.saison = saison
        self.episode = episode
        self.dureeMinutes = dureeMinutes
        self.vuLe = vuLe
        self.anterieur = anterieur
    }
}

/// Une liste nommée, par exemple « Soirées Statham » (EF-63).
@Model
public final class ListePerso {
    public var nom: String = ""
    public var creeeLe: Date = Date.now
    public var titres: [ReferenceTitre] = []

    public init(nom: String) {
        self.nom = nom
    }
}

/// Un jeu de critères Explorer réutilisable (EF-57, EF-58).
@Model
public final class FiltreEnregistre {
    public var nom: String = ""
    public var typeBrut: String = TypeTitre.film.rawValue
    /// `CriteresDecouverte` encodé en JSON.
    public var criteresJSON: Data = Data()
    public var alerteActive: Bool = false
    public var derniersResultats: [ReferenceTitre] = []
    public var creeLe: Date = Date.now
    /// `FiltresExplorer` encodé en JSON : personnes, sous-genres et filtres de l'app compris.
    public var filtresJSON: Data?

    public var criteres: CriteresDecouverte {
        get { (try? JSONDecoder().decode(CriteresDecouverte.self, from: criteresJSON)) ?? CriteresDecouverte() }
        set { criteresJSON = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    public var filtres: FiltresExplorer? {
        get { filtresJSON.flatMap { try? JSONDecoder().decode(FiltresExplorer.self, from: $0) } }
        set { filtresJSON = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    public init(nom: String, type: TypeTitre, criteres: CriteresDecouverte) {
        self.nom = nom
        typeBrut = type.rawValue
        criteresJSON = (try? JSONEncoder().encode(criteres)) ?? Data()
    }

    /// Enregistre un réglage d'Explorer ; les critères TMDB sont gardés à part pour les alertes (EF-58).
    public convenience init(nom: String, filtres: FiltresExplorer, abonnements: [Int]) {
        self.init(nom: nom, type: filtres.type, criteres: filtres.criteres(abonnements: abonnements))
        self.filtres = filtres
    }
}

/// Un goût choisi au premier lancement (EF-60).
@Model
public final class Interet {
    public var genreID: Int?
    public var motCleID: Int?
    public var libelle: String = ""
    public var poids: Double = 1

    public init(libelle: String, genreID: Int? = nil, motCleID: Int? = nil, poids: Double = 1) {
        self.libelle = libelle
        self.genreID = genreID
        self.motCleID = motCleID
        self.poids = poids
    }
}

/// Un titre écarté d'un « Pas ce soir » : il ne revient pas dans les suggestions avant demain (EF-26).
@Model
public final class SuggestionReportee {
    public var tmdbID: Int = 0
    public var typeBrut: String = TypeTitre.film.rawValue
    public var jusquA: Date = Date.now
    public var reporteLe: Date = Date.now

    public var reference: ReferenceTitre {
        ReferenceTitre(type: TypeTitre(rawValue: typeBrut) ?? .film, tmdbID: tmdbID)
    }

    public init(reference: ReferenceTitre, jusquA: Date) {
        tmdbID = reference.tmdbID
        typeBrut = reference.type.rawValue
        self.jusquA = jusquA
    }
}

/// Une plateforme suisse cochée (EF-42).
@Model
public final class Abonnement {
    public var providerID: Int = 0
    public var nom: String = ""
    public var cheminLogo: String?
    public var actif: Bool = true

    public init(providerID: Int, nom: String, cheminLogo: String? = nil) {
        self.providerID = providerID
        self.nom = nom
        self.cheminLogo = cheminLogo
    }
}

public enum SourceGuide: String, Codable, Sendable {
    case srgssr
    case xmltvfr
}

/// Une chaîne de télé reçue (EF-45).
@Model
public final class Chaine {
    public var identifiantGuide: String = ""
    public var nom: String = ""
    public var sourceBrut: String = SourceGuide.xmltvfr.rawValue
    public var active: Bool = true

    public var source: SourceGuide {
        SourceGuide(rawValue: sourceBrut) ?? .xmltvfr
    }

    public init(identifiantGuide: String, nom: String, source: SourceGuide) {
        self.identifiantGuide = identifiantGuide
        self.nom = nom
        sourceBrut = source.rawValue
    }
}

public enum ModeNAS: String, Codable, Sendable {
    case jellyfin
    case plex
    case smb
}

/// Le NAS relié par Patrick (EF-71). La clé du serveur est dans le trousseau, pas ici.
@Model
public final class SourceNAS {
    public var modeBrut: String = ModeNAS.jellyfin.rawValue
    public var adresse: String?
    /// Signet d'accès au dossier partagé choisi dans Fichiers (mode SMB).
    public var signetDossier: Data?

    public var mode: ModeNAS {
        ModeNAS(rawValue: modeBrut) ?? .jellyfin
    }

    public init(mode: ModeNAS, adresse: String? = nil, signetDossier: Data? = nil) {
        modeBrut = mode.rawValue
        self.adresse = adresse
        self.signetDossier = signetDossier
    }
}

/// Un titre retenu pour la soirée (« Ma soirée » dans Ce soir). La soirée va de 6 h à 6 h le lendemain.
@Model
public final class SelectionSoir {
    public var tmdbID: Int = 0
    public var typeBrut: String = TypeTitre.film.rawValue
    public var titre: String = ""
    public var cheminAffiche: String?
    /// Jour de la soirée, par exemple « 2026-09-17 ».
    public var soiree: String = ""
    public var ajouteLe: Date = Date.now

    public init(reference: ReferenceTitre, titre: String, cheminAffiche: String?, soiree: String) {
        tmdbID = reference.tmdbID
        typeBrut = reference.type.rawValue
        self.titre = titre
        self.cheminAffiche = cheminAffiche
        self.soiree = soiree
    }

    public var reference: ReferenceTitre {
        ReferenceTitre(type: TypeTitre(rawValue: typeBrut) ?? .film, tmdbID: tmdbID)
    }
}
