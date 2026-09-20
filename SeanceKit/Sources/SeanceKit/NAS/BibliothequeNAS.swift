import Foundation

/// Réglages du NAS (EF-71). Le mot de passe n'en fait pas partie : il est dans le trousseau (EF-86).
public struct ReglagesNAS: Codable, Sendable, Hashable {
    public var hote: String
    public var partage: String
    /// Dossiers du partage à analyser ; les autres ne sont jamais lus.
    public var dossiers: [String]
    public var utilisateur: String

    /// Valeurs relevées sur le Synology DS220 de Patrick.
    public init(hote: String = "192.168.1.220", partage: String = "Films",
                dossiers: [String] = ["Films", "NEW", "Séries"], utilisateur: String = "admin") {
        self.hote = hote
        self.partage = partage
        self.dossiers = dossiers
        self.utilisateur = utilisateur
    }

    public var estComplet: Bool {
        !hote.isEmpty && !partage.isEmpty && !dossiers.isEmpty && !utilisateur.isEmpty
    }

    /// `smb://hôte/partage/chemin`, avec ou sans identifiants (les apps de lecture en ont besoin).
    public func url(chemin: String, motDePasse: String? = nil) -> URL? {
        var composants = URLComponents()
        composants.scheme = "smb"
        composants.host = hote
        if let motDePasse {
            composants.user = utilisateur
            composants.password = motDePasse
        }
        let segments = [partage] + chemin.split(separator: "/").map(String.init)
        composants.path = "/" + segments.joined(separator: "/")
        return composants.url
    }
}

/// Un fichier vu sur le NAS : chemin relatif au partage (« Films/Bang.2025.mkv ») et taille en octets.
public struct FichierDistant: Sendable, Hashable {
    public var chemin: String
    public var taille: Int64
    /// Lue seulement là où elle sert : les vidéos personnelles se rangent par date.
    public var modifieLe: Date?

    public init(chemin: String, taille: Int64, modifieLe: Date? = nil) {
        self.chemin = chemin
        self.taille = taille
        self.modifieLe = modifieLe
    }
}

/// Ce qui sait lister les vidéos d'un NAS : le client SMB sur iPhone, le système de fichiers sur Mac.
public protocol ExplorateurFichiers: Sendable {
    func listerVideos(dossiers: [String]) async throws -> [FichierDistant]
}

/// Explorateur d'un partage déjà monté, par exemple `/Volumes/Films` sur le Mac.
public struct ExplorateurLocal: ExplorateurFichiers {
    public let racine: URL

    public init(racine: URL) {
        self.racine = racine
    }

