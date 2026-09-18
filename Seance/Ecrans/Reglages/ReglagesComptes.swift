import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

// Réglages › L'app : les clés TMDB et Claude.

/// EF-42 : clé TMDB, testée avant d'être enregistrée dans le trousseau.
struct ReglagesTMDBView: View {
    @Environment(EtatApp.self) private var etat
    @State private var jeton = ""
    @State private var enTest = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                if etat.tmdb != nil {
                    LabeledContent("Clé TMDB", value: "enregistrée")
                    Button("Supprimer la clé", role: .destructive) {
                        try? etat.supprimerCle()
                        message = nil
                    }
                } else {
                    SecureField("Clé d'API ou jeton d'accès en lecture", text: $jeton)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task { await tester() }
                    } label: {
                        HStack {
                            Text("Enregistrer et tester")
                            if enTest { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(jeton.isEmpty || enTest)
                    Link("Obtenir une clé sur themoviedb.org", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                Text("TMDB fournit les fiches, les affiches et les plateformes. La clé reste dans le trousseau de l'appareil.")
            }
        }
        .pageReglages("TMDB")
    }

    private func tester() async {
        enTest = true
        defer { enTest = false }
        do {
            try await etat.enregistrerCle(jeton)
            jeton = ""
            message = "Clé acceptée par TMDB."
        } catch ErreurTMDB.identifiantsRefuses {
            message = "TMDB refuse cette clé. Vérifie-la sur themoviedb.org, dans Paramètres › API."
        } catch {
            message = Journal.conseil(error) ?? "Le test n'a pas abouti : vérifie la connexion Internet, puis réessaie."
            etat.journal.noter(.tmdb, "La clé TMDB n'a pas pu être testée.", erreur: error)
        }
    }
}

/// EF-27 : clé Claude facultative, pour que « Idées pour ce soir » lise une envie précisée.
struct ReglagesClaudeView: View {
    @Environment(EtatApp.self) private var etat
    @State private var cleClaude = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                if etat.claude != nil {
                    LabeledContent("Clé Claude", value: "enregistrée")
                    Button("Supprimer la clé", role: .destructive) {
                        try? etat.supprimerCleClaude()
                        message = nil
                    }
                } else {
                    SecureField("Clé d'API (sk-ant-…)", text: $cleClaude)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Enregistrer la clé") {
                        do {
                            try etat.enregistrerCleClaude(cleClaude)
                            cleClaude = ""
                            message = "Clé enregistrée dans le trousseau."
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                    .disabled(cleClaude.isEmpty)
                    Link("Créer une clé sur console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Sans clé, « Idées pour ce soir » classe les titres sur l'appareil, selon tes goûts. Avec une clé, Claude lit l'envie que tu précises et choisit parmi les titres disponibles : environ 0,07 $ par demande.")
            }
        }
        .pageReglages("Claude")
    }
}
