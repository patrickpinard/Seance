import Foundation
@testable import SeanceKit
import Testing

@Suite("Widgets : prochains épisodes")
struct InstantaneWidgetsTests {
    private func serie(_ id: Int, _ nom: String, _ numeros: [(Int, Int)]) -> InstantaneWidgets.Serie {
        .init(id: id, nom: nom, cheminAffiche: nil, episodes: numeros.map { .init(saison: $0.0, numero: $0.1, titre: nil, dureeMinutes: 50) })
    }

    @Test func episodesDiffusesDepuisLeProchain() {
        let saison = [
            Construire.episode(2, 5, diffuse: "2026-09-01"),
            Construire.episode(2, 6, diffuse: "2026-09-08"),
            Construire.episode(2, 7, diffuse: "2026-09-15", duree: 0),
            Construire.episode(2, 8, diffuse: "2026-09-22"),
            Construire.episode(2, 4, diffuse: "2026-08-25"),
        ]
        let episodes = InstantaneWidgets.episodes(saison, depuis: NumeroEpisode(saison: 2, episode: 5),
                                                  aujourdhui: DateTMDB(annee: 2026, mois: 9, jour: 17), dureeParDefaut: 50)
        #expect(episodes.map(\.numero) == [5, 6, 7])
        // Une durée TMDB absente ou à zéro prend celle de la série.
        #expect(episodes.map(\.dureeMinutes) == [45, 45, 50])
    }

    @Test func prochainApresLesEpisodesCochesDepuis() {
        let instantane = InstantaneWidgets(series: [
            serie(1, "Reacher", [(2, 6), (2, 7), (2, 8)]),
            serie(2, "Jack Ryan", [(4, 1)]),
        ])
        let prochains = instantane.prochains(vus: [1: [NumeroEpisode(saison: 2, episode: 6)], 2: [NumeroEpisode(saison: 4, episode: 1)]])
        #expect(prochains.map(\.serie.nom) == ["Reacher"])
        #expect(prochains.first?.episode.numeroEpisode == NumeroEpisode(saison: 2, episode: 7))
    }

    @Test func ordreSoireePuisRecents() {
        let instantane = InstantaneWidgets(series: [
            serie(1, "Reacher", [(2, 6)]),
            serie(2, "Jack Ryan", [(4, 1)]),
            serie(3, "The Night Agent", [(2, 1)]),
        ])
        let recents: [Int: Date] = [1: Date(timeIntervalSince1970: 100), 3: Date(timeIntervalSince1970: 500)]
        #expect(instantane.prochains(vus: [:], derniersVisionnages: recents).map(\.serie.id) == [3, 1, 2])
        #expect(instantane.prochains(vus: [:], derniersVisionnages: recents, soiree: [2]).map(\.serie.id) == [2, 3, 1])
    }

    @Test func allerRetourSurDisque() throws {
        let dossier = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dossier) }
        let instantane = InstantaneWidgets(series: [serie(1, "Reacher", [(2, 6)])], miseAJour: Date(timeIntervalSince1970: 1_789_000_000))
        try instantane.ecrire(dossier: dossier)
        #expect(InstantaneWidgets.lire(dossier: dossier) == instantane)
    }
}

@Suite("Siri : ce soir")
struct PhraseSoireeTests {
    private let reacher = InstantaneWidgets.Serie(id: 108_978, nom: "Reacher", cheminAffiche: nil,
                                                  episodes: [.init(saison: 2, numero: 6, titre: nil, dureeMinutes: 50)])
    private let nightAgent = InstantaneWidgets.Serie(id: 129_552, nom: "The Night Agent", cheminAffiche: nil,
                                                     episodes: [.init(saison: 2, numero: 1, titre: nil, dureeMinutes: 48)])

    private var prochains: [InstantaneWidgets.Prochain] {
        InstantaneWidgets(series: [reacher, nightAgent]).prochains(vus: [:])
    }

    @Test func soireePrevueAvecEpisode() {
        let soiree = [
            PhraseSoiree.Titre(reference: reacher.reference, nom: "Reacher"),
            PhraseSoiree.Titre(reference: ReferenceTitre(type: .film, tmdbID: 324_552), nom: "John Wick : Chapitre 2"),
        ]
        #expect(PhraseSoiree.texte(soiree: soiree, prochains: prochains, aVoir: [])
            == "Ce soir, tu as prévu Reacher, saison 2, épisode 6 et John Wick : Chapitre 2.")
    }

    @Test func soireeDeFilmsSeulement() {
        let soiree = ["Heat", "Ronin", "Collateral"].enumerated().map {
            PhraseSoiree.Titre(reference: ReferenceTitre(type: .film, tmdbID: $0.offset), nom: $0.element)
        }
        #expect(PhraseSoiree.texte(soiree: soiree, prochains: [], aVoir: []) == "Ce soir, tu as prévu Heat, Ronin et Collateral.")
    }

    @Test func sansSoireeLesEpisodesPuisLaListe() {
        #expect(PhraseSoiree.texte(soiree: [], prochains: prochains, aVoir: ["Heat"])
            == "Rien de prévu ce soir. Tu pourrais continuer Reacher : saison 2, épisode 6, ou The Night Agent.")
        #expect(PhraseSoiree.texte(soiree: [], prochains: [], aVoir: ["Heat", "Ronin", "Collateral", "Drive"])
            == "Rien de prévu ce soir. Dans ta liste à voir : Heat, Ronin et Collateral.")
        #expect(PhraseSoiree.texte(soiree: [], prochains: [], aVoir: []).hasPrefix("Rien de prévu ce soir. Ouvre Séance"))
    }
}
