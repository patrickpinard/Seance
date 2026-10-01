import AMSMB2
import Foundation

/// Les connexions SMB qui ont connu une erreur (8.8, plantages de l'iPhone et du Mac du 28.09 au 01.10.2026).
///
/// Quand une opération dépasse son délai, AMSMB2 abandonne l'attente mais laisse la commande en cours dans libsmb2, avec
/// l'adresse d'une variable qui n'existe plus. Dès que la connexion resservait — une autre lecture, sa fermeture, ou sa
/// simple libération, qui la ferme —, libsmb2 rappelait cette commande et Séance plantait (`read_cb`, `open_cb`). Une
/// connexion en erreur n'est donc plus jamais touchée : ni réutilisée, ni fermée, ni libérée. Elle reste ici jusqu'à la
/// fin de l'app ; le NAS finit par couper la socket de son côté. La suivante repart d'une connexion neuve.
public enum QuarantaineSMB {
    private static let verrou = NSLock()
    nonisolated(unsafe) private static var gardees: [SMB2Manager] = []

    static func garder(_ connexion: SMB2Manager) {
        verrou.lock()
        defer { verrou.unlock() }
        guard !gardees.contains(where: { $0 === connexion }) else { return }
        gardees.append(connexion)
    }

    /// Combien de connexions sont tenues à l'écart, pour le journal.
    public static var nombre: Int {
        verrou.lock()
        defer { verrou.unlock() }
        return gardees.count
    }
}