    public func listerVideos(dossiers: [String]) async throws -> [FichierDistant] {
        let gestionnaire = FileManager.default
        var fichiers: [FichierDistant] = []
        for dossier in dossiers {
            let base = racine.appending(path: dossier)
            guard let parcours = gestionnaire.enumerator(at: base, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                                         options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            while let url = parcours.nextObject() as? URL {
                guard AnalyseNomFichier.extensionsVideo.contains(url.pathExtension.lowercased()) else { continue }
                let valeurs = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard valeurs.isRegularFile == true else { continue }
                let relatif = String(url.path(percentEncoded: false).dropFirst(racine.path(percentEncoded: false).count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                fichiers.append(FichierDistant(chemin: relatif, taille: Int64(valeurs.fileSize ?? 0)))
            }
        }
        return fichiers
    }
}

/// Une vidéo retenue dans l'index du NAS.
public struct EntreeNAS: Sendable, Hashable {
    public var fichier: FichierDistant
    public var analyse: FichierVideoAnalyse
    /// Premier dossier du chemin : « Films », « NEW » ou « Séries ».
    public var dossier: String

    public var cleOeuvre: String {
        "\(analyse.type.rawValue)|\(NormalisationTitre.normaliser(analyse.titre))"
    }
}

/// Plusieurs fichiers pour le même film ou le même épisode : celui que Séance garde et les autres.
public struct DoublonNAS: Sendable, Hashable {
    public var gardee: FichierDistant
    public var ecartees: [FichierDistant]

    public init(gardee: FichierDistant, ecartees: [FichierDistant]) {
        self.gardee = gardee
        self.ecartees = ecartees
    }
}

public enum IndexNAS {
    public struct Resultat: Sendable {
        public var entrees: [EntreeNAS]
        /// Vidéos dont le nom n'a pas pu être lu.
        public var illisibles: [FichierDistant]
        /// Copies en double d'un même film ou épisode (par exemple `.mkv` et `.mp4`), triées par chemin.
        public var copiesEnDouble: [DoublonNAS]

        /// Nombre de fichiers écartés parce qu'une meilleure copie existe.
        public var doublons: Int {
            copiesEnDouble.reduce(0) { $0 + $1.ecartees.count }
        }
    }

    /// Analyse les noms et ne garde qu'une copie par film ou par épisode : la meilleure qualité connue,
    /// puis le fichier le plus lourd (EF-72).
    public static func construire(_ fichiers: [FichierDistant]) -> Resultat {
        var meilleures: [String: EntreeNAS] = [:]
        var ordre: [String] = []
        var illisibles: [FichierDistant] = []
        var copies: [String: [FichierDistant]] = [:]

        for fichier in fichiers {
            guard let analyse = AnalyseNomFichier.analyser(chemin: "/" + fichier.chemin) else {
                illisibles.append(fichier)
                continue
            }
            let dossier = fichier.chemin.split(separator: "/").first.map(String.init) ?? ""
            let entree = EntreeNAS(fichier: fichier, analyse: analyse, dossier: dossier)
            let cle = entree.cleOeuvre + "|" + (analyse.episode?.description ?? String(analyse.annee ?? 0))
            copies[cle, default: []].append(fichier)
            if let existante = meilleures[cle] {
                if estMeilleure(entree, que: existante) { meilleures[cle] = entree }
            } else {
                meilleures[cle] = entree
                ordre.append(cle)
            }
        }
        let enDouble = ordre.compactMap { cle -> DoublonNAS? in
            guard let gardee = meilleures[cle]?.fichier, let toutes = copies[cle], toutes.count > 1 else { return nil }
            return DoublonNAS(gardee: gardee, ecartees: toutes.filter { $0 != gardee }.sorted { $0.chemin < $1.chemin })
        }
        .sorted { $0.gardee.chemin < $1.gardee.chemin }
        return Resultat(entrees: ordre.compactMap { meilleures[$0] }, illisibles: illisibles, copiesEnDouble: enDouble)
    }

    private static func estMeilleure(_ a: EntreeNAS, que b: EntreeNAS) -> Bool {
        let qa = a.analyse.qualite?.rawValue ?? 0
        let qb = b.analyse.qualite?.rawValue ?? 0
        return qa != qb ? qa > qb : a.fichier.taille > b.fichier.taille
    }
}

/// Une vidéo du NAS et le titre TMDB auquel elle se rattache, s'il est sûr.
public struct EntreeRattachee: Sendable, Hashable {
    public var entree: EntreeNAS
    public var titre: TitreResume?
}

/// Rattache les vidéos du NAS à TMDB (EF-72, EF-79). Une œuvre n'est cherchée qu'une fois, même
/// pour les dizaines d'épisodes d'une série.
public actor RattachementNAS {
    private let recherche: any RechercheTMDB
    private var parOeuvre: [String: TitreResume?] = [:]
    public private(set) var recherchesEnEchec = 0

    public init(recherche: any RechercheTMDB) {
        self.recherche = recherche
    }

    public func rattacher(_ entrees: [EntreeNAS]) async throws -> [EntreeRattachee] {
        // Une recherche par œuvre, six à la fois : les épisodes d'une série partagent la leur.
        var representants: [String: EntreeNAS] = [:]
        var ordre: [String] = []
        for entree in entrees where representants[Self.cle(entree)] == nil {
            representants[Self.cle(entree)] = entree
            ordre.append(Self.cle(entree))
        }
        var trouves: [String: TitreResume] = [:]
        try await withThrowingTaskGroup(of: (String, TitreResume?).self) { groupe in
            var reste = ordre[...]
            for _ in 0..<6 {
                guard let cle = reste.popFirst(), let entree = representants[cle] else { break }
                groupe.addTask { (cle, try await self.titre(pour: entree)) }
            }
            while let (cle, titre) = try await groupe.next() {
                trouves[cle] = titre
                if let suivante = reste.popFirst(), let entree = representants[suivante] {
                    groupe.addTask { (suivante, try await self.titre(pour: entree)) }
                }
            }
        }
        return entrees.map { EntreeRattachee(entree: $0, titre: trouves[Self.cle($0)]) }
    }

    private static func cle(_ entree: EntreeNAS) -> String {
        entree.cleOeuvre + "|" + String(entree.analyse.annee ?? 0)
    }

    private func titre(pour entree: EntreeNAS) async throws -> TitreResume? {
        let analyse = entree.analyse
        let cle = Self.cle(entree)
        if let connu = parOeuvre[cle] { return connu }

        let trouve: TitreResume?
        do {
            switch analyse.type {
            case .film:
                let resultats = try await recherche.rechercherFilms(analyse.titre, page: 1).resultats.map(\.titreResume)
                var retenu = choisirFilm(analyse, parmi: resultats)
                // Titre générique noyé parmi les homonymes : second essai restreint à l'année.
                if retenu == nil, let annee = analyse.annee {
                    let parAnnee = try await recherche.rechercherFilms(analyse.titre, annee: annee, page: 1).resultats.map(\.titreResume)
                    retenu = choisirFilm(analyse, parmi: parAnnee)
                }
                trouve = retenu
            case .serie:
                let resultats = try await recherche.rechercherSeries(analyse.titre, page: 1).resultats.map(\.titreResume)
                trouve = choisirSerie(analyse, parmi: resultats)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            recherchesEnEchec += 1
            return nil
        }
        parOeuvre[cle] = .some(trouve)
        return trouve
    }

    /// Un identifiant TMDB écrit dans le nom l'emporte ; sinon titre et année, avec la règle de la télé.
    func choisirFilm(_ analyse: FichierVideoAnalyse, parmi resultats: [TitreResume]) -> TitreResume? {
        if let id = analyse.tmdbID, let exact = resultats.first(where: { $0.reference.tmdbID == id }) { return exact }
        let candidats = resultats.map {
            CandidatRattachement(tmdbID: $0.reference.tmdbID, type: .film, titre: $0.titre, titreOriginal: $0.titreOriginal, annee: $0.date?.annee)
        }
        guard let retenu = Rattacheur.rattacher(titre: analyse.titre, annee: analyse.annee, parmi: candidats) else { return nil }
        return resultats.first { $0.reference.tmdbID == retenu.tmdbID }
    }

    /// Un dossier de série n'a pas d'année : le titre doit correspondre exactement, et une homonyme
    /// n'est retenue que si elle est au moins deux fois plus connue que la suivante.
    func choisirSerie(_ analyse: FichierVideoAnalyse, parmi resultats: [TitreResume]) -> TitreResume? {
        if let id = analyse.tmdbID, let exact = resultats.first(where: { $0.reference.tmdbID == id }) { return exact }
        let cible = NormalisationTitre.normaliser(analyse.titre)
        let exacts = resultats
            .filter { NormalisationTitre.normaliser($0.titre) == cible || NormalisationTitre.normaliser($0.titreOriginal) == cible }
            .sorted { $0.nombreVotes > $1.nombreVotes }
        guard let premier = exacts.first else { return nil }
        if exacts.count == 1 { return premier }
        return premier.nombreVotes >= 2 * max(1, exacts[1].nombreVotes) ? premier : nil
    }
}
