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
