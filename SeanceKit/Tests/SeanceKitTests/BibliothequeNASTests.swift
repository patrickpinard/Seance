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

    /// 8.10 : sans dossier déclaré, tout le partage est lu — les films d'un Mac sont souvent à la racine.
    @Test func sansDossierToutLePartageEstLu() async throws {
        #expect(ReglagesNAS(hote: "172.22.22.229", partage: "Films", dossiers: [], utilisateur: "patrick").estComplet)
        let racine = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: racine) }
        try FileManager.default.createDirectory(at: racine.appending(path: "Séries/Reacher"), withIntermediateDirectories: true)
        try Data().write(to: racine.appending(path: "Mile.22.2018.mkv"))
        try Data().write(to: racine.appending(path: "Séries/Reacher/Reacher.S04E07.mkv"))
        let chemins = try await ExplorateurLocal(racine: racine).listerVideos(dossiers: []).map(\.chemin).sorted()
        // La fin du chemin seulement : dans le dossier temporaire, /var et /private/var décalent le début.
        #expect(chemins.count == 2)
        #expect(chemins[0].hasSuffix("Mile.22.2018.mkv") && chemins[1].hasSuffix("Séries/Reacher/Reacher.S04E07.mkv"))
    }

    @Test func indexSansDoublonAvecLaCopieLaPlusLourde() {
        let index = IndexNAS.construire(fichiers)
        #expect(index.doublons == 1)
        // Le fichier gardé et celui écarté sont nommés, pour que Patrick puisse faire le ménage.
        #expect(index.copiesEnDouble == [DoublonNAS(
            gardee: FichierDistant(chemin: "Séries/Reacher/Saison 04/Reacher.S04E07.mkv", taille: 900_000_000),
            ecartees: [FichierDistant(chemin: "Séries/Reacher/Saison 04/Reacher.S04E07.mp4", taille: 700_000_000)]
        )])
        #expect(index.entrees.count == 7)
        let s04e07 = index.entrees.first { $0.analyse.episode == NumeroEpisode(saison: 4, episode: 7) }
        #expect(s04e07?.fichier.chemin.hasSuffix(".mkv") == true)
        #expect(index.entrees.first { $0.fichier.chemin.hasPrefix("NEW/") }?.dossier == "NEW")
        #expect(index.entrees.first { $0.analyse.titre == "L Homme Qui Rétrécit" }?.analyse.annee == 2025)
        #expect(index.entrees.filter { $0.analyse.type == .serie }.map(\.analyse.titre).sorted() == ["Black Bird", "Reacher", "Reacher"])
    }

    /// 8.11 (audit de sécurité) : une autre app reçoit le compte, jamais le mot de passe.
    @Test func lAppExterneNeRecoitPasLeMotDePasse() throws {
        let adresse = try #require(ReglagesNAS().urlPourAppExterne(chemin: "Films/Bang.2025.mkv"))
        #expect(adresse.user() == "admin")
        #expect(adresse.password() == nil)
        #expect(adresse.absoluteString == "smb://admin@192.168.1.220/Films/Films/Bang.2025.mkv")
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
        for doublon in index.copiesEnDouble {
            print("  en double : garde \(doublon.gardee.chemin), écarte \(doublon.ecartees.map(\.chemin).joined(separator: ", "))")
        }
        for r in reconnus where r.titre?.cheminAffiche == nil {
            print("  sans affiche : \(r.entree.fichier.chemin) → \(r.titre?.reference.tmdbID ?? 0) « \(r.titre?.titre ?? "") »")
        }
        // Détail des séries : une ligne par dossier, avec le type lu et le titre TMDB retenu.
        var parDossier: [String: (type: TypeTitre, episodes: Int, titre: String?, affiche: String?)] = [:]
        for r in resultats where r.entree.dossier.precomposedStringWithCanonicalMapping == "Séries" {
            let composants = r.entree.fichier.chemin.split(separator: "/")
            let dossier = composants.count > 1 ? String(composants[1]) : r.entree.fichier.chemin
            var ligne = parDossier[dossier] ?? (r.entree.analyse.type, 0, r.titre?.titre, r.titre?.cheminAffiche)
            ligne.episodes += 1
            parDossier[dossier] = ligne
        }
        for (dossier, ligne) in parDossier.sorted(by: { $0.key < $1.key }) {
            print("  série \(dossier) : type \(ligne.type), \(ligne.episodes) fichiers, TMDB « \(ligne.titre ?? "—") », affiche \(ligne.affiche ?? "—")")
        }
        #expect(Double(reconnus.count) / Double(max(1, resultats.count)) > 0.7)
    }
}

