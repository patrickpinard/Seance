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

    /// La chaîne en direct dans blue TV ; `app` : le lien que l'app reprend (iPhone, iPad, Apple TV), sinon le lecteur web.
    public static func blueTV(chaine idGuide: String, app: Bool) -> URL? {
        guard let numero = blueTV[idGuide] else { return nil }
        return URL(string: "https://tv.blue.ch/\(app ? "app/" : "")player/livetv/\(numero)")
    }
}
