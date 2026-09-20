import Foundation
import Network

/// De quoi lire une vidéo là où elle est : sa taille, et n'importe quelle tranche d'octets. Le NAS en fournit une
/// (`SourceVideoSMB`), un fichier du disque aussi — c'est ce qui permet d'éprouver le relais sans NAS.
public protocol SourceVideo: Sendable {
    func taille() async throws -> UInt64
    /// Les octets de cette plage, éventuellement moins si le fichier s'arrête avant.
    func lire(_ plage: Range<UInt64>) async throws -> Data
}

/// Un petit serveur HTTP qui ne sert qu'une vidéo, qu'à cette app, et que sur `127.0.0.1` : AVPlayer ne sait pas
/// lire `smb://`, mais il lit parfaitement du HTTP avec des plages d'octets. Le relais traduit donc les demandes
/// du lecteur en lectures sur le NAS, sans rien copier sur l'appareil.
///
/// L'adresse porte un jeton tiré au hasard à chaque lecture : une autre app de l'appareil qui tomberait sur le
/// port ne saurait pas quoi demander.
public actor RelaisVideo {
    public enum Erreur: LocalizedError {
        case demarrageImpossible

        public var errorDescription: String? {
            switch self {
            case .demarrageImpossible: "La lecture n'a pas pu démarrer sur cet appareil."
            }
        }
    }

    /// Ce que le relais envoie d'un coup au lecteur : assez grand pour ne pas multiplier les allers-retours SMB,
    /// assez petit pour que l'avance rapide reste vive.
    static let tranche: UInt64 = 1 << 20

    private let source: any SourceVideo
    private let typeMIME: String
    private let jeton = UUID().uuidString.lowercased()
    private var ecouteur: NWListener?
    private var taille: UInt64 = 0

    public init(source: any SourceVideo, typeMIME: String = "video/mp4") {
        self.source = source
        self.typeMIME = typeMIME
    }

    /// Ouvre le relais et rend l'adresse à donner au lecteur. La taille est lue une fois, au début.
    public func demarrer() async throws -> URL {
        arreter()
        taille = try await source.taille()
        let parametres = NWParameters.tcp
        parametres.requiredInterfaceType = .loopback
        parametres.allowLocalEndpointReuse = true
        guard let nouveau = try? NWListener(using: parametres) else { throw Erreur.demarrageImpossible }
        nouveau.newConnectionHandler = { [weak self] connexion in
            Task { await self?.servir(connexion) }
        }
        ecouteur = nouveau
        let port = try await port(de: nouveau)
        guard let url = URL(string: "http://127.0.0.1:\(port)/\(jeton)") else { throw Erreur.demarrageImpossible }
        return url
    }

    public func arreter() {
        ecouteur?.cancel()
        ecouteur = nil
    }

    /// Attend que le système ait attribué un port.
    private func port(de ecouteur: NWListener) async throws -> UInt16 {
        try await withCheckedThrowingContinuation { suite in
            let rendu = Rendu()
            ecouteur.stateUpdateHandler = { etat in
                switch etat {
                case .ready:
                    guard let port = ecouteur.port?.rawValue else { return }
                    if rendu.premier() { suite.resume(returning: port) }
                case .failed, .cancelled:
                    if rendu.premier() { suite.resume(throwing: Erreur.demarrageImpossible) }
                default:
                    break
                }
            }
            ecouteur.start(queue: .global(qos: .userInitiated))
        }
    }

    private func servir(_ connexion: NWConnection) {
        connexion.start(queue: .global(qos: .userInitiated))
        Task { await echange(connexion) }
    }

    private func echange(_ connexion: NWConnection) async {
        defer { connexion.cancel() }
        guard let requete = await Self.lireRequete(connexion) else { return }
        guard requete.chemin.hasSuffix(jeton) else {
            await Self.envoyer(connexion, Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n".utf8))
            return
        }
        let debut = min(requete.plage?.lowerBound ?? 0, taille)
        let finDemandee = requete.plage?.upperBound ?? taille
        let fin = min(max(finDemandee, debut), taille)
        var entete = ""
        if requete.plage == nil {
            entete += "HTTP/1.1 200 OK\r\n"
        } else {
            entete += "HTTP/1.1 206 Partial Content\r\n"
            entete += "Content-Range: bytes \(debut)-\(max(fin, debut + 1) - 1)/\(taille)\r\n"
        }
        entete += "Content-Type: \(typeMIME)\r\n"
        entete += "Accept-Ranges: bytes\r\n"
        entete += "Content-Length: \(fin - debut)\r\n"
        entete += "Connection: close\r\n\r\n"
        guard await Self.envoyer(connexion, Data(entete.utf8)) else { return }
        // Une requête « HEAD » ou une plage vide n'attend pas d'octets.
        guard requete.methode != "HEAD", fin > debut else { return }

        var curseur = debut
        while curseur < fin {
            let bout = min(curseur + Self.tranche, fin)
            guard let donnees = try? await source.lire(curseur ..< bout), !donnees.isEmpty else { return }
            guard await Self.envoyer(connexion, donnees) else { return }
            curseur += UInt64(donnees.count)
        }
    }

    // MARK: - HTTP, au strict nécessaire

    struct Requete {
        let methode: String
        let chemin: String
        /// `bytes=1024-2047` devient `1024 ..< 2048` ; `bytes=1024-` va jusqu'au bout.
        let plage: Range<UInt64>?
    }

    /// Lit les en-têtes jusqu'à la ligne vide. Le corps d'une requête GET ne nous intéresse pas.
    private static func lireRequete(_ connexion: NWConnection) async -> Requete? {
        var recues = Data()
        while recues.range(of: Data("\r\n\r\n".utf8)) == nil, recues.count < 8192 {
            guard let bout = await recevoir(connexion), !bout.isEmpty else { break }
            recues.append(bout)
        }
        guard let texte = String(data: recues, encoding: .utf8) else { return nil }
        return analyser(texte)
    }

    static func analyser(_ texte: String) -> Requete? {
        let lignes = texte.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let premiere = lignes.first else { return nil }
        let morceaux = premiere.split(separator: " ")
        guard morceaux.count >= 2 else { return nil }
        let entete = lignes.first { $0.lowercased().hasPrefix("range:") }
        return Requete(methode: String(morceaux[0]), chemin: String(morceaux[1]), plage: entete.flatMap { plage(String($0)) })
    }

    static func plage(_ entete: String) -> Range<UInt64>? {
        guard let valeurs = entete.split(separator: "=").last?.split(separator: "-", omittingEmptySubsequences: false),
              let debut = UInt64(valeurs.first ?? "")
        else { return nil }
        if valeurs.count > 1, let dernier = UInt64(valeurs[1]) { return debut ..< (dernier + 1) }
        return debut ..< UInt64.max
    }

    private static func recevoir(_ connexion: NWConnection) async -> Data? {
        await withCheckedContinuation { suite in
            let rendu = Rendu()
            connexion.receive(minimumIncompleteLength: 1, maximumLength: 8192) { donnees, _, _, _ in
                if rendu.premier() { suite.resume(returning: donnees) }
            }
        }
    }

    @discardableResult
    private static func envoyer(_ connexion: NWConnection, _ donnees: Data) async -> Bool {
        await withCheckedContinuation { suite in
            let rendu = Rendu()
            connexion.send(content: donnees, completion: .contentProcessed { erreur in
                if rendu.premier() { suite.resume(returning: erreur == nil) }
            })
        }
    }
}

/// Garde-fou : un rappel de Network peut être appelé deux fois ; une continuation, jamais.
private final class Rendu: @unchecked Sendable {
    private let verrou = NSLock()
    private var fait = false

    func premier() -> Bool {
        verrou.lock()
        defer { verrou.unlock() }
        guard !fait else { return false }
        fait = true
        return true
    }
}

/// La source la plus simple : un fichier du disque. Sert aux tests du relais, et au Mac quand le partage est monté.
public struct SourceVideoFichier: SourceVideo {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func taille() async throws -> UInt64 {
        let valeurs = try url.resourceValues(forKeys: [.fileSizeKey])
        return UInt64(valeurs.fileSize ?? 0)
    }

    public func lire(_ plage: Range<UInt64>) async throws -> Data {
        let poignee = try FileHandle(forReadingFrom: url)
        defer { try? poignee.close() }
        try poignee.seek(toOffset: plage.lowerBound)
        return try poignee.read(upToCount: Int(plage.upperBound - plage.lowerBound)) ?? Data()
    }
}
