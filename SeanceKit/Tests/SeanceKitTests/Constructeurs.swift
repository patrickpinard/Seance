import Foundation
@testable import SeanceKit

/// Fabrique des valeurs de test à partir de JSON au format TMDB : les types TMDB n'ont pas
/// d'initialiseur public, seulement leur décodage.
enum Construire {
    static func decoder<T: Decodable>(_ type: T.Type, _ json: Any) -> T {
        let donnees = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(T.self, from: donnees)
    }

    static func fournisseur(_ id: Int, _ nom: String, priorite: Int = 1) -> Fournisseur {
        Fournisseur(id: id, nom: nom, cheminLogo: nil, priorite: priorite)
    }

    static func offres(abonnement: [Fournisseur] = [], location: [Fournisseur] = [], achat: [Fournisseur] = [], gratuit: [Fournisseur] = []) -> OffresRegion {
        func json(_ liste: [Fournisseur]) -> [[String: Any]] {
            liste.map { ["provider_id": $0.id, "provider_name": $0.nom, "display_priority": $0.priorite] }
        }
        return decoder(OffresRegion.self, ["flatrate": json(abonnement), "rent": json(location), "buy": json(achat), "free": json(gratuit)])
    }

    static func episode(_ saison: Int, _ numero: Int, diffuse: String?, duree: Int = 45) -> EpisodeTMDB {
        EpisodeTMDB(id: saison * 100 + numero, nom: "Épisode \(numero)", synopsis: "", numero: numero, saison: saison,
                    dureeMinutes: duree, cheminImage: nil, noteMoyenne: nil, dateDiffusionBrute: diffuse)
    }

    /// La fiche Game of Thrones de la spécification, avec statut et prochain épisode modifiables.
    static func serie(statut: String = "Returning Series", prochain: EpisodeTMDB? = nil) throws -> SerieDetail {
        var json = try JSONSerialization.jsonObject(with: Fixture.donnees("tv_details")) as! [String: Any]
        json["status"] = statut
        if let prochain {
            json["next_episode_to_air"] = [
                "id": prochain.id, "name": prochain.nom, "overview": "", "episode_number": prochain.numero,
                "season_number": prochain.saison, "air_date": prochain.dateDiffusion?.description ?? "",
            ]
        } else {
            json["next_episode_to_air"] = NSNull()
        }
        return decoder(SerieDetail.self, json)
    }

    static func datesDeSortie(ch sorties: [(type: Int, date: String)]) -> DatesDeSortie {
        decoder(DatesDeSortie.self, ["results": [[
            "iso_3166_1": "CH",
            "release_dates": sorties.map { ["certification": "", "release_date": $0.date, "type": $0.type] },
        ]]])
    }
}

extension Date {
    /// Heure de Suisse, par exemple `Date.suisse("2026-09-17 21:10")`.
    static func suisse(_ texte: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .suisse
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: texte)!
    }
}
