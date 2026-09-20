import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI
import UIKit

/// « Configurer depuis mon iPhone » : la TV affiche un code, l'iPhone envoie tout. Personne ne tape une clé de
/// trente-deux caractères à la télécommande.
struct ConfigurationTV: View {
    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Environment(\.dismiss) private var fermer

    @State private var recepteur = DepartTV.codeImpose.map { RecepteurConfig(code: $0) } ?? RecepteurConfig()
    @State private var pret = false
    @State private var refus = 0
    @State private var resultat: String?
    @State private var erreur: String?

    var body: some View {
        VStack(spacing: 44) {
            Image(systemName: "iphone.and.arrow.forward").font(.system(size: 90)).foregroundStyle(Theme.degradeAccent)
            if let resultat {
                Text("C'est fait").font(.system(size: 64, weight: .heavy))
                Text(resultat).font(.system(size: 32)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 1300)
                if etat.analyseEnCours {
                    Label("Lecture de ton NAS…", systemImage: "arrow.triangle.2.circlepath").font(.system(size: 28)).foregroundStyle(Theme.accentClair)
                }
                Button("Continuer") { fermer() }.buttonStyle(BoutonTV(principal: true))
            } else {
                Text("Configurer depuis mon iPhone").font(.system(size: 58, weight: .heavy))
                Text("Sur ton iPhone, ton iPad ou ton Mac : Séance › Réglages › « Configurer mon Apple TV », puis tape ce code.")
                    .font(.system(size: 30)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 1300)
                Text(codeLisible)
                    .font(.system(size: 150, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Theme.accentClair)   // une couleur franche : en dégradé, les premiers chiffres s'éteignaient
                    .accessibilityLabel("Code : " + recepteur.code.map(String.init).joined(separator: " "))
                if let erreur {
                    Label(erreur, systemImage: "exclamationmark.triangle.fill").font(.system(size: 28)).foregroundStyle(.orange)
                } else if refus > 0 {
                    Label("Un code incorrect a été essayé. Relis celui-ci.", systemImage: "exclamationmark.circle").font(.system(size: 28)).foregroundStyle(.orange)
                } else {
                    Label(pret ? "En attente de ton iPhone, sur le même Wi-Fi…" : "Préparation…", systemImage: "wifi")
                        .font(.system(size: 28)).foregroundStyle(.secondary)
                }
                Button("Annuler") { fermer() }.buttonStyle(BoutonTV())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.fond.ignoresSafeArea())
        .task { await ecouter() }
    }

    /// « 278 445 » : deux groupes se lisent et se tapent mieux que six chiffres collés.
    private var codeLisible: String {
        let code = recepteur.code
        return code.prefix(3) + " " + code.suffix(3)
    }

    private func ecouter() async {
        for await evenement in recepteur.demarrer(nom: UIDevice.current.name) {
            switch evenement {
            case .pret: pret = true
            case .codeRefuse: refus += 1
            case .erreur(let message): erreur = message
            case .recue(let configuration):
                resultat = etat.appliquer(configuration, contexte: contexte)
                recepteur.arreter()
                if etat.nasPret { await etat.analyserNAS(contexte: contexte) }
                return
            }
        }
    }
}
