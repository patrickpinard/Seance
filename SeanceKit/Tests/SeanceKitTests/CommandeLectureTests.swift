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
}
