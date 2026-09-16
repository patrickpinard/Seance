import Foundation
import Testing
@testable import SeanceKit

@Suite("Client TMDB")
struct TMDBClientTests {
    private func client(_ transport: TransportSimule, journal: JournalAttentes = JournalAttentes(),
                        identifiants: TMDBClient.Identifiants = .jetonLecture("jeton-test")) -> TMDBClient {
        TMDBClient(identifiants: identifiants, transport: transport) { await journal.noter($0) }
    }

    private func parametres(_ requete: URLRequest) -> [String: String] {
        let items = URLComponents(url: requete.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func jetonDansLEnTete() async throws {
        let transport = TransportSimule([.init(code: 200, corps: try Fixture.donnees("tv_details"))])
        _ = try await client(transport).serie(1399)

        let requete = try #require(await transport.requetes.first)
        #expect(requete.url?.path() == "/3/tv/1399")
        #expect(requete.value(forHTTPHeaderField: "Authorization") == "Bearer jeton-test")
        #expect(parametres(requete)["language"] == "fr-FR")
        #expect(parametres(requete)["api_key"] == nil)
    }

    @Test func cleAPIEnParametre() async throws {
        let transport = TransportSimule([.init(code: 200, corps: try Fixture.donnees("movie_watch_providers"))])
        _ = try await client(transport, identifiants: .cleAPI("cle-test")).fournisseurs(.film, id: 550)

        let requete = try #require(await transport.requetes.first)
        #expect(requete.url?.path() == "/3/movie/550/watch/providers")
        #expect(parametres(requete)["api_key"] == "cle-test")
        #expect(requete.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func decouverteTransmetLesCriteres() async throws {
        let transport = TransportSimule([.init(code: 200, corps: try Fixture.donnees("discover_movie"))])
        var criteres = CriteresDecouverte()
        criteres.genresInclus = [28]
        criteres.fournisseurs = [8]
        let page = try await client(transport).decouvrirFilms(criteres)

        #expect(page.resultats.count == 20)
        let requete = try #require(await transport.requetes.first)
        #expect(requete.url?.path() == "/3/discover/movie")
        #expect(parametres(requete)["with_genres"] == "28")
        #expect(parametres(requete)["watch_region"] == "CH")
    }

    @Test func limiteDeDebitPuisSucces() async throws {
        let journal = JournalAttentes()
        let transport = TransportSimule([
            .init(code: 429, entetes: ["Retry-After": "2"]),
            .init(code: 200, corps: try Fixture.donnees("search_movie")),
        ])
        let page = try await client(transport, journal: journal).rechercherFilms("Fight Club")

        #expect(page.resultats.first?.id == 550)
        #expect(await transport.requetes.count == 2)
        #expect(await journal.durees == [.seconds(2)])
    }

    @Test func limiteDeDebitPersistante() async throws {
        let journal = JournalAttentes()
        let transport = TransportSimule(Array(repeating: .init(code: 429), count: 3))

        await #expect(throws: ErreurTMDB.limiteDepassee) {
            _ = try await client(transport, journal: journal).genres(.film)
        }
        #expect(await transport.requetes.count == 3)
        #expect(await journal.durees == [.seconds(1), .seconds(1)])
    }

    @Test func identifiantsRefuses() async throws {
        let transport = TransportSimule([.init(code: 401)])
        await #expect(throws: ErreurTMDB.identifiantsRefuses) {
            _ = try await client(transport).datesDeSortie(film: 550)
        }
    }

    @Test func messageDErreurTMDB() async throws {
        let corps = Data(#"{"success":false,"status_code":34,"status_message":"The resource you requested could not be found."}"#.utf8)
        let transport = TransportSimule([.init(code: 404, corps: corps)])
        await #expect(throws: ErreurTMDB.http(code: 404, message: "The resource you requested could not be found.")) {
            _ = try await client(transport).serie(0)
        }
    }

    @Test func reponseIllisible() async throws {
        let transport = TransportSimule([.init(code: 200, corps: Data("<html>".utf8))])
        await #expect {
            _ = try await client(transport).serie(1399)
        } throws: { erreur in
            if case ErreurTMDB.decodage = erreur { return true }
            return false
        }
    }
}

@Suite("Format des identifiants TMDB")
struct IdentifiantsTMDBTests {
    @Test func cleV3OuJetonV4() {
        guard case .cleAPI("0123456789abcdef0123456789abcdef") = TMDBClient.Identifiants.depuis(" 0123456789abcdef0123456789abcdef\n") else {
            Issue.record("Une clé de 32 caractères est une clé d'API v3")
            return
        }
        guard case .jetonLecture(let jeton) = TMDBClient.Identifiants.depuis("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abc") else {
            Issue.record("Un JWT est un jeton de lecture v4")
            return
        }
        #expect(jeton.hasPrefix("eyJ"))
    }
}
