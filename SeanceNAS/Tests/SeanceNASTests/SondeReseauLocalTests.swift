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

    @Test func sondeDuNASDeLaMaison() async throws {
        try #require(ProcessInfo.processInfo.environment["SEANCE_SONDE_NAS"] != nil)
        let resultat = await SondeReseauLocal.tester(hote: "192.168.1.220", delai: 5)
        print("Sonde NAS : \(resultat)")
        // Sur le Mac, le processus de test n'a pas l'autorisation « Réseau local » : la sonde doit le dire.
        #expect(resultat == .joignable || resultat == .autorisationRefusee)
    }
}
