import Foundation
import Testing
@testable import SeanceKit

@Suite("E-mail de la semaine")
struct LettreHebdoTests {
    @Test func destinatairesSeparesParDesPointsVirgules() {
        #expect(MessageMail.adresses(" patrick@bluewin.ch ; anne@exemple.ch;pas-une-adresse ;PATRICK@bluewin.ch, luc@x.io") ==
                ["patrick@bluewin.ch", "anne@exemple.ch", "luc@x.io"])
        #expect(MessageMail.adresses("").isEmpty)
        #expect(!MessageMail.estUneAdresse("a@b") && !MessageMail.estUneAdresse("a b@c.ch") && MessageMail.estUneAdresse("a.b+c@d-e.ch"))
    }

    @Test func lettreALaCharteEtEchappee() {
        let lettre = LettreHebdo(prenom: "Patrick", periode: "Semaine du 21 au 27 septembre 2026", sections: [
            .init(titre: "Pour tes titres", lignes: [
                .init(titre: "Tom & Jerry <2>", detail: "Nouvel épisode S02E04", quand: "Jeudi 24 septembre",
                      urlAffiche: URL(string: "https://image.tmdb.org/t/p/w185/a.jpg"), lien: URL(string: "https://www.themoviedb.org/tv/1")),
            ]),
            .init(titre: "Vide", lignes: []),
        ])
        #expect(lettre.html.contains("Tom &amp; Jerry &lt;2&gt;") && !lettre.html.contains("<2>"))
        #expect(lettre.html.contains("#ff7a3d") && lettre.html.contains("Bonsoir Patrick,") && !lettre.html.contains(">Vide<"))
        #expect(lettre.texte.contains("• Tom & Jerry <2> — Nouvel épisode S02E04 (Jeudi 24 septembre)"))
        #expect(!lettre.estVide && LettreHebdo(prenom: nil, periode: "", sections: []).estVide)
        #expect(LettreHebdo(prenom: nil, periode: "", sections: [], essai: true).sujet.hasPrefix("[Essai] "))
    }

    @Test func messageMimeEtPointsDoubles() throws {
        let message = MessageMail(expediteur: "patrick@bluewin.ch", destinataires: ["a@x.ch", "b@y.ch"], sujet: "Séance · tes sorties",
                                  texte: "Bonsoir", html: "<p>Bonsoir</p>")
        let mime = message.mime(date: Date(timeIntervalSince1970: 0), identifiant: "abc")
        #expect(mime.contains("To: a@x.ch, b@y.ch\r\n") && mime.contains("Subject: =?UTF-8?B?"))
        #expect(mime.contains("From: =?UTF-8?B?") && mime.contains("<patrick@bluewin.ch>"))
        #expect(mime.contains("Content-Type: multipart/alternative; boundary=\"seance-abc\"") && mime.hasSuffix("--seance-abc--\r\n"))
        #expect(mime.contains(Data("<p>Bonsoir</p>".utf8).base64EncodedString()))
        #expect(MessageMail.base64EnLignes(String(repeating: "é", count: 200)).allSatisfy { $0.count <= 76 })

        #expect(ClientSMTP.corpsData("a\r\n.b\r\n..c\r\n") == "a\r\n..b\r\n...c\r\n.\r\n")
        #expect(ClientSMTP.reponseComplete("250-un\r\n250 OK\r\n") && !ClientSMTP.reponseComplete("250-un\r\n250-deux\r\n") && !ClientSMTP.reponseComplete("250 OK"))
        #expect(CompteSMTP(serveur: "smtpauths.bluewin.ch", utilisateur: "p", adresse: "p@bluewin.ch").estComplet && !CompteSMTP().estComplet)
    }
}

/// Sur le réseau : `SEANCE_SMTP_ESSAI=1 swift test --filter SMTPReel`. Sans identifiants valables, le serveur doit
/// refuser à l'étape de l'identification — ce qui prouve la connexion chiffrée et le début de la conversation.
@Suite("SMTP réel", .enabled(if: ProcessInfo.processInfo.environment["SEANCE_SMTP_ESSAI"] != nil))
struct SMTPReelTests {
    @Test func unMauvaisMotDePasseEstRefuseALIdentification() async {
        let compte = CompteSMTP(serveur: ProcessInfo.processInfo.environment["SEANCE_SMTP_SERVEUR"] ?? "smtpauths.bluewin.ch",
                                utilisateur: "seance-essai@bluewin.ch", adresse: "seance-essai@bluewin.ch")
        let message = MessageMail(expediteur: compte.adresse, destinataires: ["personne@exemple.invalid"], sujet: "Essai", texte: "Essai", html: "<p>Essai</p>")
        do {
            try await ClientSMTP(compte: compte, motDePasse: "mot-de-passe-faux").envoyer(message)
            Issue.record("Un mot de passe faux a été accepté")
        } catch let erreur as ErreurSMTP {
            guard case .refus(let etape, _) = erreur else { Issue.record("Attendu un refus, reçu \(erreur)"); return }
            #expect(etape == "identification")
        } catch {
            Issue.record("Erreur inattendue : \(error)")
        }
    }
}
