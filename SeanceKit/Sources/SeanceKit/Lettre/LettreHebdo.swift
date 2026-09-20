import Foundation

/// L'e-mail de la semaine (Séance 5.0) : ce qui sort et ce qui passe dans les sept jours, mis en page à la charte de
/// Séance — fond sombre, orange, affiches. Ici, rien que du texte : le contenu vient de l'app, l'envoi de `ClientSMTP`.
public struct LettreHebdo: Sendable, Equatable {
    public struct Ligne: Sendable, Equatable {
        public var titre: String
        /// « Nouvel épisode S02E04 », « Sort au cinéma », « RTS 1 · 21:10 ».
        public var detail: String
        /// « Jeudi 24 septembre ».
        public var quand: String
        public var urlAffiche: URL?
        public var lien: URL?

        public init(titre: String, detail: String, quand: String, urlAffiche: URL? = nil, lien: URL? = nil) {
            self.titre = titre
            self.detail = detail
            self.quand = quand
            self.urlAffiche = urlAffiche
            self.lien = lien
        }
    }

    public struct Section: Sendable, Equatable {
        public var titre: String
        public var sousTitre: String?
        public var lignes: [Ligne]

        public init(titre: String, sousTitre: String? = nil, lignes: [Ligne]) {
            self.titre = titre
            self.sousTitre = sousTitre
            self.lignes = lignes
        }
    }

    public var prenom: String?
    /// « Semaine du 21 au 27 septembre 2026 ».
    public var periode: String
    public var sections: [Section]
    public var essai = false

    public init(prenom: String?, periode: String, sections: [Section], essai: Bool = false) {
        self.prenom = prenom
        self.periode = periode
        self.sections = sections
        self.essai = essai
    }

    public var estVide: Bool { sections.allSatisfy(\.lignes.isEmpty) }

    public var sujet: String {
        (essai ? "[Essai] " : "") + "Séance · tes sorties de la semaine"
    }

    // MARK: Texte brut (pour les lecteurs sans HTML)

    public var texte: String {
        var lignes = ["Séance — \(periode)", ""]
        if estVide { lignes.append("Rien de prévu cette semaine pour tes titres. Bonne soirée quand même !") }
        for section in sections where !section.lignes.isEmpty {
            lignes.append(section.titre.uppercased())
            for ligne in section.lignes { lignes.append("• \(ligne.titre) — \(ligne.detail) (\(ligne.quand))") }
            lignes.append("")
        }
        lignes.append("Envoyé par Séance, depuis ton appareil. Pour ne plus le recevoir : Réglages › E-mail de la semaine.")
        return lignes.joined(separator: "\n")
    }

    // MARK: HTML à la charte

    /// Les couleurs de `Theme` : fond, surface, accent, accent clair.
    private enum Couleur {
        static let fond = "#0b0b10"
        static let surface = "#1a1a20"
        static let trait = "#2b2b33"
        static let accent = "#ff7a3d"
        static let accentClair = "#ffab5e"
        static let secondaire = "#a9a9b4"
    }

    public var html: String {
        let salut = prenom.map { "Bonsoir \(Self.echapper($0))," } ?? "Bonsoir,"
        var corps = ""
        if estVide {
            corps += "<tr><td style=\"padding:24px 28px;color:\(Couleur.secondaire);font-size:16px;line-height:1.5\">Rien de prévu cette semaine pour tes titres. Ouvre Séance : « Idées pour ce soir » a sûrement quelque chose pour toi.</td></tr>"
        }
        for section in sections where !section.lignes.isEmpty {
            corps += "<tr><td style=\"padding:26px 28px 6px\"><div style=\"font-size:21px;font-weight:800;color:#ffffff\">\(Self.echapper(section.titre))</div>"
            if let sousTitre = section.sousTitre {
                corps += "<div style=\"font-size:14px;color:\(Couleur.secondaire);margin-top:3px\">\(Self.echapper(sousTitre))</div>"
            }
            corps += "</td></tr>"
            for ligne in section.lignes { corps += Self.html(ligne) }
        }
        return """
        <!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark"><title>\(Self.echapper(sujet))</title></head>
        <body style="margin:0;padding:0;background:\(Couleur.fond);font-family:-apple-system,'SF Pro Text','Helvetica Neue',Arial,sans-serif">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:\(Couleur.fond)"><tr><td align="center" style="padding:24px 12px">
        <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background:\(Couleur.fond);border:1px solid \(Couleur.trait);border-radius:22px;overflow:hidden">
        <tr><td style="padding:30px 28px 22px;background:linear-gradient(90deg,#1c120c,\(Couleur.fond));border-bottom:1px solid \(Couleur.trait)">
          <div style="font-size:30px;font-weight:900;letter-spacing:-.5px;color:\(Couleur.accent)">Séance</div>
          <div style="font-size:22px;font-weight:800;color:#ffffff;margin-top:14px">\(salut) voici ta semaine</div>
          <div style="font-size:15px;color:\(Couleur.secondaire);margin-top:4px">\(Self.echapper(periode))\(essai ? " · e-mail d'essai" : "")</div>
        </td></tr>
        \(corps)
        <tr><td style="padding:26px 28px 30px;border-top:1px solid \(Couleur.trait);color:\(Couleur.secondaire);font-size:12px;line-height:1.6">
          Envoyé par Séance depuis ton appareil, une fois par semaine. Pour changer de jour, de destinataires ou l'arrêter : Réglages › E-mail de la semaine.<br>
          Affiches et données : TMDB. Disponibilités : JustWatch. Ce produit utilise l'API de TMDB mais n'est ni approuvé ni certifié par TMDB.
        </td></tr>
        </table></td></tr></table></body></html>
        """
    }

    private static func html(_ ligne: Ligne) -> String {
        let image = ligne.urlAffiche.map {
            "<img src=\"\(echapper($0.absoluteString))\" width=\"64\" height=\"96\" alt=\"\" style=\"display:block;border-radius:10px;border:0\">"
        } ?? "<div style=\"width:64px;height:96px;border-radius:10px;background:\(Couleur.trait)\"></div>"
        let titre = ligne.lien.map { "<a href=\"\(echapper($0.absoluteString))\" style=\"color:#ffffff;text-decoration:none\">\(echapper(ligne.titre))</a>" } ?? echapper(ligne.titre)
        return """
        <tr><td style="padding:8px 28px"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:\(Couleur.surface);border-radius:16px"><tr>
          <td width="64" style="padding:12px 0 12px 12px;vertical-align:top">\(image)</td>
          <td style="padding:12px 16px;vertical-align:middle">
            <div style="font-size:12px;font-weight:800;letter-spacing:.4px;color:\(Couleur.accentClair);text-transform:uppercase">\(echapper(ligne.quand))</div>
            <div style="font-size:18px;font-weight:700;color:#ffffff;margin-top:3px">\(titre)</div>
            <div style="font-size:14px;color:\(Couleur.secondaire);margin-top:3px">\(echapper(ligne.detail))</div>
          </td></tr></table></td></tr>
        """
    }

    static func echapper(_ texte: String) -> String {
        texte.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
