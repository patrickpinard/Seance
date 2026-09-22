import Foundation
import Testing
@testable import SeanceKit

@Suite("Progression des séries")
struct ProgressionSerieTests {
    private let aujourdhui = DateTMDB(annee: 2026, mois: 9, jour: 17)
    private let episodes = [
        Construire.episode(0, 1, diffuse: "2026-01-01"),
        Construire.episode(1, 1, diffuse: "2026-09-01"),
        Construire.episode(1, 2, diffuse: "2026-09-08"),
        Construire.episode(1, 3, diffuse: "2026-09-15"),
        Construire.episode(1, 4, diffuse: "2026-09-22"),
    ]

    private func vus(_ numeros: [(Int, Int)]) -> Set<NumeroEpisode> {
        Set(numeros.map { NumeroEpisode(saison: $0.0, episode: $0.1) })
    }

    @Test func premierEpisodeSiRienVuEtSpeciauxIgnores() throws {
        let etat = ProgressionSerie.etat(episodes: episodes, vus: [], serie: try Construire.serie(), aujourdhui: aujourdhui)
        #expect(etat == .aSuivre(episodes[1]))
    }

    @Test func prochainEpisodeDiffuse() throws {
        let etat = ProgressionSerie.etat(episodes: episodes, vus: vus([(1, 1), (1, 2)]), serie: try Construire.serie(), aujourdhui: aujourdhui)
        #expect(etat == .aSuivre(episodes[3]))
    }

    @Test func enAttenteDuProchainEpisode() throws {
        let etat = ProgressionSerie.etat(episodes: episodes, vus: vus([(1, 1), (1, 2), (1, 3)]), serie: try Construire.serie(), aujourdhui: aujourdhui)
        #expect(etat == .enAttente(prochaineDiffusion: DateTMDB(annee: 2026, mois: 9, jour: 22)))
    }

    @Test func toutVu() throws {
        let tout = vus([(1, 1), (1, 2), (1, 3), (1, 4)])
        let saison2 = Construire.episode(2, 1, diffuse: "2027-03-01")
        #expect(ProgressionSerie.etat(episodes: episodes, vus: tout, serie: try Construire.serie(statut: "Ended"), aujourdhui: aujourdhui) == .terminee)
        #expect(ProgressionSerie.etat(episodes: episodes, vus: tout, serie: try Construire.serie(prochain: saison2), aujourdhui: aujourdhui)
            == .enAttente(prochaineDiffusion: DateTMDB(annee: 2027, mois: 3, jour: 1)))
        #expect(ProgressionSerie.etat(episodes: episodes, vus: tout, serie: try Construire.serie(), aujourdhui: aujourdhui)
            == .enAttente(prochaineDiffusion: nil))
    }

    @Test func cocherJusquIci() {
        let cible = NumeroEpisode(saison: 1, episode: 3)
        #expect(ProgressionSerie.episodes(jusqua: cible, parmi: episodes.reversed()).map(\.numeroEpisode.description) == ["S01E01", "S01E02", "S01E03"])
    }
}

@Suite("Prochain épisode sans charger les saisons")
struct ProchainEpisodeTests {
    private let saisons: [SaisonResume] = Construire.decoder([SaisonResume].self, [
        ["id": 0, "name": "Épisodes spéciaux", "season_number": 0, "episode_count": 3],
        ["id": 1, "name": "Saison 1", "season_number": 1, "episode_count": 8],
        ["id": 2, "name": "Saison 2", "season_number": 2, "episode_count": 8],
        ["id": 3, "name": "Saison 3", "season_number": 3, "episode_count": 0],
    ])
    private let dernierDiffuse = Construire.episode(2, 5, diffuse: "2026-09-10")

    @Test func premierEpisodeQuandRienVu() throws {
        let suivant = try #require(ProgressionSerie.suivant(vus: [], saisons: saisons, dernierDiffuse: dernierDiffuse))
        #expect(suivant.numero == NumeroEpisode(saison: 1, episode: 1) && suivant.disponible)
        #expect(ProgressionSerie.total(saisons) == 16)
    }

