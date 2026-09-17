import Foundation
import Testing
@testable import SeanceKit

@Suite("Expérience 2.0 : sorties, Explorer, installation")
struct ExperienceTests {
    private let aujourdhui = DateTMDB(annee: 2026, mois: 9, jour: 17)

    @Test func etatDeSortieDUnFilmAbsentDesPlateformes() {
        // En salle depuis le 3 septembre, streaming annoncé pour décembre.
        let enSalle = Construire.datesDeSortie(ch: [(3, "2026-09-03T00:00:00.000Z"), (4, "2026-12-15T00:00:00.000Z")])
        #expect(EtatSortie.etat(dates: enSalle, dateMondiale: nil, aujourdhui: aujourdhui)
            == .auCinema(depuis: DateTMDB(annee: 2026, mois: 9, jour: 3), numerique: DateTMDB(annee: 2026, mois: 12, jour: 15)))

        let bientot = Construire.datesDeSortie(ch: [(3, "2026-10-08T00:00:00.000Z")])
        #expect(EtatSortie.etat(dates: bientot, dateMondiale: nil, aujourdhui: aujourdhui) == .bientotAuCinema(le: DateTMDB(annee: 2026, mois: 10, jour: 8)))

        // Sorti en salle il y a longtemps, streaming daté plus tard : on annonce le streaming.
        let vieuxEnSalle = Construire.datesDeSortie(ch: [(3, "2026-01-10T00:00:00.000Z"), (4, "2026-10-01T00:00:00.000Z")])
        #expect(EtatSortie.etat(dates: vieuxEnSalle, dateMondiale: nil, aujourdhui: aujourdhui) == .sortieNumerique(le: DateTMDB(annee: 2026, mois: 10, jour: 1)))

        // Sans dates suisses : la sortie mondiale décide.
        #expect(EtatSortie.etat(dates: nil, dateMondiale: DateTMDB(annee: 2027, mois: 3, jour: 1), aujourdhui: aujourdhui) == .aVenir(le: DateTMDB(annee: 2027, mois: 3, jour: 1)))
        #expect(EtatSortie.etat(dates: nil, dateMondiale: DateTMDB(annee: 2026, mois: 5, jour: 1), aujourdhui: aujourdhui) == .pasEncoreEnStreaming)
        // Un vieux film reste introuvable.
        #expect(EtatSortie.etat(dates: nil, dateMondiale: DateTMDB(annee: 1995, mois: 12, jour: 15), aujourdhui: aujourdhui) == nil)
    }

    @Test func explorerAOuverture() {
        let filtres = FiltresExplorer.parDefaut(avecPlateformes: true)
        #expect(filtres.langue == "fr|en" && filtres.mesPlateformes)
        #expect(filtres.criteresActifs == [.langue, .plateformes])
        #expect(filtres.criteres(abonnements: [8]).parametres(pour: .film).contains(URLQueryItem(name: "with_original_language", value: "fr|en")))
        #expect(!FiltresExplorer.parDefaut(avecPlateformes: false).mesPlateformes)
    }

    @Test func expirationDuProfilDInstallation() throws {
        let expiration = Date(timeIntervalSince1970: 1_789_560_000)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["ExpirationDate": expiration, "Name": "iOS Team Provisioning Profile"],
                                                       format: .xml, options: 0)
        // Le plist est entouré de la signature CMS : des octets quelconques avant et après.
        let donnees = Data([0x30, 0x82, 0x01, 0xFF]) + plist + Data([0xA0, 0x00, 0x31])
        #expect(ProfilInstallation.dateExpiration(donnees) == expiration)
        #expect(ProfilInstallation.dateExpiration(Data("pas un profil".utf8)) == nil)

        let maintenant = Date.suisse("2026-09-17 10:00")
        #expect(ProfilInstallation.libelle(expiration: Date.suisse("2026-09-22 09:00"), maintenant: maintenant) == "encore 5 jours")
        #expect(ProfilInstallation.libelle(expiration: Date.suisse("2026-09-18 09:00"), maintenant: maintenant) == "expire demain")
        #expect(ProfilInstallation.libelle(expiration: Date.suisse("2026-09-17 20:00"), maintenant: maintenant) == "expire aujourd'hui")
        #expect(ProfilInstallation.libelle(expiration: Date.suisse("2026-09-16 20:00"), maintenant: maintenant) == "expirée")
    }
}
