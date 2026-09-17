import Foundation

/// Les genres TMDB en français, livrés avec l'app : sans réseau ou avant la réponse de TMDB, les filtres,
/// les phrases et les statistiques ne montrent jamais « Genre 28 ». Les noms de TMDB les remplacent dès qu'ils arrivent.
public enum GenresParDefaut {
    public static let films: [Genre] = [
        Genre(id: 28, nom: "Action"), Genre(id: 12, nom: "Aventure"), Genre(id: 16, nom: "Animation"),
        Genre(id: 35, nom: "Comédie"), Genre(id: 80, nom: "Crime"), Genre(id: 99, nom: "Documentaire"),
        Genre(id: 18, nom: "Drame"), Genre(id: 10751, nom: "Familial"), Genre(id: 14, nom: "Fantastique"),
        Genre(id: 36, nom: "Histoire"), Genre(id: 27, nom: "Horreur"), Genre(id: 10402, nom: "Musique"),
        Genre(id: 9648, nom: "Mystère"), Genre(id: 10749, nom: "Romance"), Genre(id: 878, nom: "Science-Fiction"),
        Genre(id: 10770, nom: "Téléfilm"), Genre(id: 53, nom: "Thriller"), Genre(id: 10752, nom: "Guerre"),
        Genre(id: 37, nom: "Western"),
    ]

    public static let series: [Genre] = [
        Genre(id: 10759, nom: "Action & Aventure"), Genre(id: 16, nom: "Animation"), Genre(id: 35, nom: "Comédie"),
        Genre(id: 80, nom: "Crime"), Genre(id: 99, nom: "Documentaire"), Genre(id: 18, nom: "Drame"),
        Genre(id: 10751, nom: "Familial"), Genre(id: 10762, nom: "Enfants"), Genre(id: 9648, nom: "Mystère"),
        Genre(id: 10763, nom: "Actualités"), Genre(id: 10764, nom: "Téléréalité"),
        Genre(id: 10765, nom: "Science-Fiction & Fantastique"), Genre(id: 10766, nom: "Feuilleton"),
        Genre(id: 10767, nom: "Talk-show"), Genre(id: 10768, nom: "Guerre & Politique"), Genre(id: 37, nom: "Western"),
    ]

    /// Films et séries en un seul dictionnaire ; les identifiants communs portent le même nom.
    public static var noms: [Int: String] {
        Dictionary((films + series).map { ($0.id, $0.nom) }, uniquingKeysWith: { premier, _ in premier })
    }

    /// Les noms de TMDB l'emportent ; un genre que TMDB n'a pas renvoyé garde son nom par défaut.
    public static func fusionner(_ tmdb: [Genre], defaut: [Genre]) -> [Genre] {
        guard !tmdb.isEmpty else { return defaut }
        let connus = Set(tmdb.map(\.id))
        return tmdb + defaut.filter { !connus.contains($0.id) }
    }
}
