import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI
import UIKit

/// Met en route un autre appareil depuis celui-ci — l'Apple TV, ou un iPhone, un iPad, un Mac (« Nouvel appareil ») :
/// il affiche un code, on le tape ici, et tout part par le réseau de la
/// maison — la clé TMDB, le NAS et son mot de passe, les listes, les soirées, ce qui est vu, les plateformes cochées.
/// Rien n'est écrit dans un fichier ni ne passe par internet (EF-86, EF-145).
struct EnvoiAppleTVView: View {
    let fermer: () -> Void

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte

    @State private var televiseurs: [EmetteurConfig.Televiseur] = []
    @State private var choisie: EmetteurConfig.Televiseur?
    @State private var code = ""
    @State private var envoi = false
    @State private var message: String?
    @State private var reussi = false
    @FocusState private var saisie: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    etape(1, "Sur l'autre appareil", "Apple TV : Séance › Réglages › « Configurer depuis mon iPhone ». iPhone, iPad ou Mac : « Nouvel appareil » › « Tout recevoir… ». Un code à six chiffres s'affiche.")
                    etape(2, "Ici", "Choisis l'appareil, tape le code, envoie. C'est tout.")
                }
                Section("Appareils qui attendent, sur ton réseau") {
                    if televiseurs.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Recherche… L'autre appareil doit afficher son code, sur le même Wi-Fi.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(televiseurs) { tv in
                        Button { choisie = tv } label: {
                            HStack {
                                Label(tv.nom, systemImage: tv.nom.localizedCaseInsensitiveContains("tv") ? "appletv.fill" : "iphone")
                                Spacer()
                                if (choisie ?? televiseurs.first) == tv { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Section {
                    TextField("Code affiché sur l'autre appareil", text: $code)
                        .keyboardType(.numberPad)
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .focused($saisie)
                        .onChange(of: code) { _, nouveau in code = String(nouveau.filter(\.isNumber).prefix(6)) }
                    Button { envoyer() } label: {
                        HStack {
                            Text(envoi ? "Envoi…" : "Envoyer").fontWeight(.semibold)
                            if envoi { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(envoi || code.count != 6 || (choisie ?? televiseurs.first) == nil)
                } footer: {
                    if let message {
                        Label(message, systemImage: reussi ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(reussi ? .green : .orange)
                    }
                }
                Section {
                    Text(contenu).font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("Ce qui est envoyé")
                }
            }
            .titreDeFeuille("Envoyer à un appareil")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(reussi ? "Terminé" : "Fermer", action: fermer) } }
            .task {
                for await trouvees in EmetteurConfig.chercher() { televiseurs = trouvees }
            }
        }
    }

    private func etape(_ numero: Int, _ titre: String, _ texte: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "\(numero).circle.fill").font(.title2).foregroundStyle(Theme.accentClair)
            VStack(alignment: .leading, spacing: 2) {
                Text(titre).font(.headline)
                Text(texte).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var contenu: String {
        var morceaux: [String] = []
        morceaux.append(etat.tmdb != nil ? "ta clé TMDB" : "pas de clé TMDB (aucune n'est enregistrée ici)")
        morceaux.append(etat.nas.estConfigure ? "l'adresse de ton NAS et son mot de passe" : "pas de NAS (il n'est pas configuré ici)")
        morceaux.append("tes listes, tes soirées, ce que tu as vu et noté, tes plateformes et tes chaînes")
        return "Par le Wi-Fi de la maison, chiffré avec le code : " + morceaux.joined(separator: " ; ") + ". La clé Claude reste ici."
    }

    private func envoyer() {
        guard let tv = choisie ?? televiseurs.first else { return }
        saisie = false
        envoi = true
        message = nil
        let coffre = etat.depot.coffre
        var complete = try? ServiceSauvegarde(contexte: contexte).exporter()
        complete?.preferences = PreferencesSauvegardees.lire()
        let sauvegarde = try? complete?.encoder()
        let configuration = ConfigurationTransferee(
            expediteur: UIDevice.current.name,
            cleTMDB: (try? coffre.lire(.tmdb)) ?? nil,
            nas: etat.nas.estConfigure ? etat.nas.reglages : nil,
            motDePasseNAS: (try? coffre.lire(.nas)) ?? nil,
            sauvegarde: sauvegarde,
            lecteur: etat.nas.lecteur
        )
        Task {
            do {
                try await EmetteurConfig.envoyer(configuration, a: tv, code: code)
                reussi = true
                message = "« \(tv.nom) » a tout reçu."
                etat.journal.noter(.general, "Configuration envoyée à « \(tv.nom) ».")
            } catch EmetteurConfig.Erreur.codeIncorrect {
                message = "Ce n'est pas le code affiché sur l'autre appareil. Vérifie-le et recommence."
            } catch {
                message = "L'appareil ne répond pas. Vérifie qu'il affiche toujours son code et qu'il est sur le même Wi-Fi."
            }
            envoi = false
        }
    }
}
