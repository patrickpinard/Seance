import CryptoKit
import Foundation
import Testing
@testable import SeanceKit

@Suite("Transfert de configuration vers l'Apple TV")
struct TransfertConfigTests {
    private let configuration = ConfigurationTransferee(
        expediteur: "iPhone de test", cleTMDB: "0123456789abcdef0123456789abcdef", nas: ReglagesNAS(),
        motDePasseNAS: "mot de passe très secret", sauvegarde: Data("{\"version\":1}".utf8)
    )

    @Test func allerRetourAvecLeBonCode() throws {
        let tv = Curve25519.KeyAgreement.PrivateKey()
        let message = try TransfertConfig.sceller(configuration, pour: tv.publicKey.rawRepresentation, code: "278445")
        #expect(try TransfertConfig.ouvrir(message, avec: tv, code: "278445") == configuration)
    }

    @Test func unAutreCodeNOuvreRien() throws {
        let tv = Curve25519.KeyAgreement.PrivateKey()
        let message = try TransfertConfig.sceller(configuration, pour: tv.publicKey.rawRepresentation, code: "278445")
        #expect(throws: TransfertConfig.Erreur.codeIncorrect) { try TransfertConfig.ouvrir(message, avec: tv, code: "278446") }
    }

    @Test func uneAutreTVNOuvreRien() throws {
        let tv = Curve25519.KeyAgreement.PrivateKey()
        let message = try TransfertConfig.sceller(configuration, pour: tv.publicKey.rawRepresentation, code: "278445")
        #expect(throws: TransfertConfig.Erreur.codeIncorrect) {
            try TransfertConfig.ouvrir(message, avec: Curve25519.KeyAgreement.PrivateKey(), code: "278445")
        }
    }

    /// Ni la clé ni le mot de passe ne se lisent dans ce qui passe sur le réseau.
    @Test func rienNePasseEnClair() throws {
        let tv = Curve25519.KeyAgreement.PrivateKey()
        let message = try TransfertConfig.sceller(configuration, pour: tv.publicKey.rawRepresentation, code: "278445")
        #expect(message.range(of: Data("0123456789abcdef".utf8)) == nil)
        #expect(message.range(of: Data("secret".utf8)) == nil)
    }

    @Test func messageTronqueOuAbsurde() {
        let tv = Curve25519.KeyAgreement.PrivateKey()
        #expect(throws: TransfertConfig.Erreur.messageIllisible) { try TransfertConfig.ouvrir(Data([1, 2, 3]), avec: tv, code: "000000") }
        #expect(throws: TransfertConfig.Erreur.messageIllisible) { try TransfertConfig.ouvrir(Data(repeating: 7, count: 40), avec: tv, code: "000000") }
    }

    @Test func codesEtTrames() {
        let code = TransfertConfig.nouveauCode()
        #expect(code.count == 6 && code.allSatisfy(\.isNumber))
        let trame = TransfertConfig.trame(Data(repeating: 9, count: 300))
        #expect(trame.count == 304)
        #expect(TransfertConfig.longueur(trame.prefix(4)) == 300)
        #expect(TransfertConfig.longueur(Data([0, 0, 0, 0])) == nil)
        #expect(TransfertConfig.longueur(Data([255, 255, 255, 255])) == nil)
    }
}

/// Le vrai réseau, sur cette machine : une « TV » s'annonce par Bonjour, un « iPhone » la trouve et lui envoie tout.
@Suite("Transfert de configuration, par le réseau", .serialized)
struct ReseauTransfertTests {
    private let configuration = ConfigurationTransferee(expediteur: "iPhone de test", cleTMDB: "cle", motDePasseNAS: "secret",
                                                        sauvegarde: Data(repeating: 65, count: 400_000))

    private func televiseur(_ nom: String) async -> EmetteurConfig.Televiseur? {
        for await trouves in EmetteurConfig.chercher() {
            if let tv = trouves.first(where: { $0.nom == nom }) { return tv }
        }
        return nil
    }

    @Test(.timeLimit(.minutes(1))) func bonCodePuisReception() async throws {
        let nom = "Test Séance \(UUID().uuidString.prefix(6))"
        let recepteur = RecepteurConfig()
        let evenements = recepteur.demarrer(nom: nom)
        let tv = try #require(await televiseur(nom))
        async let envoi: Void = EmetteurConfig.envoyer(configuration, a: tv, code: recepteur.code)
        var recue: ConfigurationTransferee?
        for await evenement in evenements {
            if case .recue(let configuration) = evenement { recue = configuration; break }
        }
        try await envoi
        #expect(recue == configuration)
        recepteur.arreter()
    }

    @Test(.timeLimit(.minutes(1))) func mauvaisCodeRefuse() async throws {
        let nom = "Test Séance \(UUID().uuidString.prefix(6))"
        let recepteur = RecepteurConfig()
        // Le flux doit rester en vie : l'abandonner arrête le récepteur.
        let evenements = recepteur.demarrer(nom: nom)
        let tv = try #require(await televiseur(nom))
        let faux = recepteur.code == "000000" ? "111111" : "000000"
        await #expect(throws: EmetteurConfig.Erreur.codeIncorrect) {
            try await EmetteurConfig.envoyer(configuration, a: tv, code: faux)
        }
        var refuse = false
        for await evenement in evenements {
            if case .codeRefuse = evenement { refuse = true; break }
        }
        #expect(refuse, "La TV doit dire qu'un code incorrect a été essayé")
        recepteur.arreter()
    }
}
