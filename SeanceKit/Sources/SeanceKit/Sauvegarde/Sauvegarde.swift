import Foundation

/// Fichier de sauvegarde de Séance (EF-70) : tout ce que Patrick a saisi, rien de ce qui se
/// retélécharge. Sans iCloud, c'est la seule protection contre la perte de l'iPhone.
public struct Sauvegarde: Codable, Sendable, Equatable {
    public static let versionActuelle = 1

    public struct Suivi: Codable, Sendable, Equatable {
        public var reference: ReferenceTitre
        public var statut: String
        public var note: Int?
        public var exclusionLangue: Bool
        public var ajouteLe: Date
        public var titre: String
        public var cheminAffiche: String?
        public var acteursPrincipaux: [String]
        public var genres: [Int]

        public init(reference: ReferenceTitre, statut: String, note: Int?, exclusionLangue: Bool, ajouteLe: Date,
                    titre: String, cheminAffiche: String?, acteursPrincipaux: [String], genres: [Int]) {
            self.reference = reference
            self.statut = statut
            self.note = note
            self.exclusionLangue = exclusionLangue
            self.ajouteLe = ajouteLe
            self.titre = titre
            self.cheminAffiche = cheminAffiche
            self.acteursPrincipaux = acteursPrincipaux
            self.genres = genres
        }
    }

    public struct Visionnage: Codable, Sendable, Equatable {
        public var reference: ReferenceTitre
        public var episode: NumeroEpisode?
        public var dureeMinutes: Int
        public var note: Int?
        public var vuLe: Date

        public init(reference: ReferenceTitre, episode: NumeroEpisode?, dureeMinutes: Int, note: Int?, vuLe: Date) {
            self.reference = reference
            self.episode = episode
            self.dureeMinutes = dureeMinutes
            self.note = note
            self.vuLe = vuLe
        }

        /// Deux visionnages du même épisode à la même minute sont un doublon.
        var cle: String {
            "\(reference)|\(episode?.description ?? "-")|\(Int(vuLe.timeIntervalSince1970 / 60))"
        }
    }

    public struct Liste: Codable, Sendable, Equatable {
        public var nom: String
        public var creeeLe: Date
        public var titres: [ReferenceTitre]

        public init(nom: String, creeeLe: Date, titres: [ReferenceTitre]) {
            self.nom = nom
            self.creeeLe = creeeLe
            self.titres = titres
        }
    }

    public struct Filtre: Codable, Sendable, Equatable {
        public var nom: String
        public var type: TypeTitre
        public var criteres: CriteresDecouverte
        public var alerteActive: Bool
        /// Réglages complets d'Explorer, filtres de l'app compris ; absents des sauvegardes anciennes.
        public var filtres: FiltresExplorer?

        public init(nom: String, type: TypeTitre, criteres: CriteresDecouverte, alerteActive: Bool, filtres: FiltresExplorer? = nil) {
            self.nom = nom
            self.type = type
            self.criteres = criteres
            self.alerteActive = alerteActive
            self.filtres = filtres
        }
    }

    public struct Interet: Codable, Sendable, Equatable {
        public var libelle: String
        public var genreID: Int?
        public var motCleID: Int?
        public var poids: Double

        public init(libelle: String, genreID: Int?, motCleID: Int?, poids: Double) {
            self.libelle = libelle
            self.genreID = genreID
            self.motCleID = motCleID
            self.poids = poids
        }

        var cle: String { "\(genreID.map(String.init) ?? "-")|\(motCleID.map(String.init) ?? "-")" }
    }

    public struct Abonnement: Codable, Sendable, Equatable {
        public var providerID: Int
        public var nom: String
        public var actif: Bool

        public init(providerID: Int, nom: String, actif: Bool) {
            self.providerID = providerID
            self.nom = nom
            self.actif = actif
        }
    }

    public struct Chaine: Codable, Sendable, Equatable {
        public var identifiantGuide: String
        public var nom: String
        public var source: String
        public var active: Bool

