import Foundation

/// L'e-mail de la semaine (Séance 5.0) : ce qui sort et ce qui passe dans les sept jours, mis en page à la charte de
/// Séance — fond sombre, orange, affiches. Ici, rien que du texte : le contenu vient de l'app, l'envoi de `ClientSMTP`.
/// 8.11 : une lettre qui donne envie — une phrase d'accueil, le programme en une ligne, un titre à la une en grande
/// image, et pour chaque nouveauté sa note, un extrait du résumé et pourquoi elle devrait te plaire.
public struct LettreHebdo: Sendable, Equatable {
    public struct Ligne: Sendable, Equatable {
        public var titre: String
        /// « Nouvel épisode S02E04 », « Sort au cinéma », « RTS 1 · 21:10 ».
        public var detail: String
        /// « Jeudi 24 septembre ».
        public var quand: String
        public var urlAffiche: URL?
        public var lien: URL?
        /// 8.11 : deux ou trois lignes de résumé, la note TMDB, et pourquoi ça devrait te plaire (« Parce que tu aimes
        /// les thrillers », la phrase des suggestions de l'app).
        public var resume: String?
        public var note: Double?
        public var pourquoi: String?
        /// L'image large du titre, pour « À la une ».
        public var urlFond: URL?

        public init(titre: String, detail: String, quand: String, urlAffiche: URL? = nil, lien: URL? = nil,
                    resume: String? = nil, note: Double? = nil, pourquoi: String? = nil, urlFond: URL? = nil) {
            self.titre = titre
            self.detail = detail
            self.quand = quand
            self.urlAffiche = urlAffiche
            self.lien = lien
            self.resume = resume.flatMap { $0.isEmpty ? nil : $0 }
            self.note = note
            self.pourquoi = pourquoi.flatMap { $0.isEmpty ? nil : $0 }
            self.urlFond = urlFond
        }

        /// « Film · sur tes plateformes · ★ 7,8 ».
        var faits: String {
            [detail, note.map { "★ " + String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",") }]
                .compactMap { $0 }.joined(separator: " · ")
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
    /// L'heure de l'envoi (6.6), pour saluer juste : l'e-mail peut partir le matin comme le soir.
    public var envoyeLe: Date
    /// 8.11 : le titre qui ouvre la lettre, en grande image — la nouveauté qui te va le mieux.
    public var aLaUne: Ligne?
    /// 8.11 : « Au programme : 3 rendez-vous pour tes titres et 8 nouveautés sur tes plateformes. »
    public var auProgramme: String?

    /// La phrase d'accueil, sous le bonjour (8.11, demande de Patrick).
    public static let introduction = "Voici les informations concernant tes préférences et les nouveautés de la semaine."

    public init(prenom: String?, periode: String, sections: [Section], essai: Bool = false, envoyeLe: Date = .now,
                aLaUne: Ligne? = nil, auProgramme: String? = nil) {
        self.prenom = prenom
        self.periode = periode
        self.sections = sections
        self.essai = essai
        self.envoyeLe = envoyeLe
        self.aLaUne = aLaUne
        self.auProgramme = auProgramme
    }

    /// « Bonjour » avant 18 h, « Bonsoir » ensuite (6.6) — toujours « Bonsoir » jusque-là, même à 9 h du matin.
    public static func salutation(_ date: Date, calendrier: Calendar = .current) -> String {
        calendrier.component(.hour, from: date) < 18 ? "Bonjour" : "Bonsoir"
    }

    /// Le début d'un résumé, coupé entre deux mots : de quoi accrocher, pas tout raconter.
    public static func extrait(_ texte: String, maximum: Int = 220) -> String {
        let propre = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard propre.count > maximum else { return propre }
        let debut = propre.prefix(maximum)
        let coupe = debut.lastIndex(of: " ") ?? debut.endIndex
        return String(debut[..<coupe]).trimmingCharacters(in: CharacterSet(charactersIn: " ,;:.—-")) + "…"
    }

    public var estVide: Bool { aLaUne == nil && sections.allSatisfy(\.lignes.isEmpty) }

    /// Le sujet nomme ce qui est à la une : c'est lui qui donne envie d'ouvrir.
    public var sujet: String {
        (essai ? "[Essai] " : "") + (aLaUne.map { "Séance · \($0.titre), et ta semaine en films et séries" }
            ?? "Séance · ta semaine en films et séries")
    }

    // MARK: Texte brut (pour les lecteurs sans HTML)

