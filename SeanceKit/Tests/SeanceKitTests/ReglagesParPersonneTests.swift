import Foundation
import Testing
@testable import SeanceKit

/// 8.2.17 : chacun ses alertes et son e-mail de la semaine, sous une clé par personne de la famille.
@Suite struct ReglagesParPersonneTests {
    @Test func lesClesDuProfilPrincipalRestentCellesDAvant() {
        #expect(ReglagesAlertes.cle(profil: "") == "alertes.reglages")
        #expect(ReglagesLettre.cle(profil: "") == "lettre.reglages")
        #expect(ReglagesAlertes.cle(profil: "anne") == "alertes.reglages.anne")
        #expect(ReglagesLettre.cle(profil: "anne") == "lettre.reglages.anne")
    }

    @Test func chacunLitLesSiens() throws {
        let defauts = try #require(UserDefaults(suiteName: "tests.reglagesParPersonne"))
        defauts.removePersistentDomain(forName: "tests.reglagesParPersonne")
        var anne = ReglagesLettre()
        anne.actif = true
        anne.destinataires = "anne@exemple.ch"
        anne.rubriques = [.passagesTele]
        anne.chaines = ["RTS 1"]
        defauts.set(try JSONEncoder().encode(anne), forKey: ReglagesLettre.cle(profil: "anne"))
        #expect(ReglagesLettre.lire(defauts, profil: "anne") == anne)
        #expect(ReglagesLettre.lire(defauts, profil: "") == nil)
        #expect(ReglagesLettre.lire(defauts, profil: "anne")?.veut(.sorties) == false)
    }

    /// Les réglages enregistrés avant qu'ils passent dans SeanceKit se relisent tels quels.
    @Test func lAncienFormatSeRelit() throws {
        let ancien = #"{"actif":true,"destinataires":"a@b.ch","compte":{"serveur":"s","port":465,"utilisateur":"u","adresse":"a@b.ch"},"jour":6,"heure":17}"#
        let lu = try JSONDecoder().decode(ReglagesLettre.self, from: Data(ancien.utf8))
        #expect(lu.actif && lu.joursRetenus == [6] && lu.veut(.soirees))
    }
}

@Suite struct RecentsDAbordTests {
    @Test func lesPlusRecentsDAbordSansDateALaFin() {
        let titres: [(String, DateTMDB?)] = [("a", DateTMDB(annee: 2024, mois: 5, jour: 1)), ("b", nil), ("c", DateTMDB(annee: 2026, mois: 1, jour: 2)),
                                              ("d", DateTMDB(annee: 2025, mois: 3, jour: 1)), ("e", DateTMDB(annee: 2026, mois: 1, jour: 2))]
        #expect(titres.recentsDAbord(\.1).map(\.0) == ["c", "e", "d", "a", "b"])
    }
}
