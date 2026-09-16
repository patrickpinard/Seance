import Foundation
import Testing
@testable import SeanceKit

@Suite("Alertes")
struct PlanificateurAlertesTests {
    private let reglages = ReglagesAlertes()
    private let chute = ReferenceTitre(type: .film, tmdbID: 267_860)
    private let netflix = Construire.fournisseur(8, "Netflix")
    private let prime = Construire.fournisseur(119, "Amazon Prime Video")

    @Test func arriveeSurUnePlateformeCochee() {
        let apres = Construire.offres(abonnement: [netflix, prime])
        let matin = PlanificateurAlertes.arriveesSurPlateformes(chute, titre: "La Chute de Londres", avant: [119], apres: apres,
                                                                abonnements: [8, 119], maintenant: Date.suisse("2026-09-17 10:00"), reglages: reglages)
        #expect(matin.map(\.motif) == [.arriveeSurPlateforme(nom: "Netflix")])
        #expect(matin.first?.date == Date.suisse("2026-09-17 18:00"))

        let soir = PlanificateurAlertes.arriveesSurPlateformes(chute, titre: "La Chute de Londres", avant: [], apres: apres,
                                                               abonnements: [8], maintenant: Date.suisse("2026-09-17 19:00"), reglages: reglages)
        #expect(soir.map(\.date) == [Date.suisse("2026-09-18 18:00")])
    }

    @Test func episodeEtNouvelleSaison() throws {
        let maintenant = Date.suisse("2026-09-17 09:00")
        // Diffusé aujourd'hui : la veille est passée, reste le jour même.
        let episode = try Construire.serie(prochain: Construire.episode(3, 4, diffuse: "2026-09-17"))
        #expect(PlanificateurAlertes.episodes(episode, maintenant: maintenant, reglages: reglages).map(\.motif)
            == [.nouvelEpisode(NumeroEpisode(saison: 3, episode: 4))])

        let saison = try Construire.serie(prochain: Construire.episode(4, 1, diffuse: "2026-10-02"))
        let alertes = PlanificateurAlertes.episodes(saison, maintenant: maintenant, reglages: reglages)
        #expect(alertes.map(\.motif) == [.veilleEpisode(NumeroEpisode(saison: 4, episode: 1)), .nouvelleSaison(4)])
        #expect(alertes.map(\.date) == [Date.suisse("2026-10-01 18:00"), Date.suisse("2026-10-02 18:00")])

        // En mode « saisons », un épisode ordinaire ne déclenche rien ; une nouvelle saison, si.
        let prochainEpisode = try Construire.serie(prochain: Construire.episode(3, 5, diffuse: "2026-09-24"))
        #expect(PlanificateurAlertes.episodes(prochainEpisode, mode: .saisons, maintenant: maintenant, reglages: reglages).isEmpty)
        #expect(PlanificateurAlertes.episodes(saison, mode: .saisons, maintenant: maintenant, reglages: reglages).count == 2)

