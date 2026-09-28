import Foundation

/// Un titre choisi à la main pour une vidéo du NAS ou un film du guide TV (8.4) ; sans titre : revenu à ce que
/// Séance reconnaît seul. Daté, pour que le choix le plus récent l'emporte d'un appareil à l'autre.
public struct IdentificationTMDB: Codable, Sendable, Hashable {
    public var titre: TitreResume?
    /// Ce qu'on voyait avant de choisir (nom du fichier, titre du programme) : la liste « Identifiés par toi » le montre.
    public var nom: String?
    public var majLe: Date

    public init(titre: TitreResume?, nom: String? = nil, majLe: Date = .now) {
        self.titre = titre
        self.nom = nom
        self.majLe = majLe
    }
}

/// Les titres que Séance n'a pas su reconnaître seule dans TMDB et que tu as choisis parmi ses propositions (8.4) :
/// deux films « The Runner » sortis en 2026, un nom de fichier illisible, un titre du guide traduit autrement.
///
/// Le choix vaut pour l'œuvre, pas pour un fichier : tous les épisodes d'une série, une copie convertie, une nouvelle
/// diffusion du même film le reprennent. Il est gardé dans les réglages (la bibliothèque du NAS est du cache, refait à
/// chaque analyse) et voyage dans les réglages synchronisés, entrée par entrée, comme les couvertures des souvenirs.
public struct IdentificationsTMDB: Codable, Sendable, Hashable {
    public static let cle = "tmdb.identifications"
    public var entrees: [String: IdentificationTMDB]

    public init(entrees: [String: IdentificationTMDB] = [:]) {
        self.entrees = entrees
    }

    public init(donnees: Data?) {
        entrees = donnees.flatMap { try? JSONDecoder().decode(IdentificationsTMDB.self, from: $0) }?.entrees ?? [:]
    }

    public func encoder() -> Data? {
        try? JSONEncoder().encode(self)
    }

    public static func lues(_ defauts: UserDefaults = .standard) -> IdentificationsTMDB {
        IdentificationsTMDB(donnees: defauts.data(forKey: cle))
    }

    public func enregistrer(_ defauts: UserDefaults = .standard) {
        defauts.set(encoder(), forKey: Self.cle)
    }

    // MARK: Clés

    /// Une œuvre du NAS, comme la cherche `RattachementNAS` : type, titre normalisé, année lue dans le nom.
    public static func cleNAS(_ analyse: FichierVideoAnalyse) -> String {
        "nas|\(analyse.type.rawValue)|\(NormalisationTitre.normaliser(analyse.titre))|\(analyse.annee ?? 0)"
    }

    /// La clé d'un fichier du NAS d'après son chemin ; un nom illisible se retient par son chemin.
    public static func cleNAS(chemin: String) -> String {
        AnalyseNomFichier.analyser(chemin: "/" + chemin).map(cleNAS) ?? "nas-fichier|\(chemin.precomposedStringWithCanonicalMapping)"
    }

    /// Un titre du guide TV, avec son année s'il en a une.
    public static func cleGuide(titre: String, type: TypeTitre, annee: Int?) -> String {
        "guide|\(type.rawValue)|\(NormalisationTitre.normaliser(titre))|\(annee.map(String.init) ?? "")"
    }

    // MARK: Lecture

    /// Le titre choisi pour cette clé, s'il y en a un.
    public func titre(_ cle: String) -> TitreResume? {
        entrees[cle]?.titre
    }

    public func titreNAS(chemin: String) -> TitreResume? {
        titre(Self.cleNAS(chemin: chemin))
    }

    /// Le titre choisi pour un programme : à son année, ou — programme sans année — le seul choisi pour ce titre.
    public func titre(pour programme: ProgrammeTV) -> TitreResume? {
        let type: TypeTitre
        switch programme.nature {
        case .film: type = .film
        case .serie: type = .serie
        case .autre: return nil
        }
        if let exact = titre(Self.cleGuide(titre: programme.titre, type: type, annee: programme.annee)) { return exact }
        guard programme.annee == nil else { return nil }
        let debut = Self.cleGuide(titre: programme.titre, type: type, annee: nil)
        let choisis = Set(entrees.filter { $0.key.hasPrefix(debut) }.compactMap(\.value.titre))
        return choisis.count == 1 ? choisis.first : nil
    }

    /// Les choix faits pour le NAS, ou pour le guide, les plus récents d'abord.
    public func choisis(guide: Bool) -> [(cle: String, identification: IdentificationTMDB)] {
        entrees
            .filter { $0.value.titre != nil && $0.key.hasPrefix(guide ? "guide|" : "nas") }
            .map { (cle: $0.key, identification: $0.value) }
            .sorted { $0.identification.majLe > $1.identification.majLe }
    }

    // MARK: Écriture