    @Test func passageALaSaisonSuivanteEtEpisodePasEncoreDiffuse() throws {
        let finSaison = try #require(ProgressionSerie.suivant(vus: [NumeroEpisode(saison: 1, episode: 8)], saisons: saisons, dernierDiffuse: dernierDiffuse))
        #expect(finSaison.numero == NumeroEpisode(saison: 2, episode: 1))
        let attente = try #require(ProgressionSerie.suivant(vus: [NumeroEpisode(saison: 2, episode: 5)], saisons: saisons, dernierDiffuse: dernierDiffuse))
        #expect(attente.numero == NumeroEpisode(saison: 2, episode: 6) && !attente.disponible)
    }

    @Test func toutVu() {
        #expect(ProgressionSerie.suivant(vus: [NumeroEpisode(saison: 2, episode: 8)], saisons: saisons, dernierDiffuse: dernierDiffuse) == nil)
    }
}

@Suite("Série terminée et Terminés par mois (6.1)")
struct SerieTermineeTests {
    private let fin = NumeroEpisode(saison: 8, episode: 6)

    @Test func finieEtDernierEpisodeVu() throws {
        #expect(ProgressionSerie.estTerminee(vus: [fin], serie: try Construire.serie(statut: "Ended")))
        #expect(ProgressionSerie.estTerminee(vus: [fin], serie: try Construire.serie(statut: "Canceled")))
    }

    @Test func tantQuElleContinueEllePasseEnAttente() throws {
        #expect(!ProgressionSerie.estTerminee(vus: [fin], serie: try Construire.serie(statut: "Returning Series")))
        let annonce = Construire.episode(9, 1, diffuse: "2027-04-01")
        #expect(!ProgressionSerie.estTerminee(vus: [fin], serie: try Construire.serie(statut: "Ended", prochain: annonce)))
    }

    @Test func pasAvantLeDernierEpisode() throws {
        let finie = try Construire.serie(statut: "Ended")
        #expect(!ProgressionSerie.estTerminee(vus: [], serie: finie))
        #expect(!ProgressionSerie.estTerminee(vus: [NumeroEpisode(saison: 8, episode: 5)], serie: finie))
        #expect(ProgressionSerie.estFinie(finie))
    }

    @Test func rangesParMoisDuPlusRecent() {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = .suisse
        let titres: [(String, Date?)] = [
            ("Heat", .suisse("2026-08-30 22:00")), ("Reacher", .suisse("2026-09-20 21:00")), ("Ancien", nil),
            ("Drive", .suisse("2026-09-02 20:30")), ("Collateral", .suisse("2025-12-24 20:00")),
        ]
        let groupes = TerminesParMois.grouper(titres, fini: \.1, calendrier: calendrier)
        #expect(groupes.map(\.titre) == ["Septembre 2026", "Août 2026", "Décembre 2025", "Plus tôt"])
        #expect(groupes[0].elements.map(\.0) == ["Reacher", "Drive"])
        #expect(groupes.last?.mois == nil && groupes.last?.elements.map(\.0) == ["Ancien"])
        #expect(TerminesParMois.grouper([String](), fini: { _ in nil }).isEmpty)
    }
}

@Suite("Langue et disponibilité")
struct DisponibiliteTests {
    private let maintenant = Date.suisse("2026-09-17 19:00")
    private let netflix = Construire.fournisseur(8, "Netflix", priorite: 2)
    private let prime = Construire.fournisseur(119, "Amazon Prime Video", priorite: 1)
    private let playSuisse = Construire.fournisseur(691, "Play Suisse", priorite: 5)
    private let appleTV = Construire.fournisseur(2, "Apple TV", priorite: 3)
    private let googlePlay = Construire.fournisseur(3, "Google Play Movies", priorite: 4)

    @Test func regleDeLangue() {
        #expect(RegleLangue.accepte(langueOriginale: "fr", exclu: false))
        #expect(RegleLangue.accepte(langueOriginale: "EN", exclu: false))
        #expect(!RegleLangue.accepte(langueOriginale: "ko", exclu: false))
        #expect(!RegleLangue.accepte(langueOriginale: nil, exclu: false))
        #expect(RegleLangue.accepte(langueOriginale: "ko", exclu: false, diffuseSurChaineFrancophone: true))
        #expect(!RegleLangue.accepte(langueOriginale: "fr", exclu: true, diffuseSurChaineFrancophone: true))
    }

