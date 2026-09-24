import Foundation

/// « Regarder sur Netflix » : TMDB dit sur quelle plateforme un titre est inclus, pas à quelle adresse. Depuis la 6.1,
/// Séance ouvre le titre lui-même quand Wikidata connaît son identifiant chez la plateforme (`direct`) ; sinon la
/// recherche de la plateforme sur le nom du titre. Ce sont des liens universels, que l'app de la plateforme reprend
/// quand elle est installée, et le navigateur sinon. Seules les plateformes dont l'adresse est connue ont un lien ;
/// les autres se contentent de leur nom.
public enum LiensPlateformes {
    /// Identifiants TMDB des plateformes, et leur adresse de recherche (le titre remplace « {q} »).
    private static let recherches: [Int: String] = [
        8: "https://www.netflix.com/search?q={q}",                       // Netflix
        1796: "https://www.netflix.com/search?q={q}",                    // Netflix avec pub
        9: "https://www.primevideo.com/search?phrase={q}",               // Amazon Prime Video
        119: "https://www.primevideo.com/search?phrase={q}",             // Amazon Prime Video (ancien identifiant)
        10: "https://www.primevideo.com/search?phrase={q}",              // Amazon Video
        337: "https://www.disneyplus.com/search?q={q}",                  // Disney+
        350: "https://tv.apple.com/search?term={q}",                     // Apple TV+
        2: "https://tv.apple.com/search?term={q}",                       // Apple TV (location, achat)
        531: "https://www.paramountplus.com/search/?q={q}",              // Paramount+
        381: "https://www.canalplus.com/recherche/?q={q}",               // Canal+
        283: "https://www.crunchyroll.com/search?q={q}",                 // Crunchyroll
        11: "https://mubi.com/search/films?query={q}",                   // MUBI
        691: "https://www.playsuisse.ch/search?q={q}",                   // Play Suisse
        3: "https://play.google.com/store/search?c=movies&q={q}",        // Google Play Films
        192: "https://www.youtube.com/results?search_query={q}",         // YouTube
    ]

    /// Le lien qui ouvre le titre lui-même (6.1), quand Wikidata connaît son identifiant chez la plateforme ; `nil` sinon,
    /// et la recherche prend le relais. Des liens universels, que l'app de la plateforme reprend :
    /// - Netflix : un film se lance directement (`/watch`), une série s'ouvre sur sa page (`/title`) ;
    /// - Apple TV : `action=play` lance la lecture quand le titre est inclus dans l'abonnement (Apple TV+), pas pour la
    ///   location ou l'achat ;
    /// - Disney+ : la page du titre ;
    /// - Prime Video : aucun — Wikidata ne connaît que les références d'Amazon.com, introuvables en Suisse.
    public static func direct(plateforme id: Int, reference: ReferenceTitre, identifiants: IdentifiantsPlateformes) -> URL? {
        let film = reference.type == .film
        switch id {
        case 8, 1796:
            guard let netflix = identifiants.netflix else { return nil }
            return URL(string: "https://www.netflix.com/\(film ? "watch" : "title")/\(netflix)")
        case 350, 2:
            guard let apple = identifiants.appleTV else { return nil }
            return URL(string: "https://tv.apple.com/ch/\(film ? "movie" : "show")/\(apple)\(id == 350 ? "?action=play" : "")")
        case 337:
            guard let disney = identifiants.disney else { return nil }
            return URL(string: "https://www.disneyplus.com/\(film ? "movies/wd" : "series/wp")/\(disney)")
        default:
            return nil
        }
    }

    /// Les adresses à essayer sur l'Apple TV (6.6), dans l'ordre. tvOS ne se comporte pas comme iOS : un lien
    /// universel `https://www.netflix.com/watch/…` y ouvre Netflix sur sa page d'accueil, jamais sur le titre. Le
    /// schéma de l'app — `nflx://` — lance, lui, le bon film. On essaie donc d'abord le schéma natif avec l'identifiant
    /// exact, puis le lien universel (que l'app TV d'Apple, elle, comprend), puis la recherche.
    public static func liensTV(plateforme id: Int, titre: String, reference: ReferenceTitre,
                               identifiants: IdentifiantsPlateformes?) -> [URL] {
        var liens: [URL] = []
        let film = reference.type == .film
        if let identifiants {
            switch id {
            case 8, 1796:
                if let netflix = identifiants.netflix {
                    liens.append(URL(string: "nflx://www.netflix.com/\(film ? "watch" : "title")/\(netflix)")!)
                }
            case 337:
                if let disney = identifiants.disney {
                    liens.append(URL(string: "disneyplus://\(film ? "movies/wd" : "series/wp")/\(disney)")!)
                }
            default:
                break
            }
            if let direct = direct(plateforme: id, reference: reference, identifiants: identifiants) { liens.append(direct) }
        }
        if let recherche = lien(plateforme: id, titre: titre) { liens.append(recherche) }
        return liens
    }

    /// Les plateformes dont Séance sait ouvrir un titre précis : ce n'est que pour elles que Wikidata vaut la peine.
    public static let avecLienDirect: Set<Int> = [8, 1796, 350, 2, 337]

    /// Le meilleur lien : le titre lui-même quand son identifiant est connu, la recherche sinon.
    public static func lien(plateforme id: Int, titre: String, reference: ReferenceTitre, identifiants: IdentifiantsPlateformes?) -> URL? {
        identifiants.flatMap { direct(plateforme: id, reference: reference, identifiants: $0) } ?? lien(plateforme: id, titre: titre)
    }

