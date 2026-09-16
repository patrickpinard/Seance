import Foundation

/// Décompression des fichiers `.gz` de XML TV Fr (RFC 1952), sans dépendance externe.
/// Le framework Compression d'Apple ne lit que le flux DEFLATE brut : l'en-tête gzip
/// et les 8 octets de fin sont donc retirés ici.
public enum Gzip {
    public enum Erreur: Error, Equatable {
        case enteteInvalide
        case donneesTronquees
        case tailleIncorrecte(attendue: UInt32, obtenue: Int)
    }

    private enum Drapeau {
        static let crcEntete: UInt8 = 0x02
        static let extra: UInt8 = 0x04
        static let nom: UInt8 = 0x08
        static let commentaire: UInt8 = 0x10
    }

    public static func decompresser(_ donnees: Data) throws -> Data {
        let octets = [UInt8](donnees)
        guard octets.count >= 18, octets[0] == 0x1f, octets[1] == 0x8b, octets[2] == 8 else {
            throw Erreur.enteteInvalide
        }
        let drapeaux = octets[3]
        var position = 10
        if drapeaux & Drapeau.extra != 0 {
            guard position + 2 <= octets.count else { throw Erreur.donneesTronquees }
            let longueur = Int(octets[position]) | (Int(octets[position + 1]) << 8)
            position += 2 + longueur
        }
        if drapeaux & Drapeau.nom != 0 {
            position = try apresChaineC(octets, depuis: position)
        }
        if drapeaux & Drapeau.commentaire != 0 {
            position = try apresChaineC(octets, depuis: position)
        }
        if drapeaux & Drapeau.crcEntete != 0 {
            position += 2
        }
        let fin = octets.count - 8
        guard position <= fin else { throw Erreur.donneesTronquees }

        let resultat = try (Data(octets[position..<fin]) as NSData).decompressed(using: .zlib) as Data
        let tailleAttendue = UInt32(octets[fin + 4])
            | UInt32(octets[fin + 5]) << 8
            | UInt32(octets[fin + 6]) << 16
            | UInt32(octets[fin + 7]) << 24
        guard UInt32(truncatingIfNeeded: resultat.count) == tailleAttendue else {
            throw Erreur.tailleIncorrecte(attendue: tailleAttendue, obtenue: resultat.count)
        }
        return resultat
    }

    private static func apresChaineC(_ octets: [UInt8], depuis debut: Int) throws -> Int {
        guard let zero = octets[debut...].firstIndex(of: 0) else { throw Erreur.donneesTronquees }
        return zero + 1
    }
}
