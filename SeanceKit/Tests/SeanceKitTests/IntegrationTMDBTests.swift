import Foundation
import Testing
@testable import SeanceKit

/// Vérifie le décodage contre l'API réelle. Ne tourne que si la clé est fournie dans
/// l'environnement : `SEANCE_CLE_TMDB=… outils/tester.sh`. La clé n'est jamais écrite dans le dépôt.
@Suite("TMDB réel", .enabled(if: ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] != nil))
struct IntegrationTMDBTests {
    private let client = TMDBClient(identifiants: .depuis(ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] ?? ""))

    @Test func tendancesEtRecherche() async throws {
        #expect(try await client.tendances(.jour).count >= 10)
        let resultats = try await client.rechercherTout("Keanu Reeves")
        #expect(resultats.contains { $0.personne?.id == 6384 })
    }

    @Test func ficheFilmComplete() async throws {
        let film = try await client.film(603_692)
        #expect(film.titre.contains("John Wick"))
        #expect((film.dureeMinutes ?? 0) > 150)
        #expect(film.casting?.acteurs.first?.nom == "Keanu Reeves")
        #expect(film.datesDeSortie?.sorties(region: "CH").isEmpty == false)
        #expect(film.fournisseurs != nil)
    }

    @Test func ficheSerieEtSaison() async throws {
        let serie = try await client.serie(108_978, complements: [.casting, .fournisseurs, .videos])
        #expect(serie.nom == "Reacher")
        #expect(serie.casting?.acteurs.isEmpty == false)
        let saison = try await client.saison(1, serie: 108_978)
        #expect(saison.episodes.count == 8)
    }

    @Test func plateformesSuissesEtDecouverte() async throws {
        let catalogue = try await client.catalogueFournisseurs(.film)
        #expect(catalogue.contains { $0.id == 691 && $0.nom == "Play Suisse" })
        var criteres = CriteresDecouverte()
        criteres.genresInclus = [28]
        criteres.acteurs = [6384]
        criteres.fournisseurs = [8, 119, 337, 350, 150, 691]
        criteres.monetisations = [.abonnement]
        let page = try await client.decouvrirFilms(criteres)
        #expect(page.nombreResultats >= 0)
    }

    @Test func filmographieEtDatesDeSortie() async throws {
        let filmographie = try await client.filmographie(personne: 6384)
        #expect(filmographie.roles.contains { $0.tmdbID == 603 && $0.type == .film })
        let dates = try await client.datesDeSortie(film: 603_692)
        #expect(!dates.pays.isEmpty)
    }
}

/// Lit le vrai guide (fichier complet, 18 Mo) et affiche ce qui passe ce soir sur les chaînes par défaut.
/// `SEANCE_GUIDE_REEL=1 SEANCE_CLE_TMDB=… outils/tester.sh --filter GuideReel`
@Suite("Guide TV réel", .enabled(if: ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] != nil
    && ProcessInfo.processInfo.environment["SEANCE_GUIDE_REEL"] != nil))
struct GuideReelTests {
    @Test func programmesRTSEtFrancaisRattaches() async throws {
        let chaines = Set(ChaineGuide.parDefaut.map(\.id))
        let debut = Date.now
        let guide = try await GuideTVClient().programmes(chaines: chaines)
        let lecture = Date.now.timeIntervalSince(debut)
        let aVenir = guide.programmes.filter { $0.fin > .now }
        #expect(aVenir.contains { $0.chaine == "RTSUn.ch" })

        let client = TMDBClient(identifiants: .depuis(ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] ?? ""))
        let rattachement = RattachementGuide(recherche: client)
        let debutRattachement = Date.now
        let resultats = try await rattachement.rattacher(aVenir)
        let duree = Date.now.timeIntervalSince(debutRattachement)

        let films = resultats.filter { $0.programme.nature == .film }
        let filmsRattaches = films.filter { $0.candidat != nil }
        print("Lecture \(Int(lecture)) s, rattachement \(Int(duree)) s, échecs \(await rattachement.recherchesEnEchec)")
        print("Films : \(filmsRattaches.count)/\(films.count) ; séries : \(resultats.filter { $0.programme.nature == .serie && $0.candidat != nil }.count)/\(resultats.filter { $0.programme.nature == .serie }.count)")
        let format = Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "fr_CH"))
        for r in films.sorted(by: { $0.programme.debut < $1.programme.debut }) {
            let etat = r.candidat.map { "→ TMDB \($0.tmdbID) « \($0.titre) » (\($0.annee.map(String.init) ?? "?"))" } ?? "✗ non rattaché"
            print("\(r.programme.chaine) \(r.programme.debut.formatted(format)) \(r.programme.titre) [\(r.programme.annee.map(String.init) ?? "sans année")] \(etat)")
        }
        #expect(filmsRattaches.count * 2 >= films.count)
    }
}

/// Chaque critère d'Explorer doit réduire le nombre de résultats annoncé par TMDB.
/// `SEANCE_CLE_TMDB=… outils/tester.sh --filter FiltresReels`
@Suite("Filtres réels", .enabled(if: ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] != nil))
struct FiltresReelsTests {
    private let client = TMDBClient(identifiants: .depuis(ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"] ?? ""))

    private func total(_ filtres: FiltresExplorer) async throws -> Int {
        let criteres = filtres.criteres(abonnements: [8, 119, 337])
        switch filtres.type {
        case .film: return try await client.decouvrirFilms(criteres).nombreResultats
        case .serie: return try await client.decouvrirSeries(criteres).nombreResultats
        }
    }

    @Test(arguments: [TypeTitre.film, .serie])
    func chaqueCritereReduitLeNombre(type: TypeTitre) async throws {
        // TMDB plafonne le nombre annoncé à 20 001 : la base reste en dessous pour que chaque critère se voie.
        var base = FiltresExplorer(type: type)
        base.votesMin = 300
        let reference = try await total(base)
        #expect(reference < 20_000)
        var cas: [(String, FiltresExplorer)] = []
        func ajouter(_ nom: String, _ modifier: (inout FiltresExplorer) -> Void) {
            var f = base
            modifier(&f)
            cas.append((nom, f))
        }
        ajouter("genre") { $0.genresInclus = [type == .film ? 28 : 10759] }
        ajouter("genre exclu") { $0.genresExclus = [type == .film ? 18 : 18] }
        ajouter("sous-genre") { $0.sousGenres = ["artsMartiaux"] }
        if type == .film { ajouter("personne") { $0.personnes = [PersonneFiltre(id: 6384, nom: "Keanu", cheminPortrait: nil)] } }
        ajouter("période") { $0.anneeDebut = 1990; $0.anneeFin = 1999 }
        if type == .film { ajouter("type de sortie") { $0.typesSortie = [.salles] } }
        ajouter("note") { $0.noteMin = 7 }
        ajouter("votes") { $0.votesMin = 2000 }
        ajouter("durée") { $0.dureeMax = type == .film ? 90 : 30 }
        ajouter("langue") { $0.langue = "fr" }
        ajouter("plateformes") { $0.mesPlateformes = true }
        ajouter("monétisation") { $0.monetisations = [.location] }
        ajouter("tri par note (même nombre)") { $0.tri = .note }

        print("\(type) — sans filtre : \(reference)")
        for (nom, filtres) in cas {
            let n = try await total(filtres)
            print("\(type) — \(nom) : \(n)")
            if nom.hasPrefix("tri") {
                #expect(n == reference)
            } else {
                #expect(n < reference, "\(nom) ne réduit pas les résultats (\(n) sur \(reference))")
            }
        }
    }
}
