import Foundation
import Network

/// Le compte de messagerie qui envoie : serveur en TLS implicite (port 465 — Bluewin, Gmail, Infomaniak, GMX…).
/// Les serveurs qui n'offrent que STARTTLS sur le port 587 (iCloud) ne sont pas pris en charge.
public struct CompteSMTP: Sendable, Equatable, Codable {
    public var serveur: String
    public var port: Int
    public var utilisateur: String
    /// L'adresse « De » ; souvent la même que l'utilisateur.
    public var adresse: String

    public init(serveur: String = "", port: Int = 465, utilisateur: String = "", adresse: String = "") {
        self.serveur = serveur
        self.port = port
        self.utilisateur = utilisateur
        self.adresse = adresse
    }

    public var estComplet: Bool {
        !serveur.trimmingCharacters(in: .whitespaces).isEmpty && !utilisateur.isEmpty && MessageMail.estUneAdresse(adresse) && (1...65_535).contains(port)
    }
}

public enum ErreurSMTP: Error, Equatable, LocalizedError {
    case connexion(String)
    case refus(etape: String, reponse: String)
    case delai

    public var errorDescription: String? {
        switch self {
        case .connexion(let detail): "Le serveur d'envoi ne répond pas (\(detail)). Vérifie son nom et le port 465."
        case .refus(let etape, let reponse):
            etape == "identification" ? "Le serveur refuse l'utilisateur ou le mot de passe. Certains (Gmail) exigent un « mot de passe d'application »."
                                      : "Le serveur a refusé l'envoi (\(etape)) : \(reponse)"
        case .delai: "Le serveur d'envoi met trop de temps à répondre."
        }
    }
}

/// Un client SMTP minimal : une connexion TLS, une identification, un message. Assez pour un e-mail par semaine.
public struct ClientSMTP: Sendable {
    public let compte: CompteSMTP
    private let motDePasse: String

    public init(compte: CompteSMTP, motDePasse: String) {
        self.compte = compte
        self.motDePasse = motDePasse
    }

    /// Le corps de DATA : un point en début de ligne se double (RFC 5321, 4.5.2), et le message se termine par « . ».
    public static func corpsData(_ mime: String) -> String {
        let lignes = mime.components(separatedBy: "\r\n").map { $0.hasPrefix(".") ? "." + $0 : $0 }
        var corps = lignes.joined(separator: "\r\n")
        if !corps.hasSuffix("\r\n") { corps += "\r\n" }
        return corps + ".\r\n"
    }

    /// Une réponse est complète quand sa dernière ligne porte un code suivi d'une espace (« 250 OK »), pas d'un tiret.
    public static func reponseComplete(_ texte: String) -> Bool {
        guard texte.hasSuffix("\r\n"), let derniere = texte.dropLast(2).components(separatedBy: "\r\n").last, derniere.count >= 3 else { return false }
        return derniere.count == 3 || derniere[derniere.index(derniere.startIndex, offsetBy: 3)] == " "
    }

    public func envoyer(_ message: MessageMail) async throws {
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: compte.port)) else { throw ErreurSMTP.connexion("port invalide") }
        let connexion = NWConnection(host: NWEndpoint.Host(compte.serveur.trimmingCharacters(in: .whitespaces)), port: port, using: .tls)
        defer { connexion.cancel() }
        try await ouvrir(connexion)

        _ = try await attendre(connexion, codes: ["220"], etape: "accueil")
        _ = try await dire("EHLO seance.local", connexion, codes: ["250"], etape: "présentation")
        _ = try await dire("AUTH LOGIN", connexion, codes: ["334"], etape: "identification")
        _ = try await dire(Data(compte.utilisateur.utf8).base64EncodedString(), connexion, codes: ["334"], etape: "identification")
        _ = try await dire(Data(motDePasse.utf8).base64EncodedString(), connexion, codes: ["235"], etape: "identification")
        _ = try await dire("MAIL FROM:<\(message.expediteur)>", connexion, codes: ["250"], etape: "expéditeur")
        for destinataire in message.destinataires {
            _ = try await dire("RCPT TO:<\(destinataire)>", connexion, codes: ["250", "251"], etape: "destinataire \(destinataire)")
        }
        _ = try await dire("DATA", connexion, codes: ["354"], etape: "message")
        try await ecrire(Self.corpsData(message.mime()), connexion)
        _ = try await attendre(connexion, codes: ["250"], etape: "message")
        try? await ecrire("QUIT\r\n", connexion)
    }

    // MARK: Conversation

    private func ouvrir(_ connexion: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (suite: CheckedContinuation<Void, any Error>) in
            let repondu = Verrou()
            connexion.stateUpdateHandler = { etat in
                switch etat {
                case .ready: if repondu.premier() { suite.resume() }
                case .failed(let erreur): if repondu.premier() { suite.resume(throwing: ErreurSMTP.connexion(erreur.localizedDescription)) }
                case .waiting(let erreur): if repondu.premier() { suite.resume(throwing: ErreurSMTP.connexion(erreur.localizedDescription)) }
                default: break
                }
            }
            connexion.start(queue: .global(qos: .utility))
        }
    }

    private func dire(_ commande: String, _ connexion: NWConnection, codes: [String], etape: String) async throws -> String {
        try await ecrire(commande + "\r\n", connexion)
        return try await attendre(connexion, codes: codes, etape: etape)
    }

    private func ecrire(_ texte: String, _ connexion: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (suite: CheckedContinuation<Void, any Error>) in
            connexion.send(content: Data(texte.utf8), completion: .contentProcessed { erreur in
                if let erreur { suite.resume(throwing: ErreurSMTP.connexion(erreur.localizedDescription)) } else { suite.resume() }
            })
        }
    }

    private func attendre(_ connexion: NWConnection, codes: [String], etape: String) async throws -> String {
        var recu = ""
        while !Self.reponseComplete(recu) {
            let morceau: Data = try await withCheckedThrowingContinuation { suite in
                connexion.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { donnees, _, fini, erreur in
                    if let erreur { suite.resume(throwing: ErreurSMTP.connexion(erreur.localizedDescription)) }
                    else if let donnees, !donnees.isEmpty { suite.resume(returning: donnees) }
                    else if fini { suite.resume(throwing: ErreurSMTP.connexion("connexion fermée")) }
                    else { suite.resume(returning: Data()) }
                }
            }
            recu += String(decoding: morceau, as: UTF8.self)
            if recu.count > 65_536 { throw ErreurSMTP.delai }
        }
        guard codes.contains(where: { recu.hasPrefix($0) || recu.components(separatedBy: "\r\n").dropLast().last?.hasPrefix($0) == true }) else {
            throw ErreurSMTP.refus(etape: etape, reponse: recu.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\r\n").last ?? recu)
        }
        return recu
    }

    /// Une continuation ne se reprend qu'une fois, même si l'état de la connexion change plusieurs fois.
    private final class Verrou: @unchecked Sendable {
        private let verrou = NSLock()
        private var fait = false
        func premier() -> Bool { verrou.withLock { if fait { return false }; fait = true; return true } }
    }
}
