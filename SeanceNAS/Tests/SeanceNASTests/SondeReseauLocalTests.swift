import Foundation
import Testing
@testable import SeanceNAS

@Suite("Sonde du réseau local")
struct SondeReseauLocalTests {
    @Test func portFermeInjoignable() async {
        // Port local fermé : la connexion échoue vite, sans rien joindre à l'extérieur.
        let resultat = await SondeReseauLocal.tester(hote: "127.0.0.1", port: 9, delai: 3)
        #expect(resultat != .joignable)
    }

    @Test func erreursLibsmb2TraduitesDepuisLeTexte() {
        let routeAbsente = POSIXError(.EIO, userInfo: [NSLocalizedDescriptionKey: "Error code 5: Connect failed: No route to host"])
        #expect(ErreurNAS.message(routeAbsente).contains("Réseau local"))
        let refus = POSIXError(.ECANCELED, userInfo: [NSLocalizedDescriptionKey: "Error 0xC000006D: STATUS_LOGON_FAILURE"])
        #expect(ErreurNAS.message(refus) == "Le NAS refuse l'utilisateur ou le mot de passe.")
    }

    @Test func dossierRetrouveMalgreLaFormeDeLAccent() {
        let depuisLeMac = "Se\u{0301}ries"   // « e » + accent combinant, tel que macOS l'écrit
        // Swift juge les deux écritures égales, le NAS non : on compare les caractères Unicode.
        #expect(depuisLeMac.unicodeScalars.count != "Séries".unicodeScalars.count)
        let retrouve = ExplorateurSMB.correspondance("Séries", parmi: ["Films", "NEW", depuisLeMac])
        #expect(retrouve.map { Array($0.unicodeScalars) } == Array(depuisLeMac.unicodeScalars))
        #expect(ExplorateurSMB.correspondance("séries/", parmi: ["Films", depuisLeMac]) != nil)
        #expect(ExplorateurSMB.correspondance("Series", parmi: ["Films", depuisLeMac]) == nil)
        let erreur = ErreurNAS.dossierAbsent("Series", presents: ["Films", "NEW", "Séries"])
        #expect(erreur.errorDescription?.contains("Dossiers présents : Films, NEW, Séries") == true)
    }

    @Test func dossiersTechniquesDuSynologyEcartes() {
        #expect(!ExplorateurSMB.retenu("@eaDir"))
        #expect(!ExplorateurSMB.retenu("#recycle"))
        #expect(!ExplorateurSMB.retenu(".DS_Store"))
        #expect(ExplorateurSMB.retenu("Saison 01"))
        #expect(ExplorateurSMB.retenu("Mr. Robot"))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SEANCE_SONDE_NAS"] != nil))
    func sondeDuNASDeLaMaison() async throws {
        let resultat = await SondeReseauLocal.tester(hote: "192.168.1.220", delai: 5)
        print("Sonde NAS : \(resultat)")
        // Sur le Mac, le processus de test n'a pas l'autorisation « Réseau local » : la sonde doit le dire.
        #expect(resultat == .joignable || resultat == .autorisationRefusee)
    }
}
