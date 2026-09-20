import Foundation

/// « Regarder sur Netflix » : TMDB dit sur quelle plateforme un titre est inclus, pas à quelle adresse. Séance ouvre
/// donc la recherche de la plateforme sur le nom du titre : un lien universel, que l'app de la plateforme reprend
/// quand elle est installée, et le navigateur sinon. Seules les plateformes dont l'adresse de recherche est connue
/// ont un lien ; les autres se contentent de leur nom.
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
