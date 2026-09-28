import Foundation
import Testing
@testable import SeanceKit

@Suite("Titres identifiés à la main")
struct IdentificationsTMDBTests {
    /// Deux films « The Runner » sortis en 2026 (le cas du 28.09.2026) : Séance ne choisit pas seule.
    private let recherche = RechercheSimulee(films: ["The Runner": [
        RechercheSimulee.film(1_386_315, "The Runner", "The Runner", "2026-09-02"),
        RechercheSimulee.film(2_000_001, "The Runner", "The Runner", "2026-02-05"),
        RechercheSimulee.film(3_000_001, "The Runner", "The Runner", "1999-09-09"),
    ]])

    private func titre(_ id: Int, _ type: TypeTitre = .film, _ nom: String = "The Runner") -> TitreResume {
        TitreResume(reference: ReferenceTitre(type: type, tmdbID: id), titre: nom, titreOriginal: nom, langueOriginale: "en",
                    synopsis: "", genres: [28], cheminAffiche: "/a.jpg", cheminFond: "/f.jpg", noteMoyenne: 7, nombreVotes: 100,
                    date: DateTMDB(texte: "2026-09-02"))
    }

    @Test func lesHomonymesNeSontPasRattachesSeuls() async throws {
        let index = IndexNAS.construire([FichierDistant(chemin: "Films/The.Runner.2026.mkv", taille: 1)])
        let resultats = try await RattachementNAS(recherche: recherche).rattacher(index.entrees)
        #expect(resultats.first?.titre == nil)
    }

    @Test func leChoixLEmporteSansRecherche() async throws {
        var identifications = IdentificationsTMDB()
        identifications.choisir(titre(1_386_315), pour: IdentificationsTMDB.cleNAS(chemin: "Films/The.Runner.2026.mkv"))
        let index = IndexNAS.construire([
            FichierDistant(chemin: "Films/The.Runner.2026.mkv", taille: 1),
            // Une autre copie du même film, écrite autrement : même œuvre, même choix.
            FichierDistant(chemin: "NEW/The Runner (2026) 1080p.mp4", taille: 2),
        ])
        let resultats = try await RattachementNAS(recherche: recherche, identifications: identifications).rattacher(index.entrees)
        #expect(resultats.map { $0.titre?.reference.tmdbID } == [1_386_315])
        #expect(await recherche.appels.isEmpty)
    }

    @Test func unNomIllisibleSeRetientParSonChemin() {
        #expect(IdentificationsTMDB.cleNAS(chemin: "Films/[1080p].mkv") == "nas-fichier|Films/[1080p].mkv")
        #expect(IdentificationsTMDB.cleNAS(chemin: "Séries/Reacher/Saison 01/Reacher.S01E02.mkv")
            == IdentificationsTMDB.cleNAS(chemin: "Séries/Reacher/Saison 02/Reacher.S02E05.mkv"))
    }

    @Test func lesPropositionsMettentLAnneeDAbord() async throws {
        let recherche = RechercheSimulee(
            films: ["The Runner": [
                RechercheSimulee.film(3_000_001, "The Runner", "The Runner", "1999-09-09"),
                RechercheSimulee.film(1_386_315, "The Runner", "The Runner", "2026-09-02"),
            ]],
            filmsParAnnee: ["The Runner|2026": [RechercheSimulee.film(1_386_315, "The Runner", "The Runner", "2026-09-02")]]
        )
        let propositions = try await IdentificationsTMDB.propositions("The Runner", type: .film, annee: 2026, recherche: recherche)
        #expect(propositions.map(\.reference.tmdbID) == [1_386_315, 3_000_001])
    }

    @Test func leGuideReprendLeChoix() async throws {
        var identifications = IdentificationsTMDB()
        identifications.choisir(titre(1_386_315), pour: IdentificationsTMDB.cleGuide(titre: "The Runner", type: .film, annee: 2026))
        var programme = ProgrammeTV(chaine: "M6.fr", debut: Date.suisse("2026-09-28 21:10"), fin: Date.suisse("2026-09-28 23:00"), titre: "The Runner")
        programme.categories = ["Film"]
        programme.annee = 2026
        var sansAnnee = programme
        sansAnnee.annee = nil
        let resultats = try await RattachementGuide(recherche: recherche, identifications: identifications).rattacher([programme, sansAnnee])
        #expect(resultats.map { $0.candidat?.tmdbID } == [1_386_315, 1_386_315])
    }

    @Test func leChoixLePlusRecentLEmporte() {
        let cle = IdentificationsTMDB.cleNAS(chemin: "Films/The.Runner.2026.mkv")
        var ici = IdentificationsTMDB()
        ici.choisir(titre(2_000_001), pour: cle, le: Date(timeIntervalSince1970: 100))
        var ailleurs = IdentificationsTMDB()
        ailleurs.choisir(titre(1_386_315), pour: cle, le: Date(timeIntervalSince1970: 200))
        let premiere = ici.fusionner(ailleurs)
        #expect(premiere)
        #expect(ici.titre(cle)?.reference.tmdbID == 1_386_315)
        // Oublié plus tard ici : l'entrée vide et datée l'emporte à son tour.
        var oubli = ici
        oubli.oublier(cle, le: Date(timeIntervalSince1970: 300))
        let seconde = ici.fusionner(oubli)
        #expect(seconde)
        #expect(ici.titre(cle) == nil)
        let troisieme = ici.fusionner(ailleurs)
        #expect(!troisieme)
        #expect(IdentificationsTMDB(donnees: ici.encoder()) == ici)
    }
}