@Suite("Lecture depuis le NAS")
struct LecteurVideoTests {
    @Test func infuseOuvreLeTitreDeSaBibliotheque() {
        let gourou = ReferenceTitre(type: .film, tmdbID: 1_259_983)
        let reacher = ReferenceTitre(type: .serie, tmdbID: 108_978)
        #expect(LecteurVideo.infuse.lienBibliotheque(gourou, episode: nil)?.absoluteString == "infuse://movie/1259983?play")
        #expect(LecteurVideo.infuse.lienBibliotheque(reacher, episode: NumeroEpisode(saison: 2, episode: 6))?.absoluteString
            == "infuse://series/108978-2-6?play")
        // Sans numéro d'épisode, rien à lancer ; VLC passe par l'adresse SMB.
        #expect(LecteurVideo.infuse.lienBibliotheque(reacher, episode: nil) == nil)
        #expect(LecteurVideo.vlc.lienBibliotheque(gourou, episode: nil) == nil)
    }

    @Test func lienInfuseEtVLCAvecIdentifiantsEncodes() throws {
        let reglages = ReglagesNAS()
        let video = try #require(reglages.url(chemin: "Séries/Reacher/Saison 01/Reacher.S01E03.mkv", motDePasse: "p@ss:w/rd"))
        let infuse = try #require(LecteurVideo.infuse.lien(pour: video))
        #expect(infuse.scheme == "infuse")
        #expect(infuse.host == "x-callback-url")

        // L'app de lecture décode une fois et retrouve l'adresse SMB exacte, mot de passe compris.
        let valeur = try #require(URLComponents(url: infuse, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "url" }?.value)
        let relue = try #require(URL(string: valeur))
        #expect(relue == video)
        #expect(relue.password(percentEncoded: false) == "p@ss:w/rd")
        #expect(relue.path(percentEncoded: false) == "/Films/Séries/Reacher/Saison 01/Reacher.S01E03.mkv")

        #expect(LecteurVideo.vlc.lien(pour: video)?.absoluteString.hasPrefix("vlc-x-callback://x-callback-url/stream?url=smb%3A%2F%2Fadmin%3A") == true)
    }
}

/// Ce que Séance garde d'un fichier du NAS en plus du magasin (6.4) : quand il est arrivé, et les genres du titre.
@Suite("Détails du NAS")
struct DetailsNASTests {
    @Test("La date d'ajout d'une œuvre est celle de son fichier le plus récent")
    func ajoutLePlusRecent() {
        let vieux = Date(timeIntervalSince1970: 1_700_000_000)
        let recent = Date(timeIntervalSince1970: 1_750_000_000)
        let details = DetailsNAS(ajouts: ["Séries/Reacher/S01E01.mkv": vieux, "Séries/Reacher/S01E02.mkv": recent])
        #expect(details.ajout(["Séries/Reacher/S01E01.mkv", "Séries/Reacher/S01E02.mkv"]) == recent)
        #expect(details.ajout(["Films/Inconnu.mkv"]) == nil)
    }

    @Test("Les détails se relisent tels qu'ils ont été écrits")
    func allerRetour() throws {
        let quand = Date(timeIntervalSince1970: 1_750_000_000)
        let avant = DetailsNAS(ajouts: ["Films/Heat.mkv": quand], genres: [949: [28, 80, 18]])
        let apres = try #require(DetailsNAS.decoder(try avant.encoder()))
        #expect(apres.genres[949] == [28, 80, 18])
        #expect(apres.ajouts["Films/Heat.mkv"] == quand)
    }
}