        var sansEpisodes = reglages
        sansEpisodes.typesActifs.remove(.episode)
        #expect(PlanificateurAlertes.episodes(saison, maintenant: maintenant, reglages: sansEpisodes).isEmpty)
    }

    @Test func sortiesEnSuisse() {
        let dates = Construire.datesDeSortie(ch: [
            (3, "2026-10-08T00:00:00.000Z"), (2, "2026-10-01T00:00:00.000Z"), (4, "2026-12-15T00:00:00.000Z"), (1, "2026-09-01T00:00:00.000Z"),
        ])
        let alertes = PlanificateurAlertes.sortiesFilm(chute, titre: "Film", dates: dates, maintenant: Date.suisse("2026-09-17 09:00"), reglages: reglages)
        #expect(alertes.map(\.motif) == [.veilleSortie(salles: true), .sortieSalles, .sortieNumerique])
        #expect(alertes.map(\.date) == [Date.suisse("2026-09-30 18:00"), Date.suisse("2026-10-01 18:00"), Date.suisse("2026-12-15 18:00")])
    }

    @Test func sortieEnFranceOuMondialeFauteDeDateSuisse() {
        let france = Construire.decoder(DatesDeSortie.self, ["results": [
            ["iso_3166_1": "US", "release_dates": [["release_date": "2026-10-03T00:00:00.000Z", "type": 3]]],
            ["iso_3166_1": "FR", "release_dates": [["release_date": "2026-10-08T00:00:00.000Z", "type": 3]]],
        ]])
        var sansVeille = reglages
        sansVeille.veille = false
        let maintenant = Date.suisse("2026-09-17 09:00")
        #expect(PlanificateurAlertes.sortiesFilm(chute, titre: "Film", dates: france, maintenant: maintenant, reglages: sansVeille).map(\.date)
            == [Date.suisse("2026-10-08 18:00")])

        let mondiale = PlanificateurAlertes.sortiesFilm(chute, titre: "Film", dates: nil, dateMondiale: DateTMDB(annee: 2026, mois: 11, jour: 4),
                                                        maintenant: maintenant, reglages: sansVeille)
        #expect(mondiale.map(\.motif) == [.sortie])
    }

    @Test func annoncesDeSaisonEtDeSortie() throws {
        let maintenant = Date.suisse("2026-09-17 09:00")
        let saison = try Construire.serie(prochain: Construire.episode(4, 1, diffuse: "2027-03-12"))
        let annonce = try #require(PlanificateurAlertes.annonceSerie(saison))
        #expect(annonce.cle == "saison:4@2027-03-12")

        // Première observation : rien ; puis la date apparaît : une alerte, au prochain envoi.
        #expect(PlanificateurAlertes.annonce(chute, titre: "Reacher", avant: nil, apres: annonce.cle,
                                             motif: .annonceSaison(saison: 4, date: annonce.date), maintenant: maintenant, reglages: reglages).isEmpty)
        let alertes = PlanificateurAlertes.annonce(chute, titre: "Reacher", avant: PlanificateurAlertes.aucuneAnnonce, apres: annonce.cle,
                                                   motif: .annonceSaison(saison: 4, date: annonce.date), maintenant: maintenant, reglages: reglages)
        #expect(alertes.map(\.date) == [Date.suisse("2026-09-17 18:00")])
        #expect(PlanificateurAlertes.texte(alertes[0].motif, fuseau: .suisse) == "La saison 4 arrive le 12 mars 2027")

        // Un épisode ordinaire n'est pas une annonce.
        #expect(PlanificateurAlertes.annonceSerie(try Construire.serie(prochain: Construire.episode(3, 5, diffuse: "2026-09-24"))) == nil)
        #expect(PlanificateurAlertes.annonceFilm(dates: nil, dateMondiale: DateTMDB(annee: 2026, mois: 11, jour: 4),
                                                 aujourdhui: DateTMDB(maintenant))?.cle == "sortie@2026-11-04")
    }

    @Test func disponibleEnLocationUneSeuleFois() {
        let apple = Construire.fournisseur(2, "Apple TV", priorite: 1)
        let google = Construire.fournisseur(3, "Google Play", priorite: 2)
        let apres = Construire.offres(location: [google, apple], achat: [apple])
        let maintenant = Date.suisse("2026-09-17 09:00")
        #expect(PlanificateurAlertes.arriveesEnLocation(chute, titre: "Film", avant: [], apres: apres, maintenant: maintenant, reglages: reglages)
            .map(\.motif) == [.disponibleEnLocation(nom: "Apple TV")])
        #expect(PlanificateurAlertes.arriveesEnLocation(chute, titre: "Film", avant: [3], apres: apres, maintenant: maintenant, reglages: reglages).isEmpty)
    }

    @Test func diffusionTeleEtRappel() {
        let maintenant = Date.suisse("2026-09-17 09:00")
        let ceSoir = DiffusionPrevue(chaine: "M6", debut: Date.suisse("2026-09-17 21:10"), fin: Date.suisse("2026-09-17 22:55"))
        let apresMidi = DiffusionPrevue(chaine: "TF1", debut: Date.suisse("2026-09-18 14:25"), fin: Date.suisse("2026-09-18 16:00"))
        let dansDixJours = DiffusionPrevue(chaine: "M6", debut: Date.suisse("2026-09-27 21:10"), fin: Date.suisse("2026-09-27 22:55"))
        let alertes = PlanificateurAlertes.diffusions(chute, titre: "La Chute de Londres", diffusions: [ceSoir, apresMidi, dansDixJours],
                                                      maintenant: maintenant, reglages: reglages)
        #expect(alertes.map(\.date) == [Date.suisse("2026-09-17 18:00"), Date.suisse("2026-09-17 20:55"), Date.suisse("2026-09-18 14:10")])
    }

    @Test func regroupementEtDejaEnvoyees() {
        let date = Date.suisse("2026-09-17 18:00")
        let a = AlertePrevue(reference: chute, titre: "La Chute de Londres", motif: .arriveeSurPlateforme(nom: "Netflix"), date: date)
        let b = AlertePrevue(reference: ReferenceTitre(type: .serie, tmdbID: 108_978), titre: "Reacher",
                             motif: .nouvelEpisode(NumeroEpisode(saison: 3, episode: 4)), date: date)
        let groupees = PlanificateurAlertes.notifications([a, b, a], dejaEnvoyees: [], reglages: reglages)
        #expect(groupees.count == 1)
        #expect(groupees.first?.titre == "Séance : 2 nouveautés")
        #expect(groupees.first?.corps == "La Chute de Londres — Maintenant sur Netflix\nReacher — Nouvel épisode S03E04 disponible")

        let restantes = PlanificateurAlertes.notifications([a, b], dejaEnvoyees: [a.cle], reglages: reglages)
        #expect(restantes.map(\.titre) == ["Reacher"])
    }
}

