import CryptoKit
import Foundation
import Network

/// « Lire sur l'Apple TV » (8.1) : l'iPhone demande à Séance, ouverte sur la TV, de lire une vidéo du NAS à partir
/// d'une position. La demande passe par le réseau de la maison (Bonjour), signée d'une clé tirée du mot de passe du
/// NAS : seuls tes appareils le connaissent, un inconnu du réseau ne peut rien lancer. Rien de secret n'y voyage —
/// le chemin du fichier et la position.
public struct CommandeLecture: Codable, Sendable, Equatable {
    /// Le chemin dans le partage, comme `FichierNAS.chemin` ou `VideoPerso.chemin`.
    public var chemin: String
    /// Une vidéo personnelle (partage des souvenirs) plutôt qu'un film ou un épisode de la bibliothèque.
    public var souvenir: Bool
    /// Où reprendre, en secondes ; `nil` : depuis le début (ou la dernière position connue).
    public var depart: Double?
    public var expediteur: String
    public var emiseLe: Date
    /// Tiré au hasard pour chaque demande (8.11, audit de sécurité) : la TV refuse une demande déjà reçue, qu'on aurait
    /// captée sur le réseau pour la rejouer dans la minute.
    public var jeton: String

    public init(chemin: String, souvenir: Bool = false, depart: Double?, expediteur: String, emiseLe: Date = .now,
                jeton: String = UUID().uuidString) {
        self.chemin = chemin
        self.souvenir = souvenir
        self.depart = depart
        self.expediteur = expediteur
        self.emiseLe = emiseLe
        self.jeton = jeton
    }

    public static let service = "_seance-lecture._tcp"
    /// Au-delà, une demande est tenue pour rejouée : refusée.
    public static let validite: TimeInterval = 60

    public enum Erreur: Error, Equatable {
        case signature, perimee, illisible, injoignable, refusee, rejouee
    }

    /// 8.11 (audit de sécurité) : la clé dérive du mot de passe du NAS par HKDF, avec un sel et un contexte propres à
    /// Séance, et non plus par un simple hachage.
    private static func cle(_ secret: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(secret.utf8)), salt: Data("seance-lecture-2".utf8),
                               info: Data("commande de lecture".utf8), outputByteCount: 32)
    }

    /// La demande en JSON, suivie de sa signature (HMAC-SHA256, 32 octets).
    public func sceller(secret: String) throws -> Data {
        let encodeur = JSONEncoder()
        encodeur.dateEncodingStrategy = .iso8601
        let json = try encodeur.encode(self)
        let signature = HMAC<SHA256>.authenticationCode(for: json, using: Self.cle(secret))
        return json + Data(signature)
    }

    public static func ouvrir(_ message: Data, secret: String, maintenant: Date = .now) throws -> CommandeLecture {
        guard message.count > 32 else { throw Erreur.illisible }
        let json = message.prefix(message.count - 32), signature = message.suffix(32)
        guard HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: json, using: cle(secret)) else { throw Erreur.signature }
        let decodeur = JSONDecoder()
        decodeur.dateDecodingStrategy = .iso8601
        guard let commande = try? decodeur.decode(CommandeLecture.self, from: Data(json)) else { throw Erreur.illisible }
        guard abs(maintenant.timeIntervalSince(commande.emiseLe)) < validite else { throw Erreur.perimee }
        return commande
    }
}

/// Les jetons des demandes reçues dans la minute (8.11) : une même demande ne lance pas deux fois la lecture.
public final class MemoireJetons: @unchecked Sendable {
    private var vus: [String: Date] = [:]
    private let verrou = NSLock()

    public init() {}

    /// Vrai pour un jeton jamais vu ; faux s'il a déjà servi pendant la validité d'une demande.
    public func accepter(_ jeton: String, maintenant: Date = .now) -> Bool {
        verrou.lock()
        defer { verrou.unlock() }
        vus = vus.filter { maintenant.timeIntervalSince($0.value) < CommandeLecture.validite * 2 }
        guard vus[jeton] == nil else { return false }
        vus[jeton] = maintenant
        return true
    }
}

