import Foundation
import Network

/// Vérifie qu'on joint le port SMB du NAS avant d'ouvrir libsmb2.
///
/// Sur iPhone, l'accès au réseau local demande une autorisation (« Réseau local »). Les sockets BSD de
/// libsmb2 échouent alors sans explication (« no route to host »). Une connexion Network.framework,
/// elle, déclenche la demande d'iOS, attend la réponse, et sait dire si l'accès est refusé.
public enum SondeReseauLocal {
    public enum Resultat: Sendable, Equatable {
        case joignable
        case autorisationRefusee
        case injoignable(String)
    }

    /// Le délai laisse le temps de répondre à l'alerte d'iOS lors du premier essai.
    public static func tester(hote: String, port: UInt16 = 445, delai: TimeInterval = 20) async -> Resultat {
        guard let portNW = NWEndpoint.Port(rawValue: port) else { return .injoignable("Port invalide") }
        let connexion = NWConnection(host: NWEndpoint.Host(hote), port: portNW, using: .tcp)
        let file = DispatchQueue(label: "ch.patrick.seance.sonde-nas")
        let issue = IssueUnique()

        let resultat = await withCheckedContinuation { (suite: CheckedContinuation<Resultat, Never>) in
            issue.attendre(suite)
            connexion.stateUpdateHandler = { etat in
                switch etat {
                case .ready:
                    issue.donner(.joignable)
                case .waiting(let erreur):
                    // En attente : soit l'alerte d'iOS est affichée, soit l'accès est refusé.
                    // On laisse à Patrick le temps de répondre ; seul le délai tranche.
                    if connexion.currentPath?.unsatisfiedReason == .localNetworkDenied {
                        issue.retenir(.autorisationRefusee)
                    } else {
                        issue.retenir(.injoignable(erreur.localizedDescription))
                    }
                case .failed(let erreur):
                    issue.donner(connexion.currentPath?.unsatisfiedReason == .localNetworkDenied
                                 ? .autorisationRefusee : .injoignable(erreur.localizedDescription))
                default:
                    break
                }
            }
            connexion.start(queue: file)
            file.asyncAfter(deadline: .now() + delai) {
                issue.donner(issue.retenu ?? .injoignable("Pas de réponse du NAS"))
            }
        }
        connexion.stateUpdateHandler = nil
        connexion.cancel()
        return resultat
    }
}

/// Ne reprend la suite qu'une fois, quel que soit le premier événement arrivé.
private final class IssueUnique: @unchecked Sendable {
    private let verrou = NSLock()
    private var suite: CheckedContinuation<SondeReseauLocal.Resultat, Never>?
    private var dernier: SondeReseauLocal.Resultat?

    var retenu: SondeReseauLocal.Resultat? {
        verrou.withLock { dernier }
    }

    func attendre(_ suite: CheckedContinuation<SondeReseauLocal.Resultat, Never>) {
        verrou.withLock { self.suite = suite }
    }

    func retenir(_ resultat: SondeReseauLocal.Resultat) {
        verrou.withLock { dernier = resultat }
    }

    func donner(_ resultat: SondeReseauLocal.Resultat) {
        let aReprendre = verrou.withLock { () -> CheckedContinuation<SondeReseauLocal.Resultat, Never>? in
            defer { suite = nil }
            return suite
        }
        aReprendre?.resume(returning: resultat)
    }
}
