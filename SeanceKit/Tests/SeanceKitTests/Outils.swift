import Foundation
@testable import SeanceKit

enum Fixture {
    /// Réponses d'exemple de la spécification OpenAPI de TMDB, et extrait réel de XML TV Fr.
    static func donnees(_ nom: String, extension ext: String = "json") throws -> Data {
        guard let url = Bundle.module.url(forResource: nom, withExtension: ext, subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "Fixtures/\(nom).\(ext)"])
        }
        return try Data(contentsOf: url)
    }
}

/// Transport qui rejoue des réponses préparées et garde les requêtes reçues.
actor TransportSimule: TransportHTTP {
    struct Reponse {
        var code: Int
        var entetes: [String: String] = [:]
        var corps = Data()
    }

    private var aRenvoyer: [Reponse]
    private(set) var requetes: [URLRequest] = []

    init(_ reponses: [Reponse]) {
        aRenvoyer = reponses
    }

    func envoyer(_ requete: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requetes.append(requete)
        guard !aRenvoyer.isEmpty else { throw URLError(.cannotConnectToHost) }
        let reponse = aRenvoyer.removeFirst()
        let http = HTTPURLResponse(url: requete.url!, statusCode: reponse.code, httpVersion: "HTTP/1.1", headerFields: reponse.entetes)!
        return (reponse.corps, http)
    }
}

/// Remplace `Task.sleep` : note les attentes demandées sans attendre réellement.
actor JournalAttentes {
    private(set) var durees: [Duration] = []

    func noter(_ duree: Duration) {
        durees.append(duree)
    }
}

extension Date {
    static func iso(_ texte: String) -> Date {
        try! Date.ISO8601FormatStyle().parse(texte)
    }
}