/// Côté Apple TV : s'annonce tant que Séance est ouverte, et rend chaque demande valable.
public final class RecepteurLecture: @unchecked Sendable {
    private var ecouteur: NWListener?
    private let file = DispatchQueue(label: "ch.patrick.seance.lecture.reception")
    private let secret: @Sendable () -> String?
    private let jetons = MemoireJetons()

    /// `secret` est relu à chaque demande : le mot de passe du NAS peut arriver après le lancement.
    public init(secret: @escaping @Sendable () -> String?) {
        self.secret = secret
    }

    public func demarrer(nom: String) -> AsyncStream<CommandeLecture> {
        AsyncStream { flux in
            do {
                let ecouteur = try NWListener(using: .tcp)
                ecouteur.service = NWListener.Service(name: nom, type: CommandeLecture.service)
                ecouteur.newConnectionHandler = { [weak self] connexion in self?.accueillir(connexion, flux) }
                ecouteur.stateUpdateHandler = { etat in
                    if case .failed = etat { flux.finish() }
                    if case .cancelled = etat { flux.finish() }
                }
                self.ecouteur = ecouteur
                ecouteur.start(queue: file)
            } catch {
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

    /// Lit une demande, répond 1 (lancée) ou 0 (refusée).
    private func accueillir(_ connexion: NWConnection, _ flux: AsyncStream<CommandeLecture>.Continuation) {
        connexion.start(queue: file)
        connexion.lireTrame { [secret] message in
            guard let message, let cle = secret(), let commande = try? CommandeLecture.ouvrir(message, secret: cle),
                  self.jetons.accepter(commande.jeton) else {
                return connexion.envoyerTrame(Data([0])) { _ in connexion.cancel() }
            }
            connexion.envoyerTrame(Data([1])) { _ in connexion.cancel() }
            flux.yield(commande)
        }
    }
}

/// Côté iPhone : trouve les Apple TV où Séance est ouverte, et leur envoie la vidéo à lire.
public enum EmetteurLecture {
    public static func chercher() -> AsyncStream<[EmetteurConfig.Televiseur]> {
        AsyncStream { flux in
            let explorateur = NWBrowser(for: .bonjour(type: CommandeLecture.service, domain: nil), using: .tcp)
            explorateur.browseResultsChangedHandler = { resultats, _ in
                let televiseurs = resultats.compactMap { resultat -> EmetteurConfig.Televiseur? in
                    guard case .service(let nom, _, _, _) = resultat.endpoint else { return nil }
                    return EmetteurConfig.Televiseur(nom: nom, destination: resultat.endpoint)
                }
                flux.yield(televiseurs.sorted { $0.nom < $1.nom })
            }
            explorateur.start(queue: DispatchQueue(label: "ch.patrick.seance.lecture.recherche"))
            flux.onTermination = { _ in explorateur.cancel() }
        }
    }

    public static func envoyer(_ commande: CommandeLecture, a televiseur: EmetteurConfig.Televiseur, secret: String) async throws {
        let message = try commande.sceller(secret: secret)
        let connexion = NWConnection(to: televiseur.destination, using: .tcp)
        let uneFois = UneFois()
        defer { connexion.cancel() }
        try await withCheckedThrowingContinuation { (suite: CheckedContinuation<Void, any Error>) in
            @Sendable func finir(_ resultat: Result<Void, any Error>) { uneFois.tenter { suite.resume(with: resultat) } }
            let file = DispatchQueue(label: "ch.patrick.seance.lecture.envoi")
            connexion.stateUpdateHandler = { etat in
                switch etat {
                case .failed, .cancelled: finir(.failure(CommandeLecture.Erreur.injoignable))
                default: break
                }
            }
            file.asyncAfter(deadline: .now() + 10) { finir(.failure(CommandeLecture.Erreur.injoignable)) }
            connexion.start(queue: file)
            connexion.envoyerTrame(message) { envoye in
                guard envoye else { return finir(.failure(CommandeLecture.Erreur.injoignable)) }
                connexion.lireTrame { reponse in
                    finir(reponse?.first == 1 ? .success(()) : .failure(CommandeLecture.Erreur.refusee))
                }
            }
        }
    }
}
