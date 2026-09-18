import Foundation
import Testing
@testable import SeanceKit

@Suite("Filtres d'Explorer")
struct FiltresExplorerTests {
    /// La maquette : Keanu Reeves, Action et Thriller, sans horreur, 1990 à 2019, arts martiaux, sur mes plateformes.
    private var maquette: FiltresExplorer {
        var f = FiltresExplorer()
        f.personnes = [PersonneFiltre(id: 6384, nom: "Keanu Reeves", cheminPortrait: nil)]
        f.basculer(genre: 28)
        f.basculer(genre: 53)
        f.exclure(genre: 27)
        f.anneeDebut = 1990
        f.anneeFin = 2019
        f.sousGenres = ["artsMartiaux"]
        f.mesPlateformes = true
        return f
    }

    @Test func criteresTMDBDeLaMaquette() {
        let c = maquette.criteres(abonnements: [8, 119], page: 2)
        #expect(c.acteurs == [6384])
        #expect(c.genresInclus == [28, 53] && c.genresExclus == [27])
        #expect(c.motsCles == [779, 780])
        #expect(c.sortieDepuis == DateTMDB(annee: 1990, mois: 1, jour: 1))
        #expect(c.sortieJusqua == DateTMDB(annee: 2019, mois: 12, jour: 31))
        #expect(c.fournisseurs == [8, 119] && c.monetisations == [.abonnement, .gratuit, .avecPublicite])
        #expect(c.page == 2)

        var avecRealisateur = maquette
        avecRealisateur.personnes.append(PersonneFiltre(id: 40644, nom: "Chad Stahelski", cheminPortrait: nil, estRealisateur: true))
        let r = avecRealisateur.criteres(abonnements: [])
        #expect(r.acteurs == [6384] && r.realisateurs == [40644])
    }

    @Test func pucesEtCroix() {
        var f = maquette
        #expect(f.criteresActifs == [.personne(6384), .genre(28), .genre(53), .genreExclu(27), .sousGenre("artsMartiaux"), .periode, .plateformes])
        f.retirer(.periode)
        f.retirer(.genre(53))
        #expect(f.anneeDebut == nil && f.anneeFin == nil)
        #expect(f.criteresActifs.count == 5)
        #expect(!f.filtresAppActifs)
        f.locaux.obtention = .surNAS
        #expect(f.filtresAppActifs && f.criteresActifs.last == .obtention)
    }

    @Test func genreNeutreInclusExcluNeutre() {
        var f = FiltresExplorer()
        f.basculer(genre: 28)
        #expect(f.genresInclus == [28])
        f.exclure(genre: 28)
        #expect(f.genresInclus.isEmpty && f.genresExclus == [28])
        f.basculer(genre: 28)
        #expect(f.genresExclus.isEmpty && f.genresInclus.isEmpty)
    }

