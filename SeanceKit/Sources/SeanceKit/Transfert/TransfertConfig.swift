import CryptoKit
import Foundation

/// Ce qu'un iPhone envoie à une Apple TV pour la mettre en route d'un coup : les clés, le NAS et les données.
/// Les clés ne voyagent toujours dans aucun fichier (EF-86) : ce message va d'un appareil à l'autre par le réseau de
/// la maison, chiffré, et n'est jamais écrit sur un disque.
public struct ConfigurationTransferee: Codable, Sendable, Equatable {
    public var expediteur: String
    public var cleTMDB: String?
    public var nas: ReglagesNAS?
    public var motDePasseNAS: String?
    /// Une `Sauvegarde` encodée : listes, soirées, visionnages, plateformes cochées.
    public var sauvegarde: Data?
    /// L'app de lecture choisie sur l'expéditeur : la TV la reprend, et reste libre d'en changer.
    public var lecteur: LecteurVideo?
    /// Le second accès au NAS, celui des vidéos personnelles, et son mot de passe s'il a le sien.
    public var videosPerso: ReglagesVideosPerso?
    public var motDePasseVideos: String?
    /// Le compte qui envoie l'e-mail de la semaine, et son mot de passe (6.5). Il ne sort d'un appareil que par ce
    /// message chiffré, jamais dans une sauvegarde ni dans la synchronisation : un dossier partagé se lit.
    public var smtp: Data?
    public var motDePasseSMTP: String?

    public init(expediteur: String, cleTMDB: String? = nil, nas: ReglagesNAS? = nil, motDePasseNAS: String? = nil, sauvegarde: Data? = nil,
                lecteur: LecteurVideo? = nil, videosPerso: ReglagesVideosPerso? = nil, motDePasseVideos: String? = nil,
                smtp: Data? = nil, motDePasseSMTP: String? = nil) {
        self.expediteur = expediteur
        self.cleTMDB = cleTMDB
        self.nas = nas
        self.motDePasseNAS = motDePasseNAS
        self.sauvegarde = sauvegarde
        self.lecteur = lecteur
        self.videosPerso = videosPerso
        self.motDePasseVideos = motDePasseVideos
        self.smtp = smtp
        self.motDePasseSMTP = motDePasseSMTP
    }
}

/// Le chiffrement du transfert. La TV tire une clé éphémère et affiche un code à six chiffres ; l'iPhone tire la sienne,
/// et la clé du message dérive du secret partagé (Curve25519) **et** du code : sans le code lu sur l'écran de la TV,
/// le message ne s'ouvre pas. Limite connue et assumée pour un réseau domestique : six chiffres ne résistent pas à un
/// attaquant actif déjà présent sur le Wi-Fi, qui s'interposerait et essaierait le million de codes.
public enum TransfertConfig {
    /// Service Bonjour, à déclarer dans `NSBonjourServices` des deux apps.
    public static let service = "_seance-config._tcp"
    static let tailleCle = 32
    /// Une sauvegarde pèse quelques centaines de kilo-octets ; au-delà de cette taille, ce n'est pas un message de Séance.
    static let tailleMax = 32 * 1024 * 1024

    public enum Erreur: Error, Equatable {
        case codeIncorrect
        case messageIllisible
    }

    public static func nouveauCode() -> String {
        var generateur = SystemRandomNumberGenerator()
        return String(format: "%06d", Int.random(in: 0...999_999, using: &generateur))
    }

    static func cle(_ secret: SharedSecret, code: String) -> SymmetricKey {
        secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(code.utf8), sharedInfo: Data("seance-config-1".utf8), outputByteCount: 32)
    }

    /// Côté iPhone : la clé publique de l'expéditeur, suivie du message scellé.
    public static func sceller(_ configuration: ConfigurationTransferee, pour clePubliqueTV: Data, code: String) throws -> Data {
        let tv = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: clePubliqueTV)
        let mienne = Curve25519.KeyAgreement.PrivateKey()
        let secret = try mienne.sharedSecretFromKeyAgreement(with: tv)
        let boite = try ChaChaPoly.seal(try JSONEncoder().encode(configuration), using: cle(secret, code: code))
        return mienne.publicKey.rawRepresentation + boite.combined
    }

    /// Côté TV. Un code faux donne une clé fausse : l'ouverture échoue, et c'est `codeIncorrect`.
    public static func ouvrir(_ message: Data, avec clePrivee: Curve25519.KeyAgreement.PrivateKey, code: String) throws -> ConfigurationTransferee {
        guard message.count > tailleCle else { throw Erreur.messageIllisible }
        let expediteur: Curve25519.KeyAgreement.PublicKey
        let boite: ChaChaPoly.SealedBox
        do {
            expediteur = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: message.prefix(tailleCle))
            boite = try ChaChaPoly.SealedBox(combined: message.dropFirst(tailleCle))
        } catch {
            throw Erreur.messageIllisible
        }
        let secret = try clePrivee.sharedSecretFromKeyAgreement(with: expediteur)
        guard let clair = try? ChaChaPoly.open(boite, using: cle(secret, code: code)) else { throw Erreur.codeIncorrect }
        guard let configuration = try? JSONDecoder().decode(ConfigurationTransferee.self, from: clair) else { throw Erreur.messageIllisible }
        return configuration
    }

    /// Une trame : quatre octets de longueur, puis le contenu.
    static func trame(_ contenu: Data) -> Data {
        var longueur = UInt32(contenu.count).bigEndian
        return Data(bytes: &longueur, count: 4) + contenu
    }

    static func longueur(_ entete: Data) -> Int? {
        guard entete.count == 4 else { return nil }
        let valeur = entete.reduce(0) { ($0 << 8) | Int($1) }
        return valeur > 0 && valeur <= tailleMax ? valeur : nil
    }
}