    /// L'adresse qui ouvre la recherche de `titre` sur la plateforme ; `nil` pour une plateforme sans adresse connue.
    public static func lien(plateforme id: Int, titre: String) -> URL? {
        let nettoye = titre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nettoye.isEmpty, let modele = recherches[id] else { return nil }
        var permis = CharacterSet.urlQueryAllowed
        permis.remove(charactersIn: "&+=?#")
        guard let q = nettoye.addingPercentEncoding(withAllowedCharacters: permis) else { return nil }
        return URL(string: modele.replacingOccurrences(of: "{q}", with: q))
    }
}

/// blue TV (Swisscom), 6.1 : le numéro de chaque chaîne du guide dans blue TV, relevé dans la liste publique de Swisscom
/// (`services.sg101.prd.sctv.ch/portfolio/tv/channels`), et le lien qui ouvre la chaîne en direct. L'app blue TV reprend
/// les liens `tv.blue.ch/app/…` ; le lecteur web, lui, vit à `tv.blue.ch/player/livetv/<numéro>` — c'est lui que le Mac
/// ouvre, faute d'app blue TV. Swisscom n'a pas d'API publique : rien d'autre n'est possible, ni replay ni enregistrement.
public enum LiensChaines {
    /// Identifiant XMLTV → numéro de la chaîne dans blue TV.
    static let blueTV: [String: Int] = [
        "RTSUn.ch": 369, "RTSDeux.ch": 367,
        "TF1.fr": 601, "France2.fr": 182, "France3.fr": 184, "France5.fr": 186, "M6.fr": 249,
        "Arte.fr": 28, "W9.fr": 653, "TMC.fr": 609, "NT1.fr": 295, "6ter.fr": 9,
    ]

    /// Le numéro d'une chaîne du guide dans blue TV.
    public static func numero(chaine idGuide: String) -> Int? {
        blueTV[idGuide]
    }

    /// Le lecteur web de blue TV, sur la chaîne en direct : c'est ce qu'ouvre le Mac, faute d'app blue TV.
    public static func siteBlueTV(chaine idGuide: String) -> URL? {
        blueTV[idGuide].flatMap { URL(string: "https://tv.blue.ch/player/livetv/\($0)") }
    }

    /// L'app blue TV (« TV Air »), qui s'ouvre par son adresse `tvguide://` — celle que son propre lecteur web utilise
    /// pour passer à l'app (6.3). `emission` : l'identifiant Swisscom de ce qui passe, pour ouvrir dessus ; sans lui,
    /// l'app s'ouvre sur son guide.
    public static func appBlueTV(emission: String? = nil) -> URL? {
        guard let emission, !emission.isEmpty else { return URL(string: "tvguide://T=tvguide") }
        let permis = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard emission.unicodeScalars.allSatisfy({ permis.contains($0) && $0.isASCII }) else { return URL(string: "tvguide://T=tvguide") }
        return URL(string: "tvguide://T=tvguide&I=\(emission)&AssetType=tvBroadcast")
    }
}

/// Ce qui passe en ce moment sur une chaîne de blue TV (6.3), lu dans le catalogue public de Swisscom — sans compte ni
/// clé, et sans rien dire de l'utilisateur. Sert à ouvrir l'app blue TV sur l'émission : son adresse `tvguide://` veut
/// l'identifiant d'une émission, pas celui d'une chaîne.
public struct CatalogueBlueTV: Sendable {
    private let transport: any TransportHTTP

    public init(transport: any TransportHTTP) {
        self.transport = transport
    }

    public static func requete(chaine numero: Int, autour instant: Date) -> URLRequest {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "UTC")
        format.dateFormat = "yyyyMMddHHmm"
        let debut = format.string(from: instant.addingTimeInterval(-60))
        let fin = format.string(from: instant.addingTimeInterval(60))
        let adresse = "https://services.sg101.prd.sctv.ch/catalog/tv/channels/list/(end=\(fin);ids=\(numero);level=normal;start=\(debut))"
        var requete = URLRequest(url: URL(string: adresse)!, timeoutInterval: 8)
        requete.setValue("Seance/6.3 (application personnelle)", forHTTPHeaderField: "User-Agent")
        return requete
    }

    private struct Reponse: Decodable {
        struct Liste<Element: Decodable>: Decodable { let Items: [Element]? }
        struct Chaine: Decodable { let Content: Contenu? }
        struct Contenu: Decodable { let Nodes: Liste<Emission>? }
        struct Emission: Decodable {
            let Identifier: String?
            let Availabilities: [Creneau]?
        }
        struct Creneau: Decodable {
            let AvailabilityStart: String?
            let AvailabilityEnd: String?
        }
        let Nodes: Liste<Chaine>?
    }

    /// L'identifiant de l'émission qui couvre `instant` ; à défaut, la première renvoyée.
    public static func lire(_ donnees: Data, a instant: Date) -> String? {
        guard let reponse = try? JSONDecoder().decode(Reponse.self, from: donnees) else { return nil }
        let emissions = (reponse.Nodes?.Items ?? []).flatMap { $0.Content?.Nodes?.Items ?? [] }
        let iso = ISO8601DateFormatter()
        func couvre(_ emission: Reponse.Emission) -> Bool {
            guard let creneau = emission.Availabilities?.first,
                  let debut = creneau.AvailabilityStart.flatMap(iso.date(from:)),
                  let fin = creneau.AvailabilityEnd.flatMap(iso.date(from:)) else { return false }
            return debut <= instant && instant < fin
        }
        return (emissions.first(where: couvre) ?? emissions.first)?.Identifier
    }

    /// `nil` si le catalogue ne répond pas : l'app blue TV s'ouvrira alors sur son guide.
    public func emission(chaine numero: Int, a instant: Date = .now) async -> String? {
        guard let (donnees, reponse) = try? await transport.envoyer(Self.requete(chaine: numero, autour: instant)),
              reponse.statusCode == 200 else { return nil }
        return Self.lire(donnees, a: instant)
    }
}
