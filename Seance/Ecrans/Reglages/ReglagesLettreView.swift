import SeanceKit
import SwiftData
import SwiftUI

/// Réglages › E-mail de la semaine : les destinataires (séparés par « ; »), le jour et l'heure, le compte qui envoie,
/// et un bouton d'essai. L'e-mail part de cet appareil, par ton compte de messagerie : Séance n'a pas de serveur.
struct ReglagesLettreView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @State private var reglages = EtatLettre.Reglages()
    @State private var motDePasse = ""
    @State private var port = "465"
    @State private var apercu: ApercuLettre?

    private struct ApercuLettre: Identifiable {
        let id = UUID()
        let html: String
    }

    private static let jours = [(2, "Lundi"), (3, "Mardi"), (4, "Mercredi"), (5, "Jeudi"), (6, "Vendredi"), (7, "Samedi"), (1, "Dimanche")]
    private var lettre: EtatLettre { etat.lettre }
    private var adresses: [String] { MessageMail.adresses(reglages.destinataires) }

    var body: some View {
        Form {
            Section {
                Toggle("Recevoir l'e-mail de la semaine", isOn: $reglages.actif).tint(Theme.accent)
                TextField("patrick@exemple.ch ; anne@exemple.ch", text: $reglages.destinataires, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .lineLimit(1...4)
                    .accessibilityIdentifier("lettreDestinataires")
                if !reglages.destinataires.isEmpty {
                    Label(adresses.isEmpty ? "Aucune adresse valable" : Format.pluriel(adresses.count, "destinataire") + " : " + adresses.joined(separator: ", "),
                          systemImage: adresses.isEmpty ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(adresses.isEmpty ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                }
            } header: {
                Text("Destinataires")
            } footer: {
                Text("Plusieurs adresses : sépare-les par un point-virgule. Chaque semaine : les épisodes, sorties et passages à la TV de tes titres, les nouveautés de tes plateformes et tes soirées prévues, sur sept jours.")
            }

            Section {
                Picker("Jour", selection: $reglages.jour) {
                    ForEach(Self.jours, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker("Heure", selection: $reglages.heure) {
                    ForEach(6...22, id: \.self) { Text("\($0) h").tag($0) }
                }
                if reglages.actif, let prochain = lettre.prochainEnvoi {
                    LabeledContent("Prochain envoi") {
                        Text(prochain.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute().locale(Locale(identifier: "fr_CH"))))
                    }
                }
                if let dernier = lettre.dernierEnvoi {
                    LabeledContent("Dernier envoi") { Text(dernier, format: .relative(presentation: .named)) }
                }
            } header: {
                Text("Quand")
            } footer: {
                Text("Séance n'a pas de serveur : l'e-mail part de cet appareil, à sa première ouverture de Séance (ou à son premier réveil en arrière-plan) après ce moment. Ces réglages voyagent vers tes autres appareils par la synchronisation — pas le mot de passe, qui reste dans le trousseau de chacun : seul un appareil où tu l'as saisi peut envoyer, et la date du dernier envoi est partagée pour éviter les doublons.")
            }

            Section {
                TextField("Serveur d'envoi (smtpauths.bluewin.ch)", text: $reglages.compte.serveur)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                TextField("Port", text: $port).keyboardType(.numberPad)
                TextField("Utilisateur", text: $reglages.compte.utilisateur)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                TextField("Adresse d'expédition", text: $reglages.compte.adresse)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                SecureField(lettre.aUnMotDePasse ? "Mot de passe enregistré (saisir pour le changer)" : "Mot de passe", text: $motDePasse)
            } header: {
                Text("Compte qui envoie")
            } footer: {
                Text("Connexion chiffrée, port 465 (Bluewin : smtpauths.bluewin.ch ; Gmail : smtp.gmail.com avec un « mot de passe d'application » ; Infomaniak : mail.infomaniak.com). Les serveurs qui n'acceptent que le port 587, comme iCloud, ne conviennent pas. Le mot de passe reste dans le trousseau de cet appareil.")
            }

            Section {
                Button {
                    enregistrer()
                    Task { await lettre.envoyer(etat: etat, contexte: contexte, essai: true) }
                } label: {
                    HStack {
                        Label("Envoyer un e-mail d'essai", systemImage: "paperplane.fill")
                        if lettre.enCours { Spacer(); ProgressView() }
                    }
                }
                .disabled(lettre.enCours)
                .accessibilityIdentifier("lettreEssai")
                Button {
                    Task { apercu = ApercuLettre(html: await lettre.composer(etat: etat, contexte: contexte, essai: true).html) }
                } label: {
                    Label("Voir l'e-mail de cette semaine", systemImage: "eye")
                }
                if let message = lettre.message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                Text("L'essai part tout de suite, avec le vrai contenu de la semaine, aux destinataires ci-dessus.")
            }
        }
        .pageReglages("E-mail de la semaine")
        .onAppear {
            reglages = lettre.reglages
            port = String(lettre.reglages.compte.port)
        }
        .onDisappear(perform: enregistrer)
        .sheet(item: $apercu) { apercu in
            NavigationStack {
                ApercuHTML(html: apercu.html)
                    .ignoresSafeArea(edges: .bottom)
                    .titreDeFeuille("Aperçu de l'e-mail")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { self.apercu = nil } } }
            }
        }
    }

    private func enregistrer() {
        reglages.compte.port = Int(port) ?? 465
        if reglages.compte.adresse.isEmpty, MessageMail.estUneAdresse(reglages.compte.utilisateur) { reglages.compte.adresse = reglages.compte.utilisateur }
        lettre.enregistrer(reglages, motDePasse: motDePasse)
        motDePasse = ""
    }
}

import WebKit

/// L'e-mail tel que le destinataire le verra.
private struct ApercuHTML: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let vue = WKWebView()
        vue.isOpaque = false
        vue.backgroundColor = .clear
        return vue
    }

    func updateUIView(_ vue: WKWebView, context: Context) {
        vue.loadHTMLString(html, baseURL: nil)
    }
}
