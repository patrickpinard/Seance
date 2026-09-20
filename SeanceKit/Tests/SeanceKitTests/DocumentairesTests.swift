import Foundation
import Testing
@testable import SeanceKit

@Suite("Documentaires")
struct DocumentairesTests {
    private func dictionnaire(_ items: [URLQueryItem]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func lesCriteresDemandentLeGenreDocumentaire() {
        let films = dictionnaire(CriteresDecouverte.documentaires(.film, motsCles: [6917, 9663]).parametres(pour: .film))
        #expect(films["with_genres"] == "99")
        #expect(films["with_keywords"] == "6917|9663")
        #expect(films["sort_by"] == "popularity.desc")
        // Une série documentaire se demande sur la date de diffusion de ses épisodes, pas sur une date de sortie.
        let series = dictionnaire(CriteresDecouverte.documentaires(.serie).parametres(pour: .serie))
        #expect(series["with_genres"] == "99")
        #expect(series["with_keywords"] == nil)
        #expect(series["air_date.gte"] != nil)
    }

    @Test func chaqueThemeADesTermesEtUnLibelle() {
        for theme in ThemeDocumentaire.allCases {
            #expect(!theme.libelle.isEmpty)
            #expect(!theme.symbole.isEmpty)
            #expect(!theme.termes.isEmpty, "le thème \(theme.libelle) n'a aucun mot-clé à chercher")
        }
        #expect(Set(ThemeDocumentaire.allCases.map(\.libelle)).count == ThemeDocumentaire.allCases.count)
    }

    @Test func chercheLesMotsClesDUnTheme() async throws {
        let corps = Data("""
        {"page":1,"results":[{"id":6917,"name":"nature"},{"id":158718,"name":"nature documentary"}],"total_pages":1,"total_results":2}
        """.utf8)
        let transport = TransportSimule([.init(code: 200, corps: corps)])
        let client = TMDBClient(identifiants: .jetonLecture("t"), transport: transport)

        let page = try await client.motsCles("nature")
        #expect(page.resultats.map(\.id) == [6917, 158718])
        #expect(page.resultats.first?.nom == "nature")

        let requetes = await transport.requetes
        let url = try #require(requetes.first?.url)
        #expect(url.path() == "/3/search/keyword")
        #expect(url.query()?.contains("query=nature") == true)
    }
}
