import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI
import UIKit

/// Tout recevoir d'un autre appareil, par un code : le pendant, sur l'iPhone, l'iPad et le Mac, de ce que fait l'Apple TV.
/// Cet appareil affiche un code ; sur l'autre, Réglages › Tes appareils › « Envoyer à un appareil ». Arrivent la clé
/// TMDB, le NAS et son mot de passe, le lecteur, et toutes les données — ce qu'un fichier de sauvegarde ne porte jamais
/// (EF-86) passe ici d'appareil à appareil, chiffré, sans être écrit nulle part.
struct ReceptionParCode: View {
    /// Appelé quand tout est arrivé, avec la phrase qui le résume.
    let recu: (String) -> Void

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @State private var recepteur: RecepteurConfig?
    @State private var pret = false
    @State private var refus = 0
    @State private var erreur: String?

    var body: some View {
        if let recepteur {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sur l'autre appareil : Réglages › Tes appareils › « Envoyer à un appareil », puis tape ce code.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(recepteur.code.prefix(3) + " " + recepteur.code.suffix(3))
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy)).monospacedDigit()
                    .foregroundStyle(Theme.accentClair)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Code : " + recepteur.code.map(String.init).joined(separator: " "))
                if let erreur {
                    Label(erreur, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                } else if refus > 0 {
                    Label("Un code incorrect a été essayé. Relis celui-ci.", systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.orange)
                } else {
                    Label(pret ? "En attente, sur le même Wi-Fi…" : "Préparation…", systemImage: "wifi").font(.footnote).foregroundStyle(.secondary)
                }
                Button("Annuler", role: .cancel) { arreter() }.font(.subheadline)
            }
            .task(id: recepteur.code) { await ecouter(recepteur) }
        } else {
            Button { recepteur = RecepteurConfig(); pret = false; refus = 0; erreur = nil } label: {
                Label("Tout recevoir d'un autre appareil, par un code", systemImage: "iphone.and.arrow.forward")
            }
        }
    }

    private func arreter() {
        recepteur?.arreter()
        recepteur = nil
    }

    private func ecouter(_ recepteur: RecepteurConfig) async {
        for await evenement in recepteur.demarrer(nom: UIDevice.current.name) {
            switch evenement {
            case .pret: pret = true
            case .codeRefuse: refus += 1
            case .erreur(let message): erreur = message
            case .recue(let configuration):
                let phrase = await appliquer(configuration)
                arreter()
                recu(phrase)
                return
            }
        }
    }

    private func appliquer(_ configuration: ConfigurationTransferee) async -> String {
        var recus: [String] = []
        if let cle = configuration.cleTMDB, !cle.isEmpty, (try? await etat.enregistrerCle(cle)) != nil { recus.append("la clé TMDB") }
        if let reglages = configuration.nas {
            etat.nas.enregistrer(reglages)
            if let motDePasse = configuration.motDePasseNAS, !motDePasse.isEmpty { try? etat.nas.enregistrerMotDePasse(motDePasse) }
            recus.append("le NAS")
        }
        if let lecteur = configuration.lecteur { etat.nas.choisir(lecteur) }
        if let videos = configuration.videosPerso {
            etat.videosPerso.enregistrer(videos, motDePasse: configuration.motDePasseVideos ?? "")
            recus.append("l'accès à tes vidéos personnelles")
        }
        // L'e-mail de la semaine (6.5) : cet appareil peut l'envoyer à son tour, sans ressaisir le mot de passe.
        if let smtp = configuration.smtp {
            etat.lettre.recevoir(smtp, motDePasse: configuration.motDePasseSMTP)
            recus.append("l'e-mail de la semaine")
        }
        if let donnees = configuration.sauvegarde, let bilan = try? ImportSauvegarde.importer(donnees, etat: etat, contexte: contexte) {
            recus.append(bilan.estVide ? "tes données (déjà à jour)" : bilan.phrase)
        }
        etat.journal.noter(.general, "Configuration reçue de « \(configuration.expediteur) ».")
        guard !recus.isEmpty else { return "« \(configuration.expediteur) » n'avait rien à envoyer." }
        return "Reçu de « \(configuration.expediteur) » : " + recus.joined(separator: ", ") + "."
    }
}
