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
        /// Cloche de la fiche ; absente des sauvegardes antérieures à la version 1.1.
        public var alertesActives: Bool?
        public var modeAlertes: String?
        /// Supprimé de « Terminés » ; absent des sauvegardes antérieures à la version 1.5.
        public var masque: Bool?
        /// Identifiants TMDB des acteurs, dans l'ordre de `acteursPrincipaux` : sans eux, les acteurs favoris ne mènent
        /// à aucune fiche. Absents des sauvegardes antérieures à la version 2.7.
        public var acteursPrincipauxIDs: [Int]?

        public init(reference: ReferenceTitre, statut: String, note: Int?, exclusionLangue: Bool, ajouteLe: Date,
                    titre: String, cheminAffiche: String?, acteursPrincipaux: [String], genres: [Int],
                    alertesActives: Bool? = nil, modeAlertes: String? = nil, masque: Bool? = nil, acteursPrincipauxIDs: [Int]? = nil) {
            self.acteursPrincipauxIDs = acteursPrincipauxIDs
            self.masque = masque
            self.alertesActives = alertesActives
            self.modeAlertes = modeAlertes
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
        /// « Déjà vu avant » ; absent des sauvegardes plus anciennes.
        public var anterieur: Bool?

        public init(reference: ReferenceTitre, episode: NumeroEpisode?, dureeMinutes: Int, note: Int?, vuLe: Date, anterieur: Bool? = nil) {
            self.reference = reference
            self.episode = episode
            self.dureeMinutes = dureeMinutes
            self.note = note
            self.vuLe = vuLe
            self.anterieur = anterieur
        }

        /// Deux visionnages du même épisode à la même minute sont un doublon.
        var cle: String {
            "\(reference)|\(episode?.description ?? "-")|\(Int(vuLe.timeIntervalSince1970 / 60))"
        }
    }

    public struct Liste: Codable, Sendable, Equatable {
        /// Nom et affiche d'un titre de la liste ; absent des sauvegardes antérieures à la version 2.4.
        public struct Apercu: Codable, Sendable, Equatable {
            public var reference: ReferenceTitre
            public var titre: String
            public var cheminAffiche: String?

            public init(reference: ReferenceTitre, titre: String, cheminAffiche: String?) {
                self.reference = reference
                self.titre = titre
                self.cheminAffiche = cheminAffiche
            }
        }

        public var nom: String
        public var creeeLe: Date
        public var titres: [ReferenceTitre]
        public var apercus: [Apercu]?

        public init(nom: String, creeeLe: Date, titres: [ReferenceTitre], apercus: [Apercu]? = nil) {
            self.nom = nom
            self.creeeLe = creeeLe
            self.titres = titres
            self.apercus = apercus
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
        /// Le logo de la plateforme, pour le badge des affiches ; absent des sauvegardes antérieures à la version 2.7.
        public var cheminLogo: String?

        public init(providerID: Int, nom: String, actif: Bool, cheminLogo: String? = nil) {
            self.providerID = providerID
            self.nom = nom
            self.actif = actif
            self.cheminLogo = cheminLogo
        }
    }

    /// « Suivre un acteur » ; absent des sauvegardes antérieures à la version 1.3.
    public struct ActeurSuivi: Codable, Sendable, Equatable {
        public var personneID: Int
        public var nom: String
        public var cheminPortrait: String?
        public var suiviLe: Date
        /// Les films déjà connus de cet acteur : sans eux, l'autre appareil les annoncerait comme nouveaux.
        /// Absents des sauvegardes antérieures à la version 2.7.
        public var filmsConnus: [Int]?
        public var verifieLe: Date?

        public init(personneID: Int, nom: String, cheminPortrait: String?, suiviLe: Date, filmsConnus: [Int]? = nil, verifieLe: Date? = nil) {
            self.personneID = personneID
            self.nom = nom
            self.cheminPortrait = cheminPortrait
            self.suiviLe = suiviLe
            self.filmsConnus = filmsConnus
            self.verifieLe = verifieLe
        }
    }

    /// Un titre prévu pour une soirée (« 2026-09-25 ») ; absent des sauvegardes antérieures à la version 2.7.
    public struct Soiree: Codable, Sendable, Equatable {
        public var reference: ReferenceTitre
        public var titre: String
        public var cheminAffiche: String?
        public var soiree: String
        public var ajouteLe: Date

        public init(reference: ReferenceTitre, titre: String, cheminAffiche: String?, soiree: String, ajouteLe: Date) {
            self.reference = reference
            self.titre = titre
            self.cheminAffiche = cheminAffiche
            self.soiree = soiree
            self.ajouteLe = ajouteLe
        }
    }

    /// Une idée écartée jusqu'à une date (« pas ce soir ») ; absente des sauvegardes antérieures à la version 2.7.
    public struct Report: Codable, Sendable, Equatable {
        public var reference: ReferenceTitre
        public var jusquA: Date
        public var reporteLe: Date

        public init(reference: ReferenceTitre, jusquA: Date, reporteLe: Date) {
            self.reference = reference
            self.jusquA = jusquA
            self.reporteLe = reporteLe
        }
    }

    /// Un réglage de l'app (prénom, accueil, tri, alertes, adresse du NAS) : jamais une clé ni un mot de passe.
    public enum Preference: Codable, Sendable, Equatable {
        case texte(String)
        case entier(Int)
        case booleen(Bool)
        case donnees(Data)
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
    /// Optionnel : un fichier d'une version précédente n'a pas cette clé.
    public var acteursSuivis: [ActeurSuivi]?
    /// Soirées prévues, idées reportées et réglages : absents des sauvegardes antérieures à la version 2.7.
    public var soirees: [Soiree]?
    public var reports: [Report]?
    public var preferences: [String: Preference]?
    /// Synchronisation entre appareils (voir FusionSynchro.swift) : quand chaque élément a changé pour la dernière
    /// fois, et ce qui a été supprimé. Absents d'une sauvegarde exportée à la main, qui ne fait qu'ajouter.
    public var modifications: [String: Date]?
    public var suppressions: [Suppression]?

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

/// Ce qu'un import ajoute à l'existant : il ne supprime rien et n'efface aucune donnée présente ; il complète seulement
/// les titres déjà là (note manquante, titre vu sur l'autre appareil).
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
    public var acteursSuivis: [Sauvegarde.ActeurSuivi] = []
    public var soirees: [Sauvegarde.Soiree] = []
    public var reports: [Sauvegarde.Report] = []
    /// Titres déjà présents que le fichier complète : vu ou noté sur l'autre appareil, acteurs ou genres manquants.
    public var suivisCompletes: [Sauvegarde.Suivi] = []
    /// Plateformes déjà présentes dont le logo manquait.
    public var logosAbonnements: [Int: String] = [:]

    public var estVide: Bool { self == PlanImport() }

    /// L'avancement d'un titre : on ne recule jamais à l'import. Un titre exclu (« jamais ») le reste.
    static func rang(_ statut: String) -> Int {
        switch statut {
        case "aVoir": 0
        case "enCours": 1
        case "termine": 2
        default: 3
        }
    }

    /// Ce que le fichier apporte à un titre déjà présent, ou `nil` s'il n'apporte rien. Ce qui existe n'est jamais
    /// effacé : une note manquante est reprise, un titre vu ailleurs le devient ici, les acteurs et genres se complètent.
    static func complement(_ importe: Sauvegarde.Suivi, _ present: Sauvegarde.Suivi) -> Sauvegarde.Suivi? {
        var resultat = present
        if present.note == nil, let note = importe.note { resultat.note = note }
        if rang(present.statut) < 3, rang(importe.statut) < 3, rang(importe.statut) > rang(present.statut) { resultat.statut = importe.statut }
        if present.acteursPrincipaux.isEmpty { resultat.acteursPrincipaux = importe.acteursPrincipaux }
        if (present.acteursPrincipauxIDs ?? []).isEmpty, let ids = importe.acteursPrincipauxIDs, !ids.isEmpty,
           resultat.acteursPrincipaux == importe.acteursPrincipaux {
            resultat.acteursPrincipauxIDs = ids
        }
        if present.genres.isEmpty { resultat.genres = importe.genres }
        if present.cheminAffiche == nil { resultat.cheminAffiche = importe.cheminAffiche }
        return resultat == present ? nil : resultat
    }

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
        acteursSuivis = nouveaux(importee.acteursSuivis ?? [], existante.acteursSuivis ?? [], cle: \.personneID)
        // Un titre n'est prévu que pour une soirée à la fois : celle de cet appareil l'emporte.
        soirees = nouveaux(importee.soirees ?? [], existante.soirees ?? [], cle: \.reference)
        reports = nouveaux(importee.reports ?? [], existante.reports ?? [], cle: \.reference)

        let presents = Dictionary(existante.suivis.map { ($0.reference, $0) }, uniquingKeysWith: { premier, _ in premier })
        suivisCompletes = importee.suivis.compactMap { importe in presents[importe.reference].flatMap { Self.complement(importe, $0) } }
        let sansLogo = Set(existante.abonnements.filter { $0.cheminLogo == nil }.map(\.providerID))
        for abonnement in importee.abonnements where sansLogo.contains(abonnement.providerID) {
            if let logo = abonnement.cheminLogo { logosAbonnements[abonnement.providerID] = logo }
        }

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
