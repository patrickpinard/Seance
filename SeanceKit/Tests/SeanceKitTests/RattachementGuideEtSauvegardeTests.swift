import Foundation
import Testing
@testable import SeanceKit

/// Recherche TMDB simulée : répond à partir d'une table et compte les appels.
actor RechercheSimulee: RechercheTMDB {
    var films: [String: [[String: Any]]] = [:]
    var series: [String: [[String: Any]]] = [:]
    var enEchec: Set<String> = []
    private(set) var appels: [String] = []

    init(films: [String: [[String: Any]]] = [:], series: [String: [[String: Any]]] = [:], enEchec: Set<String> = []) {
        self.films = films
        self.series = series
        self.enEchec = enEchec
    }

    func rechercherFilms(_ texte: String, page: Int) async throws -> PageTMDB<FilmResume> {
        appels.append("film:\(texte)")
        if enEchec.contains(texte) { throw URLError(.timedOut) }
        return pageDe(films[texte] ?? [], FilmResume.self)
    }

    func rechercherSeries(_ texte: String, page: Int) async throws -> PageTMDB<SerieResume> {
        appels.append("serie:\(texte)")
        return pageDe(series[texte] ?? [], SerieResume.self)
    }

    private func pageDe<T>(_ resultats: [[String: Any]], _ type: T.Type) -> PageTMDB<T> {
        Construire.decoder(PageTMDB<T>.self, ["page": 1, "results": resultats, "total_pages": 1, "total_results": resultats.count])
    }

    static func film(_ id: Int, _ titre: String, _ original: String, _ date: String) -> [String: Any] {
        ["id": id, "title": titre, "original_title": original, "original_language": "en", "overview": "", "genre_ids": [28],
         "vote_average": 7.0, "vote_count": 100, "popularity": 10.0, "release_date": date]
    }

    static func serie(_ id: Int, _ nom: String, _ original: String, _ date: String) -> [String: Any] {
        ["id": id, "name": nom, "original_name": original, "original_language": "en", "overview": "", "genre_ids": [80],
         "origin_country": ["US"], "vote_average": 7.0, "vote_count": 100, "popularity": 10.0, "first_air_date": date]
    }
}

@Suite("Rattachement du guide TV")
struct RattachementGuideTests {
    private func programme(_ titre: String, _ categorie: String, annee: Int?, debut: String = "2026-09-17 21:10") -> ProgrammeTV {
        var p = ProgrammeTV(chaine: "M6.fr", debut: Date.suisse(debut), fin: Date.suisse(debut).addingTimeInterval(6000), titre: titre)
        p.categories = [categorie]
        p.annee = annee
        return p
    }

    @Test func unTitreCherchéUneSeuleFois() async throws {
        let recherche = RechercheSimulee(
            films: ["La chute de Londres": [RechercheSimulee.film(267_860, "La Chute de Londres", "London Has Fallen", "2016-03-02")]],
            series: ["New York Unité Spéciale": [RechercheSimulee.serie(2734, "New York, unité spéciale", "Law & Order: Special Victims Unit", "1999-09-20")]]
        )
        let guide = RattachementGuide(recherche: recherche)
        let resultats = try await guide.rattacher([
            programme("La chute de Londres", "Film", annee: 2016),
            programme("La chute de Londres", "Film", annee: 2016, debut: "2026-09-19 14:00"),
            programme("New York Unité Spéciale", "Série", annee: 2019),
            programme("Que le meilleur gagne !", "Film", annee: nil),
            programme("Ça commence aujourd'hui", "Magazine", annee: 2026),
        ])

        #expect(resultats.map { $0.candidat?.tmdbID } == [267_860, 267_860, 2734, nil, nil])
        #expect(await recherche.appels == ["film:La chute de Londres", "serie:New York Unité Spéciale"])
    }

