import Foundation

/// Les identifiants d'un titre chez les plateformes (6.1). TMDB dit sur quelle plateforme un titre est inclus, pas à
/// quelle adresse ; Wikidata, base publique et gratuite, relie l'identifiant TMDB à ceux de Netflix, d'Apple TV, de
/// Disney+ et de Prime Video — sans clé ni compte. La couverture est large pour les titres connus, partielle ailleurs :
/// sans identifiant, Séance garde la recherche de la plateforme (`LiensPlateformes.lien(plateforme:titre:)`).
public struct IdentifiantsPlateformes: Codable, Sendable, Hashable {
    public var netflix: String?
    public var appleTV: String?
    public var disney: String?
    /// Lu mais pas utilisé : ce sont les références d'Amazon.com (États-Unis), introuvables sur Prime Video en Suisse.
    public var prime: String?

    public init(netflix: String? = nil, appleTV: String? = nil, disney: String? = nil, prime: String? = nil) {
        self.netflix = netflix
        self.appleTV = appleTV
        self.disney = disney
        self.prime = prime
    }

    public var estVide: Bool {
        netflix == nil && appleTV == nil && disney == nil && prime == nil
    }
}

/// La requête SPARQL et la lecture de sa réponse. Un seul aller-retour pour un lot de titres : les films par la
/// propriété P4947 (identifiant TMDB d'un film), les séries par P4983 (identifiant TMDB d'une série).
public enum RequeteWikidata {
    public static let adresse = URL(string: "https://query.wikidata.org/sparql")!
    /// Au-delà, la requête s'allonge sans rien gagner : les lots plus grands sont coupés.
    public static let tailleLot = 60

    /// Films : Apple TV P9586, Disney+ P7595 ; séries : Apple TV P9751, Disney+ P7596 ; Netflix P1874 et Prime Video
    /// P8055 pour les deux. Les identifiants TMDB sont des nombres : rien d'autre n'entre dans le texte de la requête.
    public static func sparql(_ references: [ReferenceTitre]) -> String {
        let films = references.filter { $0.type == .film }.map { "\"\($0.tmdbID)\"" }
        let series = references.filter { $0.type == .serie }.map { "\"\($0.tmdbID)\"" }
        var blocs: [String] = []
        if !films.isEmpty {
            blocs.append("""
            { VALUES ?film { \(films.joined(separator: " ")) } ?item wdt:P4947 ?film .
              OPTIONAL { ?item wdt:P9586 ?apple } OPTIONAL { ?item wdt:P7595 ?disney } }
            """)
        }
        if !series.isEmpty {
            blocs.append("""
            { VALUES ?serie { \(series.joined(separator: " ")) } ?item wdt:P4983 ?serie .
              OPTIONAL { ?item wdt:P9751 ?apple } OPTIONAL { ?item wdt:P7596 ?disney } }
            """)
        }
        return """
        SELECT ?film ?serie ?netflix ?prime ?apple ?disney WHERE {
          \(blocs.joined(separator: "\n  UNION\n  "))
          OPTIONAL { ?item wdt:P1874 ?netflix }
          OPTIONAL { ?item wdt:P8055 ?prime }
        }
        """
    }

    /// Une requête GET, réponse en JSON. L'en-tête d'identification nomme l'app, comme le demande Wikidata, et rien de
    /// plus : aucune donnée personnelle ne part avec.
    public static func requete(_ references: [ReferenceTitre]) -> URLRequest {
        var composants = URLComponents(url: adresse, resolvingAgainstBaseURL: false)!
        composants.queryItems = [URLQueryItem(name: "query", value: sparql(references))]
        var requete = URLRequest(url: composants.url!, timeoutInterval: 20)
        requete.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        requete.setValue("Seance/6.1 (application personnelle)", forHTTPHeaderField: "User-Agent")
        return requete
    }

    private struct Reponse: Decodable {
        struct Resultats: Decodable { let bindings: [[String: Valeur]] }
        struct Valeur: Decodable { let value: String }
        let results: Resultats
    }

    /// Un titre peut revenir sur plusieurs lignes (deux identifiants Netflix, par exemple) : le premier de chaque
    /// plateforme est gardé. Les identifiants aux caractères inattendus sont écartés : ils finissent dans une adresse.
    public static func lire(_ donnees: Data) throws -> [ReferenceTitre: IdentifiantsPlateformes] {
        let reponse = try JSONDecoder().decode(Reponse.self, from: donnees)
        var resultat: [ReferenceTitre: IdentifiantsPlateformes] = [:]
        for ligne in reponse.results.bindings {
            let reference: ReferenceTitre
            if let film = ligne["film"].flatMap({ Int($0.value) }) {
                reference = ReferenceTitre(type: .film, tmdbID: film)
            } else if let serie = ligne["serie"].flatMap({ Int($0.value) }) {
                reference = ReferenceTitre(type: .serie, tmdbID: serie)
            } else {
                continue
            }
            var identifiants = resultat[reference] ?? IdentifiantsPlateformes()
            identifiants.netflix = identifiants.netflix ?? propre(ligne["netflix"]?.value)
            identifiants.appleTV = identifiants.appleTV ?? propre(ligne["apple"]?.value)
            identifiants.disney = identifiants.disney ?? propre(ligne["disney"]?.value)
            identifiants.prime = identifiants.prime ?? propre(ligne["prime"]?.value)
            resultat[reference] = identifiants
        }
        return resultat
    }

