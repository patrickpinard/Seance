import Foundation
import SeanceKit
import SwiftData
import Testing
@testable import SeanceDonnees

private struct NASSimule: ExplorateurFichiers {
    var fichiers: [FichierDistant]
    var echec: (any Error)?

    func listerVideos(dossiers: [String]) async throws -> [FichierDistant] {
        if let echec { throw echec }
        return fichiers.filter { fichier in dossiers.contains { fichier.chemin.hasPrefix($0 + "/") } }
    }
}

private actor RechercheNAS: RechercheTMDB {
    func rechercherFilms(_ texte: String, page: Int) async throws -> PageTMDB<FilmResume> {
        let json = texte == "Heat"
            ? #"[{"id": 949, "title": "Heat", "original_title": "Heat", "original_language": "en", "overview": "", "genre_ids": [28], "poster_path": "/heat.jpg", "vote_average": 7.9, "vote_count": 7000, "popularity": 30, "release_date": "1995-12-15"}]"#
            : "[]"
        return try JSONDecoder().decode(PageTMDB<FilmResume>.self, from: Data(#"{"page": 1, "results": \#(json), "total_pages": 1, "total_results": 1}"#.utf8))
    }

    func rechercherSeries(_ texte: String, page: Int) async throws -> PageTMDB<SerieResume> {
        let json = texte == "Reacher"
            ? #"[{"id": 108978, "name": "Reacher", "original_name": "Reacher", "original_language": "en", "overview": "", "genre_ids": [10759], "origin_country": ["US"], "poster_path": "/reacher.jpg", "vote_average": 8.0, "vote_count": 3000, "popularity": 50, "first_air_date": "2022-02-03"}]"#
            : "[]"
        return try JSONDecoder().decode(PageTMDB<SerieResume>.self, from: Data(#"{"page": 1, "results": \#(json), "total_pages": 1, "total_results": 1}"#.utf8))
    }
}

@Suite("Bibliothèque du NAS en magasin")
@MainActor
struct ServiceBibliothequeTests {
    private let fichiers = [
        FichierDistant(chemin: "Films/Heat.1995.1080p.mkv", taille: 8_000),
        FichierDistant(chemin: "Films/Heat.1995.2160p.mkv", taille: 20_000),
        FichierDistant(chemin: "NEW/Film.Inconnu.2025.mkv", taille: 3_000),
        // Écrit depuis un Mac : « e » + accent combinant.
        FichierDistant(chemin: "Se\u{0301}ries/Reacher/Saison 01/Reacher.S01E01.mkv", taille: 2_000),
        FichierDistant(chemin: "Se\u{0301}ries/Reacher/Saison 01/Reacher.S01E02.mkv", taille: 2_000),
        FichierDistant(chemin: "Privé/Vacances.2024.mkv", taille: 1_000),
    ]

    @Test func analyseRemplaceLaBibliothequeEtRecopieTMDB() async throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let contexte = conteneur.mainContext
        contexte.insert(FichierNAS(chemin: "Films/Ancien.2000.mkv", type: .film))
        try contexte.save()

        let service = ServiceBibliotheque(contexte: contexte)
        let rapport = try await service.actualiser(
            explorateur: NASSimule(fichiers: fichiers), recherche: RechercheNAS(), dossiers: ["Films", "NEW", "Séries"]
        )

        #expect(rapport.videosLues == 5)
        #expect(rapport.doublons == 1)
        #expect(rapport.copiesEnDouble.count == 1 && rapport.copiesEnDouble.first?.ecartees.count == 1)
        #expect(rapport.reconnues == 3)
        #expect(rapport.nonReconnues == ["NEW/Film.Inconnu.2025.mkv"])
        #expect(rapport.videosParDossier == ["Films": 2, "NEW": 1, "Séries": 2])
        #expect(rapport.filmsReconnus == 1 && rapport.seriesReconnues == 1)

        let enMagasin = try contexte.fetch(FetchDescriptor<FichierNAS>(sortBy: [SortDescriptor(\.chemin)]))
        #expect(enMagasin.map(\.chemin) == [
            "Films/Heat.1995.2160p.mkv", "NEW/Film.Inconnu.2025.mkv",
            "Séries/Reacher/Saison 01/Reacher.S01E01.mkv", "Séries/Reacher/Saison 01/Reacher.S01E02.mkv",
        ])
        let heat = try #require(enMagasin.first)
        #expect(heat.titre == "Heat" && heat.cheminAffiche == "/heat.jpg" && heat.qualite == "4K" && heat.dossier == "Films")
        #expect(enMagasin[3].reference == ReferenceTitre(type: .serie, tmdbID: 108_978) && enMagasin[3].episode == 2)
        #expect(enMagasin[3].dossier.unicodeScalars.count == "Séries".unicodeScalars.count)
        // Le chemin garde l'écriture du NAS, indispensable pour relire le fichier.
        #expect(enMagasin[3].chemin.unicodeScalars.count > "Séries/Reacher/Saison 01/Reacher.S01E02.mkv".unicodeScalars.count)
        #expect(enMagasin[1].titre == "Film Inconnu" && enMagasin[1].tmdbID == nil)
    }

    @Test func unNASInjoignableNeVidePasLaBibliotheque() async throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let contexte = conteneur.mainContext
        contexte.insert(FichierNAS(chemin: "Films/Heat.1995.mkv", type: .film, tmdbID: 949))
        try contexte.save()

        await #expect(throws: URLError.self) {
            try await ServiceBibliotheque(contexte: contexte).actualiser(
                explorateur: NASSimule(fichiers: [], echec: URLError(.timedOut)), recherche: RechercheNAS(), dossiers: ["Films"]
            )
        }
        #expect(try contexte.fetchCount(FetchDescriptor<FichierNAS>()) == 1)
    }
}