@Suite("Statistiques")
struct StatistiquesTests {
    private let heat = ReferenceTitre(type: .film, tmdbID: 949)
    private let chute = ReferenceTitre(type: .film, tmdbID: 267_860)
    private let reacher = ReferenceTitre(type: .serie, tmdbID: 108_978)

    private var visionnages: [VisionnageStat] {
        [
            VisionnageStat(reference: heat, dureeMinutes: 170, vuLe: Date.suisse("2026-08-30 21:00"), genres: [28, 80], acteurs: ["Al Pacino", "Robert De Niro"]),
            VisionnageStat(reference: chute, dureeMinutes: 99, vuLe: Date.suisse("2026-09-02 21:00"), genres: [28, 53], acteurs: ["Gerard Butler", "Morgan Freeman"]),
            VisionnageStat(reference: reacher, dureeMinutes: 50, vuLe: Date.suisse("2026-09-05 20:00"), genres: [10759], acteurs: ["Alan Ritchson"]),
            VisionnageStat(reference: reacher, dureeMinutes: 48, vuLe: Date.suisse("2026-09-05 21:00"), genres: [10759], acteurs: ["Alan Ritchson"]),
            VisionnageStat(reference: reacher, dureeMinutes: 52, vuLe: Date.suisse("2026-09-05 22:00"), genres: [10759], acteurs: ["Alan Ritchson"]),
            VisionnageStat(reference: reacher, dureeMinutes: 49, vuLe: Date.suisse("2026-09-06 21:00"), genres: [10759], acteurs: ["Alan Ritchson"]),
        ]
    }

    @Test func totauxEtPeriodes() {
        let bilan = Statistiques.calculer(visionnages)
        #expect(bilan.minutesTotales == 468)
        #expect(bilan.minutesFilms == 269)
        #expect(bilan.minutesSeries == 199)
        #expect(bilan.nombreFilms == 2 && bilan.nombreEpisodes == 4)
        #expect(bilan.parMois == [Periode(annee: 2026, numero: 8): 170, Periode(annee: 2026, numero: 9): 298])
        // 30 août 2026 = semaine ISO 35 ; 2 septembre = 36 ; 5 et 6 septembre = 36.
        #expect(bilan.parSemaine == [Periode(annee: 2026, numero: 35): 170, Periode(annee: 2026, numero: 36): 298])
        #expect(bilan.recordEpisodes == RecordSoiree(jour: DateTMDB(annee: 2026, mois: 9, jour: 5), nombreEpisodes: 3))
    }

    @Test func classementsParTitresDifferents() {
        let bilan = Statistiques.calculer(visionnages, nombreActeurs: 2, nombreGenres: 2)
        // Une série vue en quatre épisodes compte pour un titre.
        #expect(bilan.acteurs.map(\.cle) == ["Al Pacino", "Alan Ritchson"])
        #expect(bilan.acteurs.map(\.nombreTitres) == [1, 1])
        #expect(bilan.genres.first == Classement(cle: 28, nombreTitres: 2))
    }

    @Test func surUnePeriode() {
        let septembre = Date.suisse("2026-09-01 00:00")...Date.suisse("2026-09-30 23:59")
        #expect(Statistiques.calculer(visionnages, entre: septembre).minutesTotales == 298)
    }
}