    @Test func leNASPasseDevantEtGardeLaMeilleureQualite() {
        let sources = SourcesTitre(
            nas: [CopieNAS(chemin: "a.mkv", qualite: .hd1080), CopieNAS(chemin: "b.mkv", qualite: .uhd4K)],
            offres: Construire.offres(abonnement: [netflix]), abonnements: [8]
        )
        #expect(Disponibilite.etat(sources, maintenant: maintenant) == .surNAS(qualite: .uhd4K))
    }

    @Test func abonnementsCochesEtOffresGratuites() {
        let sources = SourcesTitre(offres: Construire.offres(abonnement: [netflix, prime], gratuit: [playSuisse]), abonnements: [8])
        #expect(Disponibilite.etat(sources, maintenant: maintenant) == .dansAbonnements([netflix, playSuisse]))
        let sansAbonnement = SourcesTitre(offres: Construire.offres(abonnement: [prime], location: [appleTV]), abonnements: [8])
        #expect(Disponibilite.etat(sansAbonnement, maintenant: maintenant) == .aLouerOuAcheter(location: [appleTV], achat: []))
    }

    @Test func teleAVenirPuisLocationPuisIntrouvable() {
        let finie = DiffusionPrevue(chaine: "M6.fr", debut: Date.suisse("2026-09-17 14:00"), fin: Date.suisse("2026-09-17 15:45"))
        let ceSoir = DiffusionPrevue(chaine: "TF1.fr", debut: Date.suisse("2026-09-17 21:10"), fin: Date.suisse("2026-09-17 22:55"))
        let sources = SourcesTitre(offres: Construire.offres(location: [appleTV]), diffusions: [ceSoir, finie])
        #expect(Disponibilite.etat(sources, maintenant: maintenant) == .aLaTeleBientot(ceSoir))
        #expect(Disponibilite.etat(SourcesTitre(diffusions: [finie]), maintenant: maintenant) == .introuvable)
    }

    @Test func sourcesLegalesTriees() {
        let jeudi = DiffusionPrevue(chaine: "TF1.fr", debut: Date.suisse("2026-09-18 21:10"), fin: Date.suisse("2026-09-18 22:55"))
        let ceSoir = DiffusionPrevue(chaine: "M6.fr", debut: Date.suisse("2026-09-17 21:10"), fin: Date.suisse("2026-09-17 22:55"))
        let sources = SourcesTitre(offres: Construire.offres(location: [googlePlay, appleTV], achat: [appleTV]), diffusions: [jeudi, ceSoir])
        #expect(Disponibilite.sourcesAObtenir(sources, maintenant: maintenant) == [
            .tele(ceSoir), .tele(jeudi), .location(appleTV), .location(googlePlay), .achat(appleTV),
        ])
    }

    @Test(arguments: [
        (CritereObtention.surNAS, [true, false, false, false, false]),
        (.pasSurNAS, [false, true, true, true, true]),
        (.nasOuAbonnements, [true, true, false, false, false]),
        (.aObtenir, [false, false, true, true, true]),
        (.tous, [true, true, true, true, true]),
    ])
    func critereOuLObtenir(critere: CritereObtention, attendus: [Bool]) {
        let diffusion = DiffusionPrevue(chaine: "M6.fr", debut: .now, fin: .now)
        let etats: [EtatDisponibilite] = [
            .surNAS(qualite: nil), .dansAbonnements([]), .aLaTeleBientot(diffusion), .aLouerOuAcheter(location: [], achat: []), .introuvable,
        ]
        #expect(etats.map(critere.retient) == attendus)
    }
}

@Suite("Lecture depuis le NAS")
struct LectureExterneTests {
    @Test func demanderApresDixMinutesOublierApresDouzeHeures() {
        let debut = Date.suisse("2026-09-17 20:00")
        let lecture = LectureExterne(reference: ReferenceTitre(type: .serie, tmdbID: 108_978), titre: "Reacher",
                                     episode: NumeroEpisode(saison: 1, episode: 3), debut: debut)
        #expect(lecture.decision(maintenant: debut.addingTimeInterval(120)) == .attendre)
        #expect(lecture.decision(maintenant: debut.addingTimeInterval(50 * 60)) == .demander)
        #expect(lecture.decision(maintenant: debut.addingTimeInterval(13 * 3600)) == .oublier)
        #expect(lecture.libelle == "Reacher S01E03")
    }
}
