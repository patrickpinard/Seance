import Foundation
import Testing
@testable import SeanceKit

@Suite("Rattachement à TMDB")
struct RattachementTests {
    private let chuteDeLondres = CandidatRattachement(
        tmdbID: 267_860, type: .film, titre: "La Chute de Londres", titreOriginal: "London Has Fallen", annee: 2016)
    private let newYorkUniteSpeciale = CandidatRattachement(
        tmdbID: 2734, type: .serie, titre: "New York, unité spéciale", titreOriginal: "Law & Order: Special Victims Unit", annee: 1999)

    @Test(arguments: [
        ("Mission : Impossible - Fallout", "mission impossible fallout"),
        ("Mission: Impossible – Fallout", "mission impossible fallout"),
        ("L'Œuvre de Dieu, la part du Diable", "oeuvre de dieu la part du diable"),
        ("Fast & Furious", "fast et furious"),
        ("Les Visiteurs", "visiteurs"),
        ("Taken 2", "taken 2"),
        ("The", "the"),
    ])
    func normalisation(titre: String, attendu: String) {
        #expect(NormalisationTitre.normaliser(titre) == attendu)
    }

    @Test func filmParTitreFrancaisOuOriginal() {
        #expect(Rattacheur.correspond(titre: "La chute de Londres", annee: 2016, candidat: chuteDeLondres))
        #expect(Rattacheur.correspond(titre: "London Has Fallen", annee: 2015, candidat: chuteDeLondres))
    }

    @Test func filmRefuseSiLAnneeEcarteOuManque() {
        #expect(!Rattacheur.correspond(titre: "La chute de Londres", annee: 2018, candidat: chuteDeLondres))
        #expect(!Rattacheur.correspond(titre: "La chute de Londres", annee: nil, candidat: chuteDeLondres))
        #expect(!Rattacheur.correspond(titre: "La chute de la Maison-Blanche", annee: 2013, candidat: chuteDeLondres))
    }

    @Test func serieAvecAnneeDEpisode() {
        // Le guide donne 2019, année de l'épisode ; la série a commencé en 1999.
        #expect(Rattacheur.correspond(titre: "New York Unité Spéciale", annee: 2019, candidat: newYorkUniteSpeciale))
        #expect(!Rattacheur.correspond(titre: "New York Unité Spéciale", annee: 1990, candidat: newYorkUniteSpeciale))
    }

    @Test func homonymesDepartagesParLAnneeExacte() {
        let premier = CandidatRattachement(tmdbID: 1, type: .film, titre: "Taken", titreOriginal: "Taken", annee: 2008)
        let second = CandidatRattachement(tmdbID: 2, type: .film, titre: "Taken", titreOriginal: "Taken", annee: 2009)
        let jumeau = CandidatRattachement(tmdbID: 3, type: .film, titre: "Taken", titreOriginal: "Taken", annee: 2008)
        // 2008 et 2009 sont dans la tolérance : l'année exacte l'emporte.
        #expect(Rattacheur.rattacher(titre: "Taken", annee: 2008, parmi: [premier, second]) == premier)
        #expect(Rattacheur.rattacher(titre: "Taken", annee: 2007, parmi: [premier, second]) == premier)
        // Deux films différents de la même année : ambigu, rien n'est rattaché.
        #expect(Rattacheur.rattacher(titre: "Taken", annee: 2008, parmi: [premier, jumeau]) == nil)
    }

    @Test func titresAvecApostropheSupprimee() {
        #expect(NormalisationTitre.equivalents("Tyler Perrys Duplicity", "Tyler Perry's Duplicity"))
        #expect(NormalisationTitre.equivalents("L Homme Qui Rétrécit", "L'Homme qui rétrécit"))
        #expect(!NormalisationTitre.equivalents("Heat", "Heat 2"))
    }

    @Test func programmeRattacheSelonSaNature() throws {
        let debut = Date.iso("2026-09-17T19:10:00Z")
        var film = ProgrammeTV(chaine: "M6.fr", debut: debut, fin: debut.addingTimeInterval(6300), titre: "La chute de Londres")
        film.annee = 2016
        film.categories = ["Film", "Action"]
        #expect(film.rattacher(parmi: [chuteDeLondres, newYorkUniteSpeciale]) == chuteDeLondres)

        film.categories = ["Série"]
        #expect(film.rattacher(parmi: [chuteDeLondres]) == nil)

        film.categories = ["Magazine"]
        #expect(film.rattacher(parmi: [chuteDeLondres]) == nil)
    }

    @Test func candidatsDepuisLesReponsesTMDB() throws {
        let film = try #require(try JSONDecoder().decode(PageTMDB<FilmResume>.self, from: Fixture.donnees("search_movie")).resultats.first)
        #expect(film.candidat == CandidatRattachement(tmdbID: 550, type: .film, titre: "Fight Club", titreOriginal: "Fight Club", annee: 1999))
    }
}

@Suite("Rattachement sans année et chaînes")
struct RattachementSansAnneeTests {
    @Test func titreUniqueRetenuHomonymesEcartes() {
        let taken = CandidatRattachement(tmdbID: 8681, type: .film, titre: "Taken", titreOriginal: "Taken", annee: 2008)
        let autre = CandidatRattachement(tmdbID: 9, type: .film, titre: "Taken", titreOriginal: "Taken", annee: 1999)
        let taken2 = CandidatRattachement(tmdbID: 82675, type: .film, titre: "Taken 2", titreOriginal: "Taken 2", annee: 2012)
        #expect(Rattacheur.rattacherSansAnnee(titre: "Taken", parmi: [taken, taken2]) == taken)
        #expect(Rattacheur.rattacherSansAnnee(titre: "Taken", parmi: [taken, autre]) == nil)
    }

    @Test func conjonctionAnglaiseEtEsperluette() {
        #expect(NormalisationTitre.equivalents("Jerry and Marge Go Large", "Jerry & Marge Go Large"))
    }

    @Test func fichierSelonLesChaines() {
        #expect(GuideTVClient.fichier(pour: ["TF1.fr", "M6.fr"]) == .tnt)
        #expect(GuideTVClient.fichier(pour: ["TF1.fr", "RTSUn.ch"]) == .complet)
        #expect(ChaineGuide.parDefaut.map(\.nom) == ["RTS 1", "RTS 2", "TF1", "France 2", "France 3", "M6", "Arte"])
    }
}