    @Test func uneRechercheEnEchecNeBloquePasLesAutres() async throws {
        let recherche = RechercheSimulee(
            films: ["Taken 2": [RechercheSimulee.film(82675, "Taken 2", "Taken 2", "2012-10-03")]],
            enEchec: ["Heat"]
        )
        let guide = RattachementGuide(recherche: recherche)
        let resultats = try await guide.rattacher([programme("Heat", "Film", annee: 1995), programme("Taken 2", "Film", annee: 2012)])

        #expect(resultats.map { $0.candidat?.tmdbID } == [nil, 82675])
        #expect(await guide.recherchesEnEchec == 1)
    }
}

@Suite("Sauvegarde")
struct SauvegardeTests {
    private let heat = ReferenceTitre(type: .film, tmdbID: 949)
    private let reacher = ReferenceTitre(type: .serie, tmdbID: 108_978)
    private let date = Date.suisse("2026-09-16 21:00")

    private func suivi(_ reference: ReferenceTitre, statut: String) -> Sauvegarde.Suivi {
        Sauvegarde.Suivi(reference: reference, statut: statut, note: nil, exclusionLangue: false, ajouteLe: date,
                         titre: "", cheminAffiche: nil, acteursPrincipaux: [], genres: [])
    }

    @Test func allerRetourJSON() throws {
        var sauvegarde = Sauvegarde(creeeLe: date)
        sauvegarde.suivis = [suivi(heat, statut: "termine")]
        sauvegarde.visionnages = [Sauvegarde.Visionnage(reference: reacher, episode: NumeroEpisode(saison: 1, episode: 3), dureeMinutes: 48, note: 8, vuLe: date)]
        var criteres = CriteresDecouverte()
        criteres.acteurs = [6384]
        sauvegarde.filtres = [Sauvegarde.Filtre(nom: "Keanu", type: .film, criteres: criteres, alerteActive: true)]

        let donnees = try sauvegarde.encoder()
        #expect(String(data: donnees, encoding: .utf8)?.contains("\"creeeLe\" : \"2026-09-16T19:00:00Z\"") == true)
        #expect(try Sauvegarde.decoder(donnees) == sauvegarde)
        #expect(Sauvegarde.nomFichier(pour: date) == "Séance 2026-09-16.json")
    }

    @Test func versionFutureRefusee() throws {
        var sauvegarde = Sauvegarde(creeeLe: date)
        sauvegarde.version = 99
        #expect(throws: Sauvegarde.Erreur.versionInconnue(99)) {
            try Sauvegarde.decoder(try sauvegarde.encoder())
        }
    }

    @Test func importSansDoublonNiEcrasement() {
        var existante = Sauvegarde(creeeLe: date)
        existante.suivis = [suivi(heat, statut: "termine")]
        existante.visionnages = [Sauvegarde.Visionnage(reference: heat, episode: nil, dureeMinutes: 170, note: nil, vuLe: date)]
        existante.listes = [Sauvegarde.Liste(nom: "Soirées Statham", creeeLe: date, titres: [heat])]

        var importee = Sauvegarde(creeeLe: date)
        importee.suivis = [suivi(heat, statut: "aVoir"), suivi(reacher, statut: "enCours")]
        importee.visionnages = [
            Sauvegarde.Visionnage(reference: heat, episode: nil, dureeMinutes: 170, note: nil, vuLe: date.addingTimeInterval(20)),
            Sauvegarde.Visionnage(reference: reacher, episode: NumeroEpisode(saison: 1, episode: 1), dureeMinutes: 50, note: nil, vuLe: date),
        ]
        importee.listes = [
            Sauvegarde.Liste(nom: "Soirées Statham", creeeLe: date, titres: [heat, reacher]),
            Sauvegarde.Liste(nom: "Classiques 90s", creeeLe: date, titres: [heat]),
        ]

        let plan = PlanImport(importee: importee, existante: existante)
        // Heat existe déjà : l'état local l'emporte.
        #expect(plan.suivis.map(\.reference) == [reacher])
        // Même film à 20 secondes d'écart : même minute, doublon.
        #expect(plan.visionnages.map(\.reference) == [reacher])
        #expect(plan.titresAjoutesAuxListes == ["Soirées Statham": [reacher]])
        #expect(plan.listes.map(\.nom) == ["Classiques 90s"])
        #expect(PlanImport(importee: existante, existante: existante).estVide)
    }
}
