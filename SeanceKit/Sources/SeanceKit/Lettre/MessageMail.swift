import Foundation

/// Un e-mail prêt à partir : deux corps (texte et HTML), plusieurs destinataires, tout en UTF-8.
public struct MessageMail: Sendable, Equatable {
    public var expediteur: String
    public var nomExpediteur: String
    public var destinataires: [String]
    public var sujet: String
    public var texte: String
    public var html: String

    public init(expediteur: String, nomExpediteur: String = "Séance", destinataires: [String], sujet: String, texte: String, html: String) {
        self.expediteur = expediteur
        self.nomExpediteur = nomExpediteur
        self.destinataires = destinataires
        self.sujet = sujet
        self.texte = texte
        self.html = html
    }

    /// « a@x.ch ; b@y.ch, c@z.ch » → les adresses plausibles, sans doublon, dans l'ordre. Séparateurs : « ; », « , », espace, retour.
    public static func adresses(_ saisie: String) -> [String] {
        var vues = Set<String>()
        return saisie.components(separatedBy: CharacterSet(charactersIn: ";, \n\t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { estUneAdresse($0) && vues.insert($0.lowercased()).inserted }
    }

    public static func estUneAdresse(_ texte: String) -> Bool {
        let morceaux = texte.split(separator: "@", omittingEmptySubsequences: false)
        guard morceaux.count == 2, !morceaux[0].isEmpty, morceaux[1].contains("."), !morceaux[1].hasPrefix("."), !morceaux[1].hasSuffix("."),
              !texte.contains(where: { $0.isWhitespace || "<>()[],;:\"".contains($0) }) else { return false }
        return true
    }

    /// Le message au format MIME (RFC 5322 et 2045), lignes terminées par CRLF, prêt pour la commande DATA.
    public func mime(date: Date = .now, identifiant: String = UUID().uuidString) -> String {
        let frontiere = "seance-\(identifiant)"
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        let domaine = expediteur.split(separator: "@").last.map(String.init) ?? "seance.local"
        var lignes = [
            "From: \(Self.motEncode(nomExpediteur)) <\(expediteur)>",
            "To: \(destinataires.joined(separator: ", "))",
            "Subject: \(Self.motEncode(sujet))",
            "Date: \(format.string(from: date))",
            "Message-ID: <\(identifiant)@\(domaine)>",
            "MIME-Version: 1.0",
            "Content-Type: multipart/alternative; boundary=\"\(frontiere)\"",
            "",
        ]
        for (type, corps) in [("text/plain", texte), ("text/html", html)] {
            lignes += ["--\(frontiere)", "Content-Type: \(type); charset=utf-8", "Content-Transfer-Encoding: base64", ""]
            lignes += Self.base64EnLignes(corps)
            lignes.append("")
        }
        lignes.append("--\(frontiere)--")
        return lignes.joined(separator: "\r\n") + "\r\n"
    }

    /// Un en-tête qui sort de l'ASCII voyage en « mot encodé » (RFC 2047).
    static func motEncode(_ texte: String) -> String {
        texte.allSatisfy(\.isASCII) ? texte : "=?UTF-8?B?\(Data(texte.utf8).base64EncodedString())?="
    }

    static func base64EnLignes(_ texte: String) -> [String] {
        let encode = Data(texte.utf8).base64EncodedString()
        return stride(from: 0, to: encode.count, by: 76).map { debut in
            let a = encode.index(encode.startIndex, offsetBy: debut)
            let b = encode.index(a, offsetBy: min(76, encode.count - debut))
            return String(encode[a..<b])
        }
    }
}
