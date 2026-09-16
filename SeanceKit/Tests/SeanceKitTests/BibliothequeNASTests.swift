import Foundation
import Testing
@testable import SeanceKit

@Suite("Bibliothèque du NAS")
struct BibliothequeNASTests {
    /// Noms relevés sur le NAS de Patrick le 16 septembre 2026.
    private let fichiers = [
        FichierDistant(chemin: "Films/Mile.22.2018.avi", taille: 1_400_000_000),
        FichierDistant(chemin: "Films/L.Homme.Qui.Rétrécit.2025.mkv", taille: 2_100_000_000),
        FichierDistant(chemin: "NEW/11.septembre.2017.mkv", taille: 1_800_000_000),
        FichierDistant(chemin: "Séries/Reacher/Saison 04/Reacher.S04E07.mp4", taille: 700_000_000),
        FichierDistant(chemin: "Séries/Reacher/Saison 04/Reacher.S04E07.mkv", taille: 900_000_000),
        FichierDistant(chemin: "Séries/Reacher/Saison 04/Reacher.S04E06.mkv", taille: 880_000_000),
        FichierDistant(chemin: "Séries/Black Bird/Saison 01/Black.Bird.S01E01.mkv", taille: 600_000_000),
        FichierDistant(chemin: "Films/RenommerMedias.log.mkv", taille: 0),
    ]

    @Test func indexSansDoublonAvecLaCopieLaPlusLourde() {
        let index = IndexNAS.construire(fichiers)
        #expect(index.doublons == 1)
        #expect(index.entrees.count == 7)
        let s04e07 = index.entrees.first { $0.analyse.episode == NumeroEpisode(saison: 4, episode: 7) }
        #expect(s04e07?.fichier.chemin.hasSuffix(".mkv") == true)
        #expect(index.entrees.first { $0.fichier.chemin.hasPrefix("NEW/") }?.dossier == "NEW")
        #expect(index.entrees.first { $0.analyse.titre == "L Homme Qui Rétrécit" }?.analyse.annee == 2025)
        #expect(index.entrees.filter { $0.analyse.type == .serie }.map(\.analyse.titre).sorted() == ["Black Bird", "Reacher", "Reacher"])
    }

    @Test func urlSMBAvecEtSansIdentifiants() throws {
        let reglages = ReglagesNAS()
        let sans = try #require(reglages.url(chemin: "Films/L.Homme.Qui.Rétrécit.2025.mkv"))
        #expect(sans.absoluteString == "smb://192.168.1.220/Films/Films/L.Homme.Qui.R%C3%A9tr%C3%A9cit.2025.mkv")
        let avec = try #require(reglages.url(chemin: "Séries/Black Bird/Saison 01/Black.Bird.S01E01.mkv", motDePasse: "p@ss:word"))
        #expect(avec.user() == "admin")
        #expect(avec.password(percentEncoded: false) == "p@ss:word")
        #expect(avec.path() == "/Films/S%C3%A9ries/Black%20Bird/Saison%2001/Black.Bird.S01E01.mkv")
    }

    @Test func rattachementFilmsEtSeries() async throws {
        let recherche = RechercheSimulee(
            films: [
                "Mile 22": [RechercheSimulee.film(347_375, "Mile 22", "Mile 22", "2018-08-10")],
                "L Homme Qui Rétrécit": [RechercheSimulee.film(1_087_192, "L'Homme qui rétrécit", "L'Homme qui rétrécit", "2025-10-22")],
            ],
            series: [
                "Reacher": [RechercheSimulee.serie(108_978, "Reacher", "Reacher", "2022-02-03")],
                "Black Bird": [
                    RechercheSimulee.serie(155_537, "Black Bird", "Black Bird", "2022-07-08"),
                    RechercheSimulee.serie(999, "Black Bird", "Black Bird", "2001-01-01"),
                ],
            ]
        )
        let index = IndexNAS.construire(fichiers)
        let resultats = try await RattachementNAS(recherche: recherche).rattacher(index.entrees)
        let parTitre = Dictionary(resultats.map { ($0.entree.fichier.chemin, $0.titre?.reference.tmdbID) }, uniquingKeysWith: { a, _ in a })

        #expect(parTitre["Films/Mile.22.2018.avi"] == 347_375)
        #expect(parTitre["Films/L.Homme.Qui.Rétrécit.2025.mkv"] == 1_087_192)
        #expect(parTitre["Séries/Reacher/Saison 04/Reacher.S04E06.mkv"] == 108_978)
        // Deux homonymes aussi connues l'une que l'autre : non reconnu (EF-79).
        #expect(parTitre["Séries/Black Bird/Saison 01/Black.Bird.S01E01.mkv"] == .some(nil))
        // Reacher n'est cherché qu'une fois pour ses deux épisodes.
        #expect(await recherche.appels.filter { $0 == "serie:Reacher" }.count == 1)
    }
}

/// Analyse réelle du NAS monté sur le Mac, rattachée à TMDB. Ne tourne que si le partage est monté
/// et la clé fournie : `SEANCE_CLE_TMDB=… outils/tester.sh --filter NASReel`.
@Suite("NAS réel", .enabled(if: ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] != nil
    && FileManager.default.fileExists(atPath: "/Volumes/Films/Films")))
struct NASReelTests {
    @Test func analyseEtRattachementDuPartageFilms() async throws {
        let fichiers = try await ExplorateurLocal(racine: URL(filePath: "/Volumes/Films")).listerVideos(dossiers: ["Films", "NEW", "Séries"])
        let index = IndexNAS.construire(fichiers)
        let client = TMDBClient(identifiants: .depuis(ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] ?? ""))
        let rattachement = RattachementNAS(recherche: client)
        let resultats = try await rattachement.rattacher(index.entrees)

        let reconnus = resultats.filter { $0.titre != nil }
        print("NAS : \(fichiers.count) vidéos, \(index.entrees.count) retenues, \(index.doublons) doublons, \(index.illisibles.count) illisibles")
        print("NAS : \(reconnus.count) rattachées à TMDB, \(resultats.count - reconnus.count) non reconnues")
        for r in resultats where r.titre == nil {
            print("  non reconnu : \(r.entree.fichier.chemin) → « \(r.entree.analyse.titre) » \(r.entree.analyse.annee.map(String.init) ?? "")")
        }
        #expect(Double(reconnus.count) / Double(max(1, resultats.count)) > 0.7)
    }
}
