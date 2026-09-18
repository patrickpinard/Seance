import Foundation
import Testing
@testable import SeanceKit

@Suite("Cache des réponses TMDB")
struct CacheTMDBTests {
    /// Un réseau de théâtre : compte ses appels, et peut tomber en panne.
    final class Reseau: TransportHTTP, @unchecked Sendable {
        var appels = 0
        var enPanne = false
        var code = 200

        func envoyer(_ requete: URLRequest) async throws -> (Data, HTTPURLResponse) {
            appels += 1
            if enPanne { throw URLError(.notConnectedToInternet) }
            let reponse = HTTPURLResponse(url: requete.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            return (Data("réponse \(appels)".utf8), reponse)
        }
    }

    final class Horloge: @unchecked Sendable {
        var date = Date(timeIntervalSince1970: 1_789_000_000)
    }

    private func dossier() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("cache-tmdb-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func uneFicheRelueDansLaJourneeNeRepartPasSurLeReseau() async throws {
        let reseau = Reseau()
        let horloge = Horloge()
        let cache = CacheTMDB(reseau: reseau, dossier: dossier(), maintenant: { horloge.date })
        let fiche = URLRequest(url: URL(string: "https://api.themoviedb.org/3/movie/949?api_key=SECRET&language=fr-FR")!)

        #expect(String(decoding: try await cache.envoyer(fiche).0, as: UTF8.self) == "réponse 1")
        #expect(String(decoding: try await cache.envoyer(fiche).0, as: UTF8.self) == "réponse 1")
        #expect(reseau.appels == 1)

        // Le lendemain, la fiche est relue ; une liste, elle, ne reste fraîche qu'une heure.
        horloge.date += 25 * 3600
        #expect(String(decoding: try await cache.envoyer(fiche).0, as: UTF8.self) == "réponse 2")
        #expect(CacheTMDB.fraicheur("/3/discover/movie") == 3600)
        #expect(CacheTMDB.fraicheur("/3/movie/949/watch/providers") == 12 * 3600)
    }

    @Test func sansReseauUneReponseAncienneVautMieuxQueRien() async throws {
        let reseau = Reseau()
        let horloge = Horloge()
        let cache = CacheTMDB(reseau: reseau, dossier: dossier(), maintenant: { horloge.date })
        let liste = URLRequest(url: URL(string: "https://api.themoviedb.org/3/discover/movie?page=1")!)
        _ = try await cache.envoyer(liste)

        horloge.date += 5 * 86_400
        reseau.enPanne = true
        #expect(String(decoding: try await cache.envoyer(liste).0, as: UTF8.self) == "réponse 1")

        // Jamais vue : l'erreur remonte, comme avant.
        let inconnue = URLRequest(url: URL(string: "https://api.themoviedb.org/3/movie/1")!)
        await #expect(throws: URLError.self) { _ = try await cache.envoyer(inconnue) }
    }

    @Test func laCleNEstPasDansLeNomEtUneErreurNEstPasGardee() async throws {
        let avec = URL(string: "https://api.themoviedb.org/3/movie/949?language=fr-FR&api_key=SECRET")!
        let sans = URL(string: "https://api.themoviedb.org/3/movie/949?language=fr-FR")!
        #expect(CacheTMDB.nom(avec) == CacheTMDB.nom(sans))
        #expect(!CacheTMDB.nom(avec).contains("SECRET"))

        let reseau = Reseau()
        reseau.code = 401
        let cache = CacheTMDB(reseau: reseau, dossier: dossier())
        _ = try await cache.envoyer(URLRequest(url: sans))
        _ = try await cache.envoyer(URLRequest(url: sans))
        #expect(reseau.appels == 2, "Une clé refusée ne doit pas être rejouée depuis le cache")
    }
}
