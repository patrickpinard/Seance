import Foundation
import Testing
@testable import SeanceKit

@Suite("Lire sur l'Apple TV")
struct CommandeLectureTests {
    let commande = CommandeLecture(chemin: "Films/Heat.1995.mkv", depart: 3792, expediteur: "iPhone de Patrick",
                                   emiseLe: Date(timeIntervalSince1970: 1_800_000_000))

    @Test func laDemandeSigneeSeRelit() throws {
        let message = try commande.sceller(secret: "motdepasse")
        let relue = try CommandeLecture.ouvrir(message, secret: "motdepasse", maintenant: commande.emiseLe.addingTimeInterval(5))
        #expect(relue == commande)
    }

    @Test func unAutreSecretEstRefuse() throws {
        let message = try commande.sceller(secret: "motdepasse")
        #expect(throws: CommandeLecture.Erreur.signature) {
            try CommandeLecture.ouvrir(message, secret: "autre", maintenant: commande.emiseLe)
        }
    }

    @Test func uneDemandeModifieeEstRefusee() throws {
        var message = try commande.sceller(secret: "motdepasse")
        message[10] ^= 0xFF
        #expect(throws: CommandeLecture.Erreur.signature) {
            try CommandeLecture.ouvrir(message, secret: "motdepasse", maintenant: commande.emiseLe)
        }
    }

    @Test func uneDemandeAncienneEstRefusee() throws {
        let message = try commande.sceller(secret: "motdepasse")
        #expect(throws: CommandeLecture.Erreur.perimee) {
            try CommandeLecture.ouvrir(message, secret: "motdepasse", maintenant: commande.emiseLe.addingTimeInterval(120))
        }
    }

    /// 8.11 (audit de sécurité) : une demande captée et rejouée dans la minute est refusée.
    @Test func uneDemandeRejoueeEstRefusee() {
        let memoire = MemoireJetons()
        #expect(memoire.accepter(commande.jeton, maintenant: commande.emiseLe))
        #expect(!memoire.accepter(commande.jeton, maintenant: commande.emiseLe.addingTimeInterval(10)))
        #expect(memoire.accepter(UUID().uuidString, maintenant: commande.emiseLe.addingTimeInterval(10)))
    }

    @Test func chaqueDemandeASonJeton() {
        let autre = CommandeLecture(chemin: commande.chemin, depart: commande.depart, expediteur: commande.expediteur, emiseLe: commande.emiseLe)
        #expect(autre.jeton != commande.jeton)
    }
}