    public var texte: String {
        var lignes = ["Séance — \(periode)", "", Self.introduction]
        if let auProgramme { lignes.append(auProgramme) }
        lignes.append("")
        if let une = aLaUne {
            lignes.append("À LA UNE : \(une.titre) — \(une.faits)")
            if let pourquoi = une.pourquoi { lignes.append(pourquoi) }
            if let resume = une.resume { lignes.append(resume) }
            lignes.append("")
        }
        if estVide {
            let voeu = Self.salutation(envoyeLe) == "Bonjour" ? "Bonne journée" : "Bonne soirée"
            lignes.append("Rien de prévu cette semaine pour tes titres. \(voeu) quand même !")
        }
        for section in sections where !section.lignes.isEmpty {
            lignes.append(section.titre.uppercased())
            for ligne in section.lignes {
                lignes.append("• \(ligne.titre) — \(ligne.detail) (\(ligne.quand))")
                if let pourquoi = ligne.pourquoi { lignes.append("  \(pourquoi)") }
                if let resume = ligne.resume { lignes.append("  \(resume)") }
            }
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
        static let resume = "#d6d6de"
    }

    public var html: String {
        let bonjour = Self.salutation(envoyeLe)
        let salut = prenom.map { "\(bonjour) \(Self.echapper($0))," } ?? "\(bonjour),"
        var corps = "<tr><td style=\"padding:22px 28px 4px;color:#ffffff;font-size:16px;line-height:1.55\">\(Self.echapper(Self.introduction))"
        if let auProgramme {
            corps += "<div style=\"color:\(Couleur.secondaire);font-size:15px;margin-top:8px\">\(Self.echapper(auProgramme))</div>"
        }
        corps += "</td></tr>"
        if let une = aLaUne { corps += Self.html(aLaUne: une) }
        if estVide {
            corps += "<tr><td style=\"padding:24px 28px;color:\(Couleur.secondaire);font-size:16px;line-height:1.5\">Rien de prévu cette semaine pour tes titres. Ouvre Séance : « Suggestions pour ce soir » a sûrement quelque chose pour toi.</td></tr>"
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
        <tr><td align="center" style="padding:28px 28px 8px"><a href="seance://cesoir" style="display:inline-block;background:\(Couleur.accent);color:#ffffff;font-weight:800;font-size:16px;text-decoration:none;padding:13px 26px;border-radius:999px">Ouvrir Séance et choisir ce soir</a></td></tr>
        <tr><td style="padding:26px 28px 30px;border-top:1px solid \(Couleur.trait);color:\(Couleur.secondaire);font-size:12px;line-height:1.6">
          Envoyé par Séance depuis ton appareil, une fois par semaine. Pour changer de jour, de destinataires ou l'arrêter : Réglages › E-mail de la semaine.<br>
          Affiches et données : TMDB. Disponibilités : JustWatch. Ce produit utilise l'API de TMDB mais n'est ni approuvé ni certifié par TMDB.
        </td></tr>
        </table></td></tr></table></body></html>
        """
    }

    /// Pourquoi pour toi, en orange clair, puis l'extrait du résumé : ce qui fait cliquer.
    private static func accroches(_ ligne: Ligne, taille: Int) -> String {
        var html = ""
        if let pourquoi = ligne.pourquoi {
            html += "<div style=\"font-size:\(taille)px;font-weight:600;color:\(Couleur.accentClair);margin-top:7px\">\(echapper(pourquoi))</div>"
        }
        if let resume = ligne.resume {
            html += "<div style=\"font-size:\(taille)px;line-height:1.45;color:\(Couleur.resume);margin-top:6px\">\(echapper(resume))</div>"
        }
        return html
    }

    private static func html(_ ligne: Ligne) -> String {
        let image = ligne.urlAffiche.map { adresse -> String in
            let img = "<img src=\"\(echapper(adresse.absoluteString))\" width=\"64\" height=\"96\" alt=\"\" style=\"display:block;border-radius:10px;border:0\">"
            // L'affiche ouvre la fiche, comme le titre.
            return ligne.lien.map { "<a href=\"\(echapper($0.absoluteString))\">\(img)</a>" } ?? img
        } ?? "<div style=\"width:64px;height:96px;border-radius:10px;background:\(Couleur.trait)\"></div>"
        let titre = ligne.lien.map { "<a href=\"\(echapper($0.absoluteString))\" style=\"color:#ffffff;text-decoration:none\">\(echapper(ligne.titre))</a>" } ?? echapper(ligne.titre)
        return """
        <tr><td style="padding:8px 28px"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:\(Couleur.surface);border-radius:16px"><tr>
          <td width="64" style="padding:12px 0 12px 12px;vertical-align:top">\(image)</td>
          <td style="padding:12px 16px;vertical-align:middle">
            <div style="font-size:12px;font-weight:800;letter-spacing:.4px;color:\(Couleur.secondaire);text-transform:uppercase">\(echapper(ligne.quand))</div>
            <div style="font-size:18px;font-weight:700;color:#ffffff;margin-top:3px">\(titre)</div>
            <div style="font-size:14px;color:\(Couleur.secondaire);margin-top:3px">\(echapper(ligne.faits))</div>
            \(accroches(ligne, taille: 14))
          </td></tr></table></td></tr>
        """
    }

    /// « À la une » : l'image large, le titre, la note, pourquoi pour toi, le résumé, et un bouton vers la fiche.
    private static func html(aLaUne ligne: Ligne) -> String {
        let image = (ligne.urlFond ?? ligne.urlAffiche).map { adresse in
            "<img src=\"\(echapper(adresse.absoluteString))\" width=\"544\" alt=\"\" style=\"display:block;width:100%;max-width:544px;height:auto;border-radius:16px 16px 0 0;border:0\">"
        } ?? ""
        let lienImage = ligne.lien.map { "<a href=\"\(echapper($0.absoluteString))\">\(image)</a>" } ?? image
        let bouton = ligne.lien.map {
            "<a href=\"\(echapper($0.absoluteString))\" style=\"display:inline-block;margin-top:16px;background:\(Couleur.accent);color:#ffffff;font-weight:800;font-size:15px;text-decoration:none;padding:11px 22px;border-radius:999px\">Voir la fiche</a>"
        } ?? ""
        return """
        <tr><td style="padding:18px 28px 6px"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:\(Couleur.surface);border-radius:16px">
          <tr><td>\(lienImage)</td></tr>
          <tr><td style="padding:16px 18px 20px">
            <div style="font-size:12px;font-weight:800;letter-spacing:.6px;color:\(Couleur.accent);text-transform:uppercase">À la une · \(echapper(ligne.quand))</div>
            <div style="font-size:24px;font-weight:900;color:#ffffff;margin-top:4px">\(echapper(ligne.titre))</div>
            <div style="font-size:14px;color:\(Couleur.secondaire);margin-top:4px">\(echapper(ligne.faits))</div>
            \(accroches(ligne, taille: 15))
            \(bouton)
          </td></tr></table></td></tr>
        """
    }

    static func echapper(_ texte: String) -> String {
        texte.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