    public mutating func choisir(_ titre: TitreResume, pour cle: String, nom: String? = nil, le maintenant: Date = .now) {
        entrees[cle] = IdentificationTMDB(titre: titre, nom: nom, majLe: maintenant)
    }

    /// Revient à la reconnaissance automatique : l'entrée reste, vide et datée, pour que les autres appareils l'apprennent.
    public mutating func oublier(_ cle: String, le maintenant: Date = .now) {
        entrees[cle] = IdentificationTMDB(titre: nil, nom: entrees[cle]?.nom, majLe: maintenant)
    }

    /// Reprend les choix d'un autre appareil plus récents que les nôtres ; vrai si quelque chose a changé.
    @discardableResult
    public mutating func fusionner(_ autres: IdentificationsTMDB) -> Bool {
        var change = false
        for (cle, sienne) in autres.entrees where sienne.majLe > (entrees[cle]?.majLe ?? .distantPast) {
            entrees[cle] = sienne
            change = true
        }
        return change
    }

    // MARK: Propositions

    /// Ce que TMDB propose pour un titre, à choisir à la main : d'abord la recherche restreinte à l'année (le bon film
    /// y est d'habitude en tête), puis la recherche sans année ; sans doublon, les plus connus d'abord à année égale.
    public static func propositions(_ texte: String, type: TypeTitre, annee: Int?, recherche: any RechercheTMDB) async throws -> [TitreResume] {
        let texte = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texte.isEmpty else { return [] }
        var trouves: [TitreResume] = []
        switch type {
        case .film:
            if let annee {
                trouves += try await recherche.rechercherFilms(texte, annee: annee, page: 1).resultats.map(\.titreResume)
            }
            trouves += try await recherche.rechercherFilms(texte, page: 1).resultats.map(\.titreResume)
        case .serie:
            trouves += try await recherche.rechercherSeries(texte, page: 1).resultats.map(\.titreResume)
        }
        var vus = Set<ReferenceTitre>()
        let uniques = trouves.filter { vus.insert($0.reference).inserted }
        guard let annee else { return uniques }
        // L'année lue d'abord (à un an près), puis le reste dans l'ordre de TMDB.
        let proches = uniques.filter { ($0.date?.annee).map { abs($0 - annee) <= Rattacheur.toleranceAnnees } == true }
            .sorted { $0.nombreVotes > $1.nombreVotes }
        return proches + uniques.filter { titre in !proches.contains { $0.reference == titre.reference } }
    }
}

extension TitreResume {
    /// Pour le guide TV, qui rattache des candidats.
    public var candidat: CandidatRattachement {
        CandidatRattachement(tmdbID: reference.tmdbID, type: reference.type, titre: titre, titreOriginal: titreOriginal,
                             annee: date?.annee, cheminAffiche: cheminAffiche, cheminFond: cheminFond)
    }
}

/// Ce qu'on identifie à la main (8.4) : une vidéo du NAS ou un film du guide TV que Séance n'a pas su reconnaître seule
/// dans TMDB — deux films du même nom la même année, un nom de fichier illisible, un titre traduit autrement.
public struct DemandeIdentification: Identifiable, Hashable, Sendable {
    public enum Cible: Hashable, Sendable {
        case nas(chemin: String)
        case guide(titre: String, annee: Int?)
    }

    public let cible: Cible
    /// Ce qu'on montre en tête : le nom du fichier, ou le titre du programme.
    public let nom: String
    /// La première recherche, modifiable.
    public let recherche: String
    public let annee: Int?
    public let type: TypeTitre

    public var id: String {
        switch cible {
        case .nas(let chemin): "nas|\(chemin)"
        case .guide(let titre, let annee): "guide|\(titre)|\(annee ?? 0)"
        }
    }

    public static func nas(chemin: String) -> DemandeIdentification {
        let analyse = AnalyseNomFichier.analyser(chemin: "/" + chemin)
        let nom = (chemin as NSString).lastPathComponent
        return DemandeIdentification(cible: .nas(chemin: chemin), nom: nom,
                                     recherche: analyse?.titre ?? (nom as NSString).deletingPathExtension,
                                     annee: analyse?.annee, type: analyse?.type ?? .film)
    }

    public static func guide(titre: String, annee: Int?) -> DemandeIdentification {
        DemandeIdentification(cible: .guide(titre: titre, annee: annee), nom: annee.map { "\(titre) (\($0))" } ?? titre,
                              recherche: titre, annee: annee, type: .film)
    }

    /// Un choix déjà fait, à changer : la clé dit s'il vient du NAS ou du guide.
    public static func depuis(cle: String, nom: String?) -> DemandeIdentification? {
        guard let nom else { return nil }
        if cle.hasPrefix("guide|") { return .guide(titre: nom, annee: cle.split(separator: "|").last.flatMap { Int($0) }) }
        return .nas(chemin: nom)
    }
}
