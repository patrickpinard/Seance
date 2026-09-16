import Foundation
import Security

/// Les clés d'API dont Séance a besoin (ENF-08). Elles ne vont ni dans le code, ni dans les journaux, ni dans la base.
public enum CleAPI: String, Sendable, CaseIterable {
    case tmdb
    case claude
    case srgssr
}

public protocol CoffreCles: Sendable {
    func lire(_ cle: CleAPI) throws -> String?
    func enregistrer(_ valeur: String, pour cle: CleAPI) throws
    func supprimer(_ cle: CleAPI) throws
}

public struct ErreurTrousseau: Error, Equatable {
    public let statut: OSStatus
}

/// Coffre adossé au trousseau de l'iPhone. Le groupe d'accès, s'il est fourni, permet au widget
/// de lire les mêmes clés (capacité Keychain Sharing, disponible avec un compte gratuit).
public struct Trousseau: CoffreCles {
    public let service: String
    public let groupeAcces: String?

    public init(service: String = "ch.patrick.seance", groupeAcces: String? = nil) {
        self.service = service
        self.groupeAcces = groupeAcces
    }

    private func requeteBase(_ cle: CleAPI) -> [String: Any] {
        var requete: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: cle.rawValue,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let groupeAcces {
            requete[kSecAttrAccessGroup as String] = groupeAcces
        }
        return requete
    }

    public func lire(_ cle: CleAPI) throws -> String? {
        var requete = requeteBase(cle)
        requete[kSecReturnData as String] = true
        requete[kSecMatchLimit as String] = kSecMatchLimitOne
        var resultat: CFTypeRef?
        let statut = SecItemCopyMatching(requete as CFDictionary, &resultat)
        switch statut {
        case errSecSuccess:
            return (resultat as? Data).flatMap { String(data: $0, encoding: .utf8) }
        case errSecItemNotFound:
            return nil
        default:
            throw ErreurTrousseau(statut: statut)
        }
    }

    public func enregistrer(_ valeur: String, pour cle: CleAPI) throws {
        let donnees = Data(valeur.utf8)
        let miseAJour = SecItemUpdate(requeteBase(cle) as CFDictionary, [kSecValueData as String: donnees] as CFDictionary)
        switch miseAJour {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var ajout = requeteBase(cle)
            ajout[kSecValueData as String] = donnees
            // Lisible par les tâches de fond et le widget après le premier déverrouillage.
            ajout[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let statut = SecItemAdd(ajout as CFDictionary, nil)
            guard statut == errSecSuccess else { throw ErreurTrousseau(statut: statut) }
        default:
            throw ErreurTrousseau(statut: miseAJour)
        }
    }

    public func supprimer(_ cle: CleAPI) throws {
        let statut = SecItemDelete(requeteBase(cle) as CFDictionary)
        guard statut == errSecSuccess || statut == errSecItemNotFound else { throw ErreurTrousseau(statut: statut) }
    }
}