    static func propre(_ valeur: String?) -> String? {
        guard let valeur, !valeur.isEmpty, valeur.count <= 80 else { return nil }
        let permis = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        guard valeur.unicodeScalars.allSatisfy({ permis.contains($0) && $0.isASCII }) else { return nil }
        return valeur
    }
}

/// Les identifiants déjà lus, gardés sur l'appareil : trente jours pour un titre trouvé, sept pour un titre que Wikidata
/// ne connaît pas encore. Les demandes simultanées (les cartes d'une soirée qui s'affichent ensemble) partent en un seul
/// lot ; une erreur de réseau ne laisse rien en mémoire, et le titre retombe sur la recherche de la plateforme.
public actor ReserveIdentifiants {
    struct Entree: Codable, Sendable {
        var identifiants: IdentifiantsPlateformes
        var luLe: Date
    }

    private let transport: (any TransportHTTP)?
    private let fichier: URL?
    private var entrees: [String: Entree]
    private var enVol: [ReferenceTitre: Task<[ReferenceTitre: IdentifiantsPlateformes]?, Never>] = [:]

    static let validiteTrouve: TimeInterval = 30 * 86_400
    static let validiteInconnu: TimeInterval = 7 * 86_400

    /// `transport` nul : rien ne part sur le réseau (démonstration, tests d'interface), seuls les identifiants gardés servent.
    public init(transport: (any TransportHTTP)?, fichier: URL?) {
        self.transport = transport
        self.fichier = fichier
        entrees = fichier.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: Entree].self, from: $0) } ?? [:]
    }

    private static func cle(_ reference: ReferenceTitre) -> String {
        "\(reference.type.rawValue)-\(reference.tmdbID)"
    }

    private func frais(_ entree: Entree, maintenant: Date) -> Bool {
        let validite = entree.identifiants.estVide ? Self.validiteInconnu : Self.validiteTrouve
        return maintenant.timeIntervalSince(entree.luLe) < validite
    }

    /// Ce qui est déjà connu, sans réseau.
    public func connus(_ reference: ReferenceTitre) -> IdentifiantsPlateformes? {
        entrees[Self.cle(reference)]?.identifiants
    }

    /// Les identifiants d'un lot de titres : ce qui est gardé et encore frais, le reste demandé à Wikidata en un lot.
    public func identifiants(_ references: [ReferenceTitre], maintenant: Date = .now) async -> [ReferenceTitre: IdentifiantsPlateformes] {
        var resultat: [ReferenceTitre: IdentifiantsPlateformes] = [:]
        var manquants: [ReferenceTitre] = []
        for reference in Set(references) {
            if let entree = entrees[Self.cle(reference)], frais(entree, maintenant: maintenant) {
                resultat[reference] = entree.identifiants
            } else if enVol[reference] == nil {
                manquants.append(reference)
            }
        }
        if let transport, !manquants.isEmpty {
            for debut in stride(from: 0, to: manquants.count, by: RequeteWikidata.tailleLot) {
                let lot = Array(manquants[debut..<min(debut + RequeteWikidata.tailleLot, manquants.count)])
                let tache = Task { await Self.chercher(lot, transport: transport) }
                for reference in lot { enVol[reference] = tache }
            }
        }
        // Les tâches sont relevées avant d'attendre : une demande simultanée pour le même titre attend le même lot.
        var taches: [ReferenceTitre: Task<[ReferenceTitre: IdentifiantsPlateformes]?, Never>] = [:]
        for reference in Set(references) where resultat[reference] == nil {
            if let tache = enVol[reference] { taches[reference] = tache }
        }
        for (reference, tache) in taches {
            let trouves = await tache.value
            if enVol[reference] == tache { enVol[reference] = nil }
            guard let trouves else { continue }
            let identifiants = trouves[reference] ?? IdentifiantsPlateformes()
            entrees[Self.cle(reference)] = Entree(identifiants: identifiants, luLe: maintenant)
            resultat[reference] = identifiants
        }
        enregistrer()
        return resultat.filter { !$0.value.estVide }
    }

    private static func chercher(_ lot: [ReferenceTitre], transport: any TransportHTTP) async -> [ReferenceTitre: IdentifiantsPlateformes]? {
        guard let (donnees, reponse) = try? await transport.envoyer(RequeteWikidata.requete(lot)),
              reponse.statusCode == 200 else { return nil }
        return try? RequeteWikidata.lire(donnees)
    }

    private func enregistrer() {
        guard let fichier, let donnees = try? JSONEncoder().encode(entrees) else { return }
        try? donnees.write(to: fichier, options: .atomic)
    }
}