        public init(identifiantGuide: String, nom: String, source: String, active: Bool) {
            self.identifiantGuide = identifiantGuide
            self.nom = nom
            self.source = source
            self.active = active
        }
    }

    public var version = Sauvegarde.versionActuelle
    public var creeeLe: Date
    public var suivis: [Suivi] = []
    public var visionnages: [Visionnage] = []
    public var listes: [Liste] = []
    public var filtres: [Filtre] = []
    public var interets: [Interet] = []
    public var abonnements: [Abonnement] = []
    public var chaines: [Chaine] = []

    public init(creeeLe: Date) {
        self.creeeLe = creeeLe
    }

    public enum Erreur: Error, Equatable {
        case versionInconnue(Int)
    }

    public func encoder() throws -> Data {
        let encodeur = JSONEncoder()
        encodeur.outputFormatting = [.prettyPrinted, .sortedKeys]
        encodeur.dateEncodingStrategy = .iso8601
        return try encodeur.encode(self)
    }

    public static func decoder(_ donnees: Data) throws -> Sauvegarde {
        let decodeur = JSONDecoder()
        decodeur.dateDecodingStrategy = .iso8601
        let sauvegarde = try decodeur.decode(Sauvegarde.self, from: donnees)
        guard sauvegarde.version <= versionActuelle else { throw Erreur.versionInconnue(sauvegarde.version) }
        return sauvegarde
    }

    /// Nom de fichier daté, par exemple « Séance 2026-09-16.json ».
    public static func nomFichier(pour date: Date, fuseau: TimeZone = .suisse) -> String {
        "Séance \(DateTMDB(date, fuseau: fuseau)).json"
    }
}

/// Ce qu'un import ajoute à l'existant : l'import ne remplace ni ne supprime rien.
public struct PlanImport: Sendable, Equatable {
    public var suivis: [Sauvegarde.Suivi] = []
    public var visionnages: [Sauvegarde.Visionnage] = []
    public var listes: [Sauvegarde.Liste] = []
    /// Titres à ajouter en fin de listes existantes, par nom de liste.
    public var titresAjoutesAuxListes: [String: [ReferenceTitre]] = [:]
    public var filtres: [Sauvegarde.Filtre] = []
    public var interets: [Sauvegarde.Interet] = []
    public var abonnements: [Sauvegarde.Abonnement] = []
    public var chaines: [Sauvegarde.Chaine] = []

    public var estVide: Bool { self == PlanImport() }

    /// En cas de conflit, la donnée déjà présente sur l'iPhone l'emporte.
    public init(importee: Sauvegarde, existante: Sauvegarde) {
        func nouveaux<T, K: Hashable>(_ elements: [T], _ presents: [T], cle: (T) -> K) -> [T] {
            var vus = Set(presents.map(cle))
            return elements.filter { vus.insert(cle($0)).inserted }
        }
        suivis = nouveaux(importee.suivis, existante.suivis, cle: \.reference)
        visionnages = nouveaux(importee.visionnages, existante.visionnages, cle: \.cle)
        filtres = nouveaux(importee.filtres, existante.filtres, cle: \.nom)
        interets = nouveaux(importee.interets, existante.interets, cle: \.cle)
        abonnements = nouveaux(importee.abonnements, existante.abonnements, cle: \.providerID)
        chaines = nouveaux(importee.chaines, existante.chaines, cle: \.identifiantGuide)

        let listesExistantes = Dictionary(existante.listes.map { ($0.nom, $0) }, uniquingKeysWith: { premiere, _ in premiere })
        for liste in importee.listes {
            if let presente = listesExistantes[liste.nom] {
                let manquants = nouveaux(liste.titres, presente.titres, cle: { $0 })
                if !manquants.isEmpty { titresAjoutesAuxListes[liste.nom, default: []] += manquants }
            } else if !listes.contains(where: { $0.nom == liste.nom }) {
                listes.append(liste)
            }
        }
    }

    init() {}
}
