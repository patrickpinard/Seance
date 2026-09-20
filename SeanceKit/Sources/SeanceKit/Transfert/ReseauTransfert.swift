import CryptoKit
import Foundation
import Network
import OSLog

private let journal = Logger(subsystem: "ch.patrick.seance", category: "transfert")

/// Une seule reprise pour une continuation, quel que soit le nombre de rappels du réseau.
private final class UneFois: @unchecked Sendable {
    private let verrou = NSLock()
    private var fait = false
    func tenter(_ action: () -> Void) {
        verrou.lock()
        let premier = !fait
        fait = true
        verrou.unlock()
        if premier { action() }
    }
}

private extension NWConnection {
    /// Lit une trame entière : sa longueur, puis son contenu.
    func lireTrame(_ suite: @escaping @Sendable (Data?) -> Void) {
        receive(minimumIncompleteLength: 4, maximumLength: 4) { entete, _, _, _ in
            guard let entete, let longueur = TransfertConfig.longueur(entete) else { return suite(nil) }
            self.receive(minimumIncompleteLength: longueur, maximumLength: longueur) { contenu, _, _, _ in
                suite(contenu?.count == longueur ? contenu : nil)
            }
        }
    }

    func envoyerTrame(_ contenu: Data, _ suite: @escaping @Sendable (Bool) -> Void) {
        send(content: TransfertConfig.trame(contenu), completion: .contentProcessed { suite($0 == nil) })
    }
}

/// Côté Apple TV : s'annonce sur le réseau de la maison et attend la configuration d'un iPhone.
public final class RecepteurConfig: @unchecked Sendable {
    public enum Evenement: Sendable {
        case pret
        case recue(ConfigurationTransferee)
        /// Un iPhone a envoyé un message, mais avec un autre code que celui affiché.
        case codeRefuse
        case erreur(String)
    }

    public let code: String
    private let clePrivee = Curve25519.KeyAgreement.PrivateKey()
    private let file = DispatchQueue(label: "ch.patrick.seance.transfert.reception")
    private var ecouteur: NWListener?
    private var refus = 0

    /// `code` : imposé par les tests ; sinon tiré au hasard, et jamais réutilisé.
    public init(code: String = TransfertConfig.nouveauCode()) {
        self.code = code
    }

    public func demarrer(nom: String) -> AsyncStream<Evenement> {
        AsyncStream { flux in
            do {
                let ecouteur = try NWListener(using: .tcp)
                ecouteur.service = NWListener.Service(name: nom, type: TransfertConfig.service)
                ecouteur.stateUpdateHandler = { etat in
                    switch etat {
                    case .ready: flux.yield(.pret)
                    case .failed(let erreur): flux.yield(.erreur(erreur.localizedDescription)); flux.finish()
                    case .cancelled: flux.finish()
                    default: break
                    }
                }
                ecouteur.newConnectionHandler = { [weak self] connexion in self?.accueillir(connexion, flux) }
                self.ecouteur = ecouteur
                ecouteur.start(queue: file)
            } catch {
                flux.yield(.erreur(error.localizedDescription))
                flux.finish()
            }
            flux.onTermination = { [weak self] _ in self?.arreter() }
        }
    }

    public func arreter() {
        file.async { [weak self] in
            self?.ecouteur?.cancel()
            self?.ecouteur = nil
        }
    }

    /// La TV envoie sa clé publique, reçoit le message scellé, et répond 1 (reçu) ou 0 (code incorrect).
    private func accueillir(_ connexion: NWConnection, _ flux: AsyncStream<Evenement>.Continuation) {
        journal.info("Connexion reçue sur la TV")
        connexion.start(queue: file)
        connexion.envoyerTrame(clePrivee.publicKey.rawRepresentation) { [weak self] envoye in
            guard let self, envoye else { return connexion.cancel() }
            connexion.lireTrame { message in
                guard let message else { return connexion.cancel() }
                do {
                    let configuration = try TransfertConfig.ouvrir(message, avec: self.clePrivee, code: self.code)
                    connexion.envoyerTrame(Data([1])) { _ in connexion.cancel() }
                    flux.yield(.recue(configuration))
                } catch {
                    connexion.envoyerTrame(Data([0])) { _ in connexion.cancel() }
                    flux.yield(.codeRefuse)
                    // Cinq essais, pas un million : au-delà, la TV cesse d'écouter et il faut redemander un code.
                    self.refus += 1
                    if self.refus >= 5 {
                        flux.yield(.erreur("Trop de codes incorrects. Relance la configuration pour obtenir un nouveau code."))
                        self.ecouteur?.cancel()
                    }
                }
            }
        }
    }
}

/// Côté iPhone : trouve les Apple TV qui attendent une configuration, et la leur envoie.
public enum EmetteurConfig {
    public struct Televiseur: Sendable, Hashable, Identifiable {
        public let nom: String
        let destination: NWEndpoint
        public var id: String { nom }
    }

    public enum Erreur: Error, Equatable {
        case codeIncorrect
        case injoignable
    }

    /// Les TV qui s'annoncent, tant que le flux est écouté.
    public static func chercher() -> AsyncStream<[Televiseur]> {
        AsyncStream { flux in
            let explorateur = NWBrowser(for: .bonjour(type: TransfertConfig.service, domain: nil), using: .tcp)
            explorateur.browseResultsChangedHandler = { resultats, _ in
                let televiseurs = resultats.compactMap { resultat -> Televiseur? in
                    guard case .service(let nom, _, _, _) = resultat.endpoint else { return nil }
                    return Televiseur(nom: nom, destination: resultat.endpoint)
                }
                flux.yield(televiseurs.sorted { $0.nom < $1.nom })
            }
            explorateur.start(queue: DispatchQueue(label: "ch.patrick.seance.transfert.recherche"))
            flux.onTermination = { _ in explorateur.cancel() }
        }
    }

    public static func envoyer(_ configuration: ConfigurationTransferee, a televiseur: Televiseur, code: String) async throws {
        let connexion = NWConnection(to: televiseur.destination, using: .tcp)
        let uneFois = UneFois()
        defer { connexion.cancel() }
        try await withCheckedThrowingContinuation { (suite: CheckedContinuation<Void, any Error>) in
            @Sendable func finir(_ resultat: Result<Void, any Error>) { uneFois.tenter { suite.resume(with: resultat) } }
            let file = DispatchQueue(label: "ch.patrick.seance.transfert.envoi")
            connexion.stateUpdateHandler = { etat in
                journal.info("Envoi vers la TV : \(String(describing: etat), privacy: .public)")
                switch etat {
                case .failed, .cancelled: finir(.failure(Erreur.injoignable))
                default: break   // « waiting » : le réseau peut encore arriver ; le délai de garde tranche.
                }
            }
            // Une liaison qui ne s'établit pas ne doit pas laisser l'écran sur « Envoi… » pour toujours.
            file.asyncAfter(deadline: .now() + 20) { finir(.failure(Erreur.injoignable)) }
            connexion.start(queue: file)
            connexion.lireTrame { clePublique in
                guard let clePublique, let message = try? TransfertConfig.sceller(configuration, pour: clePublique, code: code) else {
                    return finir(.failure(Erreur.injoignable))
                }
                connexion.envoyerTrame(message) { envoye in
                    guard envoye else { return finir(.failure(Erreur.injoignable)) }
                    connexion.lireTrame { reponse in
                        switch reponse?.first {
                        case 1: finir(.success(()))
                        case 0: finir(.failure(Erreur.codeIncorrect))
                        default: finir(.failure(Erreur.injoignable))
                        }
                    }
                }
            }
        }
    }
}
