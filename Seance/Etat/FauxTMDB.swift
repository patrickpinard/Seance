#if DEBUG
import Foundation
import SeanceKit

/// Un TMDB de théâtre pour les tests d'interface dans le simulateur (`SEANCE_FAUX_TMDB=<dossier>`) : il répond avec
/// les réponses réelles enregistrées pour les tests de SeanceKit (`SeanceKit/Tests/SeanceKitTests/Fixtures`), lues
/// sur le disque du Mac. Sans clé ni réseau, l'Accueil, Ce soir, Explorer et les fiches s'affichent donc, toujours
/// pareils, et se laissent tester et capturer. Les affiches, elles, viennent du vrai serveur d'images.
/// Jamais dans l'app installée : ce fichier n'existe qu'en développement.
struct FauxTMDB: TransportHTTP {
    let dossier: URL

    static var dossierDemande: URL? {
        ProcessInfo.processInfo.environment["SEANCE_FAUX_TMDB"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Les titres de la démonstration (voir Demonstration.swift), pour que leurs fiches portent leur nom.
    private static let titresConnus: [Int: (nom: String, affiche: String)] = [
        245_891: ("John Wick", "/7yCzmVL0BI1aSvzgN3jCtXLtyFR.jpg"), 603_692: ("John Wick : Chapitre 4", "/n1YTIyhAqqqFyDGFTzV7WaU1JfK.jpg"),
        76_341: ("Mad Max : Fury Road", "/oLy2V6AWSEfdPgKOtrSGnwB3Q2R.jpg"), 94_329: ("The Raid", "/e0EeE8Rc5weReJNpwOP78DuCxdH.jpg"),
        545_609: ("Tyler Rake", "/qVHWs56TvXCKGjsmghWHFRqtKlF.jpg"), 361_743: ("Top Gun : Maverick", "/uuwi4wwG6HAHVqaEvJDx6gI773N.jpg"),
        353_081: ("Mission : Impossible - Fallout", "/6JO3Oz685phBaADyJtf4wmaafYj.jpg"), 615_457: ("Nobody", "/jKRzh9y5YjYNISbeh55FQwetsSu.jpg"),
        562: ("Piège de cristal", "/1nOVVjbf8ucbeLmIlK5D2kCQQST.jpg"), 324_552: ("John Wick : Chapitre 2", "/r687UV1zQ5KDB9AxRokRscWIRvt.jpg"),
        949: ("Heat", "/umSVjVdbVwtx5ryCA2QXL44Durm.jpg"),
        108_978: ("Reacher", "/qrJOCIAcvPmyZ63KajWTalQtqPT.jpg"), 73_375: ("Jack Ryan", "/sEAUJohzgehanmml9nul3sfIlVr.jpg"),
        129_552: ("The Night Agent", "/vxCFNBGQ9AeI6GLtnpML1gKuSSK.jpg"),
    ]

    private static let pageVide = Data(#"{"page":1,"results":[],"total_pages":1,"total_results":0}"#.utf8)

    func envoyer(_ requete: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = requete.url ?? TMDBClient.urlBase
        let morceaux = url.path.split(separator: "/").map(String.init).dropFirst() // sans « 3 »
        let (fichier, identifiant) = Self.reponse(Array(morceaux))
        var donnees = fichier.flatMap { try? Data(contentsOf: dossier.appendingPathComponent($0)) }
        // La fiche enregistrée est celle d'un seul titre : elle prend l'identifiant demandé, pour que les listes,
        // la soirée et les fiches parlent du même titre.
        if let identifiant, let lues = donnees, var objet = try? JSONSerialization.jsonObject(with: lues) as? [String: Any] {
            objet["id"] = identifiant
            // Un titre que la démonstration connaît garde son nom et son affiche ; sans image de fond connue, la
            // carte se rabat sur l'affiche — mieux que la même image de fond pour tous les titres.
            if let connu = Self.titresConnus[identifiant] {
                objet[objet["title"] != nil ? "title" : "name"] = connu.nom
                objet["poster_path"] = connu.affiche
                objet["backdrop_path"] = NSNull()
            }
            donnees = try? JSONSerialization.data(withJSONObject: objet)
        }
        let code = donnees == nil && fichier != nil ? 404 : 200
        let reponse = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        return (donnees ?? (code == 200 ? Self.pageVide : Data(#"{"status_message":"Absent du faux TMDB"}"#.utf8)), reponse)
    }

    /// Le fichier qui répond à un chemin, et l'identifiant à y inscrire pour une fiche. `nil` : une page vide.
    private static func reponse(_ chemin: [String]) -> (fichier: String?, identifiant: Int?) {
        switch chemin.count {
        case 2 where chemin[0] == "discover":
            return (chemin[1] == "movie" ? "discover_movie.json" : "discover_tv.json", nil)
        case 2 where chemin[0] == "search":
            return (chemin[1] == "movie" ? "search_movie.json" : nil, nil)
        case 3 where chemin[0] == "genre":
            return ("genre_movie_list.json", nil)
        case 3 where chemin[0] == "watch" && chemin[1] == "providers":
            return ("watch_providers_movie.json", nil)
        case 2 where chemin[0] == "movie":
            return ("fiche_film.json", Int(chemin[1]))
        case 2 where chemin[0] == "tv":
            return ("fiche_serie.json", Int(chemin[1]))
        case 2 where chemin[0] == "person":
            return ("absent.json", nil)
        case 3 where chemin[2] == "combined_credits":
            return ("person_combined_credits.json", nil)
        case 3 where chemin[2] == "release_dates":
            return ("movie_release_dates.json", nil)
        case 4 where chemin[2] == "watch":
            return ("movie_watch_providers.json", nil)
        case 4 where chemin[2] == "season":
            return ("tv_season.json", nil)
        default:
            return (nil, nil)
        }
    }
}
#endif
