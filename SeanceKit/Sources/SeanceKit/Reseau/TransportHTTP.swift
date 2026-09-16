import Foundation

/// Ce dont les clients d'API ont besoin du réseau. `URLSession` le fournit ; les tests le simulent.
public protocol TransportHTTP: Sendable {
    func envoyer(_ requete: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public enum ErreurReseau: Error, Equatable {
    case reponseNonHTTP
}

extension URLSession: TransportHTTP {
    public func envoyer(_ requete: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (donnees, reponse) = try await data(for: requete)
        guard let http = reponse as? HTTPURLResponse else { throw ErreurReseau.reponseNonHTTP }
        return (donnees, http)
    }
}

