import Foundation
import SeanceKit
import SwiftData
import Testing
@testable import SeanceDonnees

/// Fiches TMDB minimales, construites par décodage comme en production.
private enum TMDB {
    static func film() throws -> FicheFilm {
        try decoder(#"""
        {"id": 267860, "title": "La Chute de Londres", "original_title": "London Has Fallen", "original_language": "en",
         "overview": "", "runtime": 99, "genres": [{"id": 28, "name": "Action"}, {"id": 53, "name": "Thriller"}],
         "vote_average": 6.3, "vote_count": 5000, "poster_path": "/chute.jpg", "release_date": "2016-03-02",
         "credits": {"cast": [
            {"id": 17276, "name": "Gerard Butler", "order": 0},
            {"id": 2176, "name": "Aaron Eckhart", "order": 1},
            {"id": 192, "name": "Morgan Freeman", "order": 2}], "crew": []}}
        """#)
    }

    static func serie() throws -> SerieDetail {
        try decoder(#"""
        {"id": 108978, "name": "Reacher", "original_name": "Reacher", "original_language": "en", "overview": "",
         "status": "Returning Series", "in_production": true, "number_of_seasons": 3, "number_of_episodes": 24,
         "episode_run_time": [50], "seasons": [], "vote_average": 8.0, "vote_count": 1500,
         "genres": [{"id": 10759, "name": "Action & Adventure"}], "poster_path": "/reacher.jpg",
         "aggregate_credits": {"cast": [{"id": 1, "name": "Alan Ritchson", "order": 0}], "crew": []}}
        """#)
    }

    static func episodes(saison: Int, nombre: Int) throws -> [EpisodeTMDB] {
        try (1...nombre).map { n in
            try decoder(#"{"id": \#(saison * 100 + n), "name": "E\#(n)", "overview": "", "episode_number": \#(n), "season_number": \#(saison), "runtime": \#(n == 2 ? "null" : "48"), "air_date": "2022-02-04"}"#)
        }
    }

    private static func decoder<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}

@Suite("Services SwiftData")
@MainActor
struct ServicesTests {
    @Test func suivrePuisMarquerUnFilmVu() throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let service = ServiceSuivi(contexte: conteneur.mainContext)
        let film = try TMDB.film()

        try service.suivre(film: film)
        let suivi = try #require(try service.suivi(film.reference))
        #expect(suivi.statut == .aVoir)
        #expect(suivi.acteursPrincipaux == ["Gerard Butler", "Aaron Eckhart", "Morgan Freeman"])
        #expect(suivi.genres == [28, 53])

        try service.marquerVu(film: film, note: 7, le: Date(timeIntervalSince1970: 1_789_000_000))
        #expect(suivi.statut == .termine)
        #expect(suivi.note == 7)
        #expect(try service.visionnages(film.reference).map(\.dureeMinutes) == [99])
        #expect(try service.estVu(film.reference))

        // Un nouvel ajout ne remet pas un film vu « à voir ».
        try service.suivre(film: film)
        #expect(suivi.statut == .termine)
        #expect(try conteneur.mainContext.fetchCount(FetchDescriptor<Suivi>()) == 1)
    }

    @Test func cocherDesEpisodesSansDoublon() throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let service = ServiceSuivi(contexte: conteneur.mainContext)
        let serie = try TMDB.serie()
        let saison1 = try TMDB.episodes(saison: 1, nombre: 3)

        #expect(try service.cocher(Array(saison1.prefix(2)), serie: serie) == 2)
        #expect(try service.cocher(saison1, serie: serie) == 1)
        #expect(try service.episodesVus(serie.reference) == [
            NumeroEpisode(saison: 1, episode: 1), NumeroEpisode(saison: 1, episode: 2), NumeroEpisode(saison: 1, episode: 3),
        ])
        // Épisode sans durée TMDB : la durée type de la série.
        #expect(try service.visionnages(serie.reference).map(\.dureeMinutes).sorted() == [48, 48, 50])
        #expect(try service.suivi(serie.reference)?.statut == .enCours)

        try service.noter(NumeroEpisode(saison: 1, episode: 3), serie: serie.reference, note: 9)
        try service.decocher(NumeroEpisode(saison: 1, episode: 1), serie: serie.reference)
        #expect(try service.episodesVus(serie.reference).count == 2)
        #expect(try service.visionnages(serie.reference).compactMap(\.note) == [9])
    }

    @Test func cocherDepuisUnWidget() throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let contexte = conteneur.mainContext
        let service = ServiceSuivi(contexte: contexte)
        let reacher = ReferenceTitre(type: .serie, tmdbID: 108_978)
        contexte.insert(Suivi(reference: reacher, titre: "Reacher", statut: .aVoir))
        let numero = NumeroEpisode(saison: 2, episode: 6)
        #expect(try service.cocher(numero, serie: reacher, dureeMinutes: 50))
        // Deux touches sur le même bouton : un seul visionnage.
        #expect(try !service.cocher(numero, serie: reacher, dureeMinutes: 50))
        #expect(try service.episodesVus(reacher) == [numero])
        #expect(try service.suivi(reacher)?.statut == .enCours)
        #expect(try service.visionnages(reacher).first?.dureeMinutes == 50)
    }

    @Test func exclusionDeLangue() throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let service = ServiceSuivi(contexte: conteneur.mainContext)
        let reference = ReferenceTitre(type: .film, tmdbID: 496_243)
        try service.exclureLangue(reference, titre: "Parasite")
        #expect(try service.suivi(reference)?.exclusionLangue == true)
    }

    @Test func dejaVuAvantHorsStatistiquesMaisDansLesGouts() throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let contexte = conteneur.mainContext
        let service = ServiceSuivi(contexte: contexte)
        let film = try TMDB.film()
        let serie = try TMDB.serie()

        try service.marquerVu(film: film, anterieur: true)
        #expect(try service.cocher(try TMDB.episodes(saison: 1, nombre: 3), serie: serie, anterieur: true) == 3)
        #expect(try service.estVu(film.reference))
        #expect(try service.suivi(film.reference)?.statut == .termine)

        // Ni heures ni années : la date du visionnage est inconnue.
        let statistiques = ServiceStatistiques(contexte: contexte)
        #expect(try statistiques.bilan(annee: nil).minutesTotales == 0)
        #expect(try statistiques.annees().isEmpty)

        // Mais les deux titres sortent des suggestions.
        let gouts = ServiceGouts(contexte: contexte)
        let dejaVus = try gouts.contexteCandidats().dejaVus
        #expect(dejaVus.contains(film.reference) && dejaVus.contains(serie.reference))

        // La note du titre oriente les goûts : la série adorée, le film détesté.
        try service.noter(serie: serie, note: 10)
        try service.noter(film: film, note: 2)
        #expect(try service.suivi(serie.reference)?.note == 10)
        #expect(try service.visionnages(film.reference).map(\.note) == [2])
        let profil = try gouts.profil()
        #expect(profil.affinite(genre: 10759) > 0.2)
        #expect(profil.affinite(genre: 53) < 0)

        // Une note effacée ne laisse qu'un visionnage, faiblement positif.
        try service.noter(film: film, note: nil)
        #expect(try service.suivi(film.reference)?.note == nil)
        #expect(try gouts.profil().affinite(genre: 53) > 0)
    }

    @Test func listesNommees() throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let contexte = conteneur.mainContext
        let service = ServiceListes(contexte: contexte)
        let heat = ReferenceTitre(type: .film, tmdbID: 949)
        let reacher = ReferenceTitre(type: .serie, tmdbID: 108_978)

        let statham = try #require(try service.creer("  Soirées Statham "))
        #expect(statham.nom == "Soirées Statham")
        #expect(try service.creer("soirees statham") === statham, "même nom, même liste")
        #expect(try service.creer("   ") == nil)

        try service.ajouter(heat, titre: "Heat", cheminAffiche: "/heat.jpg", a: statham)
        try service.ajouter(heat, titre: "Heat", cheminAffiche: "/heat.jpg", a: statham)
        // Un titre sans aperçu (ancienne sauvegarde) emprunte son nom au titre suivi.
        statham.titres.append(reacher)
        contexte.insert(Suivi(reference: reacher, titre: "Reacher", statut: .enCours, cheminAffiche: "/reacher.jpg"))
        try contexte.save()
        #expect(try service.titres(statham).map(\.titre) == ["Heat", "Reacher"])

        // Aller-retour par la sauvegarde : les aperçus suivent.
        let fichier = try ServiceSauvegarde(contexte: contexte).exporter().encoder()
        let cible = try EntrepotSeance.conteneur(.memoire)
        try ServiceSauvegarde(contexte: cible.mainContext).importer(try Sauvegarde.decoder(fichier))
        let relue = try #require(try ServiceListes(contexte: cible.mainContext).listes().first)
        #expect(relue.titres == [heat, reacher] && relue.apercus.map(\.cheminAffiche) == ["/heat.jpg"])

        try service.retirer(heat, de: statham)
        #expect(statham.titres == [reacher] && statham.apercus.isEmpty)
        try service.supprimer(statham)
        #expect(try service.listes().isEmpty)
    }

    @Test func soireesPrevuesALAvance() throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let contexte = conteneur.mainContext
        let service = ServiceSoiree(contexte: contexte)
        let jeudi = Date.suisse("2026-09-17 20:00")
        let heat = ReferenceTitre(type: .film, tmdbID: 949)
        let wick = ReferenceTitre(type: .film, tmdbID: 245_891)
        let samedi = ServiceSoiree.soiree(jour: Date.suisse("2026-09-19 12:00"))
        #expect(samedi == "2026-09-19")
        #expect(ServiceSoiree.jour(samedi) == Date.suisse("2026-09-19 12:00"))

        // Une soirée passée, une pour samedi, puis un ajout pour ce soir : seule la passée disparaît.
        contexte.insert(SelectionSoir(reference: ReferenceTitre(type: .film, tmdbID: 1), titre: "Hier", cheminAffiche: nil, soiree: "2026-09-16"))
        try service.retenir(heat, titre: "Heat", cheminAffiche: nil, soiree: samedi, maintenant: jeudi)
        try service.retenir(wick, titre: "John Wick", cheminAffiche: nil, maintenant: jeudi)
        #expect(try service.selection(maintenant: jeudi).map(\.titre) == ["John Wick"])
        #expect(try service.aVenir(maintenant: jeudi).map(\.titre) == ["Heat"])
        #expect(try contexte.fetchCount(FetchDescriptor<SelectionSoir>()) == 2)

        // Prévu ailleurs, le titre est déplacé, jamais dédoublé ; une date passée vaut ce soir.
        try service.retenir(heat, titre: "Heat", cheminAffiche: nil, soiree: "2026-09-21", maintenant: jeudi)
        #expect(try service.aVenir(maintenant: jeudi).map(\.soiree) == ["2026-09-21"])
        try service.retenir(heat, titre: "Heat", cheminAffiche: nil, soiree: "2026-09-01", maintenant: jeudi)
        #expect(try service.selection(maintenant: jeudi).map(\.titre).sorted() == ["Heat", "John Wick"])
        #expect(try service.aVenir(maintenant: jeudi).isEmpty)

        // Le jour venu, la soirée prévue devient celle de ce soir.
        try service.retenir(heat, titre: "Heat", cheminAffiche: nil, soiree: samedi, maintenant: jeudi)
        #expect(try service.selection(maintenant: Date.suisse("2026-09-19 19:00")).map(\.titre) == ["Heat"])
        try service.retirer(heat, soiree: samedi)
        #expect(try service.aVenir(maintenant: jeudi).isEmpty)
    }

    @Test func serieSansEpisodeRedevientAVoir() throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let service = ServiceSuivi(contexte: conteneur.mainContext)
        let serie = try TMDB.serie()
        try service.suivre(serie: serie)
        try service.cocher(Array(try TMDB.episodes(saison: 1, nombre: 2).prefix(1)), serie: serie)
        #expect(try service.suivi(serie.reference)?.statut == .enCours)
        try service.decocher(NumeroEpisode(saison: 1, episode: 1), serie: serie.reference)
        #expect(try service.suivi(serie.reference)?.statut == .aVoir)
    }

    @Test func marquerCommeNonVuUnFilm() throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let service = ServiceSuivi(contexte: conteneur.mainContext)
        let film = try TMDB.film()
        try service.marquerVu(film: film, note: 9, anterieur: true)
        #expect(try service.estVu(film.reference))

        try service.marquerNonVu(film: film.reference)
        #expect(try !service.estVu(film.reference))
        let suivi = try #require(try service.suivi(film.reference))
        #expect(suivi.statut == .aVoir && suivi.note == nil)
        #expect(try !ServiceGouts(contexte: conteneur.mainContext).contexteCandidats().dejaVus.contains(film.reference))
    }

    @Test func supprimerDesTerminesGardeLHistorique() throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let contexte = conteneur.mainContext
        let service = ServiceSuivi(contexte: contexte)
        let film = try TMDB.film()
        try service.marquerVu(film: film, note: 9)
        let suivi = try #require(try service.suivi(film.reference))
        #expect(try service.termines().count == 1)

        try service.supprimerDesTermines([suivi])
        #expect(try service.termines().isEmpty)
        // Toujours vu, noté, compté et hors des suggestions.
        #expect(try service.estVu(film.reference) && suivi.note == 9)
        #expect(try ServiceGouts(contexte: contexte).contexteCandidats().dejaVus.contains(film.reference))
        #expect(try ServiceStatistiques(contexte: contexte).bilan(annee: nil).nombreFilms == 1)

        // Sauvegardé tel quel.
        let fichier = try ServiceSauvegarde(contexte: contexte).exporter().encoder()
        let cible = try EntrepotSeance.conteneur(.memoire)
        try ServiceSauvegarde(contexte: cible.mainContext).importer(try Sauvegarde.decoder(fichier))
        #expect(try ServiceSuivi(contexte: cible.mainContext).termines().isEmpty)

        // Un changement de statut le fait réapparaître.
        suivi.statut = .aVoir
        #expect(!suivi.masque)
        suivi.statut = .termine
        #expect(try service.termines().count == 1)
    }

    @Test func sauvegardeAllerRetourSansDoublon() throws {
        let source = try EntrepotSeance.conteneur(.memoire)
        let suivi = ServiceSuivi(contexte: source.mainContext)
        try suivi.marquerVu(film: try TMDB.film(), note: 8)
        try suivi.cocher(try TMDB.episodes(saison: 1, nombre: 3), serie: try TMDB.serie(), anterieur: true)
        let liste = ListePerso(nom: "Soirées Statham")
        liste.titres = [ReferenceTitre(type: .film, tmdbID: 267_860)]
        source.mainContext.insert(liste)
        source.mainContext.insert(Abonnement(providerID: 8, nom: "Netflix"))
        source.mainContext.insert(Chaine(identifiantGuide: "M6.fr", nom: "M6", source: .xmltvfr))
        try source.mainContext.save()
        try ServiceActeurs(contexte: source.mainContext).suivre(personneID: 6384, nom: "Keanu Reeves", cheminPortrait: nil)

        let fichier = try ServiceSauvegarde(contexte: source.mainContext).exporter().encoder()

        let cible = try EntrepotSeance.conteneur(.memoire)
        let importeur = ServiceSauvegarde(contexte: cible.mainContext)
        let plan = try importeur.importer(try Sauvegarde.decoder(fichier))
        #expect(plan.suivis.count == 2)
        #expect(plan.visionnages.count == 4)
        #expect(try cible.mainContext.fetch(FetchDescriptor<Visionnage>()).filter(\.anterieur).count == 3)
        #expect(try cible.mainContext.fetch(FetchDescriptor<ListePerso>()).first?.titres.count == 1)
        #expect(try cible.mainContext.fetchCount(FetchDescriptor<Chaine>()) == 1)
        #expect(try cible.mainContext.fetch(FetchDescriptor<ActeurSuivi>()).map(\.nom) == ["Keanu Reeves"])

        // Réimporter le même fichier n'ajoute rien.
        #expect(try importeur.importer(try Sauvegarde.decoder(fichier)).estVide)
        #expect(try cible.mainContext.fetchCount(FetchDescriptor<Visionnage>()) == 4)
    }

    @Test func purgeDuCache() throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let contexte = conteneur.mainContext
        let maintenant = Date(timeIntervalSince1970: 1_789_000_000)
        let ancien = TitreCache(reference: ReferenceTitre(type: .film, tmdbID: 1), donnees: Data(), majLe: maintenant.addingTimeInterval(-200 * 86_400))
        let recent = TitreCache(reference: ReferenceTitre(type: .film, tmdbID: 2), donnees: Data(), majLe: maintenant.addingTimeInterval(-10 * 86_400))
        var passe = ProgrammeTV(chaine: "M6.fr", debut: maintenant.addingTimeInterval(-7200), fin: maintenant.addingTimeInterval(-600), titre: "Heat")
        passe.categories = ["Film"]
        var aVenir = passe
        aVenir.fin = maintenant.addingTimeInterval(3600)
        [ancien, recent].forEach(contexte.insert)
        contexte.insert(Diffusion(programme: passe, rattachement: nil))
        contexte.insert(Diffusion(programme: aVenir, rattachement: nil))
        try contexte.save()

        let rapport = try EntretienCache(contexte: contexte).purger(maintenant: maintenant)
        #expect(rapport == EntretienCache.Rapport(fichesSupprimees: 1, diffusionsSupprimees: 1))
        #expect(try contexte.fetch(FetchDescriptor<TitreCache>()).map(\.tmdbID) == [2])
    }
}

@Suite("Ma soirée")
@MainActor
struct ServiceSoireeTests {
    @Test func retenirSansDoublonEtSoireeDeSixHeureASixHeure() throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let service = ServiceSoiree(contexte: conteneur.mainContext)
        let heat = ReferenceTitre(type: .film, tmdbID: 949)
        let soir = Date(timeIntervalSince1970: 1_789_588_800) // 16.09.2026 22:00 en Suisse

        try service.retenir(heat, titre: "Heat", cheminAffiche: nil, maintenant: soir)
        try service.retenir(heat, titre: "Heat", cheminAffiche: nil, maintenant: soir)
        #expect(try service.selection(maintenant: soir).count == 1)

        // À 1 h du matin, c'est encore la même soirée ; le lendemain à midi, une nouvelle.
        #expect(try service.estRetenu(heat, maintenant: soir.addingTimeInterval(3 * 3600)))
        #expect(try service.selection(maintenant: soir.addingTimeInterval(14 * 3600)).isEmpty)

        try service.retirer(heat, maintenant: soir)
        #expect(try service.selection(maintenant: soir).isEmpty)
    }
}

@Suite("Siri et widgets")
@MainActor
struct SiriEtWidgetsTests {
    @Test func prochainsEpisodesApresCochageEtPhrase() throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let contexte = conteneur.mainContext
        let reacher = ReferenceTitre(type: .serie, tmdbID: 108_978)
        let instantane = InstantaneWidgets(series: [
            .init(id: 108_978, nom: "Reacher", cheminAffiche: nil, episodes: [
                .init(saison: 2, numero: 6, titre: nil, dureeMinutes: 50), .init(saison: 2, numero: 7, titre: nil, dureeMinutes: 50),
            ]),
        ])
        let service = ServiceSoiree(contexte: contexte)
        #expect(try service.phrase(nil) == "Rien de prévu ce soir. Ouvre Séance : l'onglet Ce soir te propose des idées selon tes goûts.")

        // Le ✓ d'un widget fait passer au suivant.
        try ServiceSuivi(contexte: contexte).cocher(NumeroEpisode(saison: 2, episode: 6), serie: reacher, dureeMinutes: 50)
        #expect(try service.prochainsEpisodes(instantane).first?.episode.numero == 7)

        try service.retenir(reacher, titre: "Reacher", cheminAffiche: nil)
        #expect(try service.phrase(instantane) == "Ce soir, tu as prévu Reacher, saison 2, épisode 7.")
    }
}

@Suite("Premier lancement")
@MainActor
struct PremierLancementTests {
    private func film(_ id: Int, _ titre: String, genres: [Int]) throws -> TitreResume {
        let json = #"{"id": \#(id), "title": "\#(titre)", "original_title": "\#(titre)", "original_language": "en", "overview": "", "genre_ids": \#(genres), "vote_average": 8, "vote_count": 9000, "popularity": 50, "release_date": "2014-10-24"}"#
        return try JSONDecoder().decode(FilmResume.self, from: Data(json.utf8)).titreResume
    }

    @Test func genresEtNotesFontLeProfilEtSortentDesSuggestions() throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let contexte = conteneur.mainContext
        let gouts = ServiceGouts(contexte: contexte)
        #expect(try !gouts.dejaPersonnalise())

        try gouts.declarer([
            .init(libelle: "Action", genres: [28, 10759]),
            .init(libelle: "Arts martiaux", genres: [], motsCles: [779, 780]),
        ])
        #expect(try gouts.interetsDeclares() == ["Action", "Arts martiaux"])
        #expect(try gouts.dejaPersonnalise())

        // Une nouvelle sélection remplace l'ancienne.
        try gouts.declarer([.init(libelle: "Thriller", genres: [53])])
        #expect(try gouts.interetsDeclares() == ["Thriller"])

        let wick = try film(245_891, "John Wick", genres: [28, 53])
        try gouts.noterTitreConnu(wick, note: 9)
        try gouts.noterTitreConnu(try film(1, "Comédie ratée", genres: [35]), note: 2)

        let profil = try gouts.profil()
        #expect(profil.affinite(genre: 53) > 0.5)
        #expect(profil.affinite(genre: 35) < 0)
        #expect(try gouts.contexteCandidats().dejaVus.contains(wick.reference))
        let suivi = try #require(try ServiceSuivi(contexte: contexte).suivi(wick.reference))
        #expect(suivi.statut == .termine && suivi.note == 9 && !suivi.alertesActives)
    }
}

@Suite("Statistiques et bilan")
@MainActor
struct ServiceStatistiquesTests {
    @Test func heuresMeilleurFilmEtAnnees() throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let contexte = conteneur.mainContext
        let heat = ReferenceTitre(type: .film, tmdbID: 949)
        let wick = ReferenceTitre(type: .film, tmdbID: 245_891)
        let reacher = ReferenceTitre(type: .serie, tmdbID: 108_978)
        let suiviHeat = Suivi(reference: heat, titre: "Heat", statut: .termine)
        suiviHeat.genres = [28, 80]
        suiviHeat.acteursPrincipaux = ["Al Pacino", "Robert De Niro"]
        contexte.insert(suiviHeat)
        let suiviWick = Suivi(reference: wick, titre: "John Wick", statut: .termine)
        suiviWick.genres = [28]
        suiviWick.acteursPrincipaux = ["Keanu Reeves"]
        suiviWick.acteursPrincipauxIDs = [6384]
        contexte.insert(suiviWick)
        let suiviReacher = Suivi(reference: reacher, titre: "Reacher", statut: .enCours)
        suiviReacher.genres = [10759]
        contexte.insert(suiviReacher)

        let mars = Date.suisse("2026-03-14 21:00")
        let heatVu = Visionnage(reference: heat, dureeMinutes: 170, vuLe: mars)
        heatVu.note = 9
        contexte.insert(heatVu)
        let wickVu = Visionnage(reference: wick, dureeMinutes: 101, vuLe: Date.suisse("2026-06-01 21:00"))
        wickVu.note = 9
        contexte.insert(wickVu)
        for episode in 1...3 {
            contexte.insert(Visionnage(reference: reacher, saison: 1, episode: episode, dureeMinutes: 50, vuLe: Date.suisse("2026-06-02 20:00").addingTimeInterval(Double(episode) * 3600)))
        }
        contexte.insert(Visionnage(reference: heat, dureeMinutes: 170, vuLe: Date.suisse("2025-12-24 21:00")))
        try contexte.save()

        let service = ServiceStatistiques(contexte: contexte)
        let annee = try service.bilan(annee: 2026)
        #expect(annee.minutesTotales == 170 + 101 + 150)
        #expect(annee.nombreFilms == 2 && annee.nombreEpisodes == 3)
        #expect(annee.genres.first?.cle == 28)
        // Les acteurs du classement portent leur identifiant TMDB et les titres comptés.
        #expect(annee.acteurs.first { $0.cle.nom == "Keanu Reeves" }?.titres == [wick])
        #expect(annee.acteurs.first { $0.cle.nom == "Keanu Reeves" }?.cle.id == 6384)
        #expect(annee.recordEpisodes?.nombreEpisodes == 3)
        #expect(try service.bilan(annee: nil).minutesTotales == 591)
        #expect(try service.annees() == [2026, 2025])
        // À note égale, le plus récent l'emporte.
        #expect(try service.meilleurFilm(annee: 2026)?.titre == "John Wick")
        #expect(try service.meilleurFilm(annee: 2025) == nil)
        #expect(ServiceStatistiques.bilanOuvert(maintenant: Date.suisse("2026-12-02 10:00")))
        #expect(!ServiceStatistiques.bilanOuvert(maintenant: Date.suisse("2026-09-17 10:00")))
    }
}

private extension Date {
    /// Heure de Suisse, par exemple `Date.suisse("2026-09-17 21:10")`.
    static func suisse(_ texte: String) -> Date {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "Europe/Zurich")
        format.dateFormat = "yyyy-MM-dd HH:mm"
        return format.date(from: texte)!
    }
}