    @Test func seriesParPersonneFiltreesSurLaFilmographie() throws {
        var f = maquette
        f.type = .serie
        f.genresInclus = [10759]
        f.genresExclus = []
        #expect(f.personnesParFilmographie && f.filtresAppActifs)
        #expect(f.criteres(abonnements: []).acteurs.isEmpty)

        let json = #"""
        {"cast": [
          {"id": 1, "media_type": "tv", "name": "Série d'action", "original_name": "Action", "genre_ids": [10759], "vote_average": 7.5, "vote_count": 900, "first_air_date": "2005-01-01", "original_language": "en"},
          {"id": 2, "media_type": "tv", "name": "Série trop récente", "original_name": "Recent", "genre_ids": [10759], "first_air_date": "2023-01-01", "original_language": "en"},
          {"id": 3, "media_type": "movie", "title": "Film", "original_title": "Film", "genre_ids": [10759], "release_date": "2000-01-01", "original_language": "en"},
          {"id": 4, "media_type": "tv", "name": "Talk-show", "original_name": "Talk", "genre_ids": [10767], "first_air_date": "2001-01-01", "original_language": "en"}
        ]}
        """#
        let filmographie = try JSONDecoder().decode(Filmographie.self, from: Data(json.utf8))
        #expect(filmographie.roles.filter(f.retient).map(\.tmdbID) == [1])
    }

    @Test func filtresEnregistresRelus() throws {
        let donnees = try JSONEncoder().encode(maquette)
        #expect(try JSONDecoder().decode(FiltresExplorer.self, from: donnees) == maquette)
    }
}

@Suite("Filtres appliqués par l'app aux fiches")
struct ProfilTitreTests {
    private func fiche() throws -> FicheFilm {
        let json = #"""
        {"id": 603692, "title": "John Wick : Chapitre 4", "original_title": "John Wick: Chapter 4", "original_language": "en",
         "overview": "", "runtime": 169, "genres": [{"id": 28, "name": "Action"}, {"id": 53, "name": "Thriller"}],
         "vote_average": 7.7, "vote_count": 7000, "release_date": "2023-03-22",
         "credits": {"cast": [{"id": 6384, "name": "Keanu Reeves", "order": 0}], "crew": [{"id": 40644, "name": "Chad Stahelski", "job": "Director"}]},
         "release_dates": {"results": [{"iso_3166_1": "CH", "release_dates": [{"release_date": "2023-03-22T00:00:00.000Z", "type": 3}]}]},
         "watch/providers": {"results": {"CH": {"flatrate": [{"provider_id": 119, "provider_name": "Prime", "display_priority": 1}],
                                                "rent": [{"provider_id": 2, "provider_name": "Apple TV", "display_priority": 2}]}}},
         "keywords": {"keywords": [{"id": 779, "name": "martial arts"}, {"id": 2708, "name": "hitman"}]}}
        """#
        return try JSONDecoder().decode(FicheFilm.self, from: Data(json.utf8))
    }

    @Test func chaqueCritereVerifieSurLaFiche() throws {
        let profil = ProfilTitre(film: try fiche())
        var f = FiltresExplorer()
        #expect(f.retient(profil, abonnements: []))

        func verifier(_ attendu: Bool, _ modifier: (inout FiltresExplorer) -> Void, _ ligne: Int = #line) {
            var copie = f
            modifier(&copie)
            #expect(copie.retient(profil, abonnements: [119]) == attendu, "ligne \(ligne)")
        }
        verifier(true) { $0.genresInclus = [28, 12] }
        verifier(false) { $0.genresInclus = [35] }
        verifier(false) { $0.genresExclus = [53] }
        verifier(true) { $0.sousGenres = ["artsMartiaux"] }
        verifier(false) { $0.sousGenres = ["braquage"] }
        verifier(true) { $0.personnes = [PersonneFiltre(id: 6384, nom: "Keanu", cheminPortrait: nil), PersonneFiltre(id: 40644, nom: "Chad", cheminPortrait: nil, estRealisateur: true)] }
        verifier(false) { $0.personnes = [PersonneFiltre(id: 6384, nom: "Keanu", cheminPortrait: nil), PersonneFiltre(id: 1, nom: "Autre", cheminPortrait: nil)] }
        verifier(true) { $0.personnes = [PersonneFiltre(id: 6384, nom: "Keanu", cheminPortrait: nil), PersonneFiltre(id: 1, nom: "Autre", cheminPortrait: nil)]; $0.personnesEnsemble = false }
        verifier(true) { $0.anneeDebut = 2020; $0.anneeFin = 2029 }
        verifier(false) { $0.anneeFin = 2019 }
        verifier(true) { $0.typesSortie = [.salles] }
        verifier(false) { $0.typesSortie = [.numerique] }
        verifier(false) { $0.noteMin = 8 }
        verifier(false) { $0.votesMin = 10_000 }
        verifier(false) { $0.dureeMax = 150 }
        verifier(false) { $0.langue = "fr" }
        verifier(true) { $0.mesPlateformes = true }
        verifier(false) { $0.mesPlateformes = true; $0.monetisations = [.location] }
        verifier(true) { $0.monetisations = [.location] }
        verifier(false) { $0.monetisations = [.achat] }

        f.type = .serie
        #expect(!f.retient(profil, abonnements: []))
    }

    @Test func listeLocaleEtTri() {
        var f = FiltresExplorer()
        #expect(!f.partDUneListeLocale)
        f.locaux.obtention = .surNAS
        #expect(f.partDUneListeLocale)
        f.locaux.obtention = .pasSurNAS
        f.locaux.dejaVu = .vus
        #expect(f.partDUneListeLocale)
    }

    /// Le sélecteur de source d'Explorer : un seul choix, écrit dans les critères existants.
    @Test func sourceDesIdees() {
        var f = FiltresExplorer.parDefaut(avecPlateformes: true)
        #expect(f.source == .streaming)

        f.source = .nas
        #expect(f.locaux.obtention == .surNAS)
        #expect(!f.mesPlateformes, "« Sur mes plateformes » viderait la liste du NAS")
        #expect(f.partDUneListeLocale)
        #expect(f.ditParLaSource(.obtention))

        f.source = .tele
        #expect(f.locaux.obtention == .tous)
        #expect(f.locaux.tele == .cetteSemaine)
        f.locaux.tele = .ceSoir
        f.source = .tele
        #expect(f.locaux.tele == .ceSoir, "Rechoisir la télé garde « ce soir »")
        #expect(f.ditParLaSource(.tele))

        f.locaux.chaines = ["TF1.fr"]
        f.source = .toutes
        #expect(f.source == .toutes)
        #expect(f.locaux.tele == .indifferent && f.locaux.chaines.isEmpty && !f.mesPlateformes)
        #expect(!f.partDUneListeLocale)

        // « Pas sur le NAS » n'est pas une source : il survit au changement, et garde sa puce.
        f.locaux.obtention = .pasSurNAS
        f.source = .streaming
        #expect(f.locaux.obtention == .pasSurNAS && f.mesPlateformes)
        #expect(!f.ditParLaSource(.obtention))
        #expect(f.ditParLaSource(.plateformes))
    }
}
