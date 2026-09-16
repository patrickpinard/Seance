import Foundation

/// Construit les clients réseau à partir des clés du trousseau (ENF-08). Un client sans clé
/// enregistrée est `nil` : les écrans affichent alors l'invite de réglage plutôt qu'une erreur réseau.
public struct DepotCles: Sendable {
    public let coffre: any CoffreCles

    public init(coffre: any CoffreCles = Trousseau()) {
        self.coffre = coffre
    }

    /// Accepte indifféremment la clé d'API v3 ou le jeton d'accès en lecture v4.
    public func client() throws -> TMDBClient? {
        guard let valeur = try coffre.lire(.tmdb) else { return nil }
        return TMDBClient(identifiants: .depuis(valeur))
    }

    /// Sans clé Claude, « Ce soir » se rabat sur le classement local (EF-27).
    public func clientClaude() throws -> ClientClaude? {
        guard let valeur = try coffre.lire(.claude), !valeur.isEmpty else { return nil }
        return ClientClaude(cle: valeur)
    }
}
