import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Réglages › E-mail de la semaine : les destinataires (séparés par « ; »), le jour et l'heure, le compte qui envoie,
/// et un bouton d'essai. L'e-mail part de cet appareil, par ton compte de messagerie : Séance n'a pas de serveur.
struct ReglagesLettreView: View {
    /// Les plateformes et les chaînes cochées : ce sont elles qu'on propose de filtrer (6.5).
    @Query(filter: #Predicate<Abonnement> { $0.actif }, sort: \Abonnement.nom) private var abonnements: [Abonnement]
    @Query(filter: #Predicate<Chaine> { $0.active }, sort: \Chaine.nom) private var chaines: [Chaine]
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

    /// Une ligne à cocher, pour les plateformes et les chaînes.
    private func ligneCochee(_ nom: String, choisi: Bool) -> some View {
        HStack {
            Text(nom).foregroundStyle(.primary)
            Spacer()
            Image(systemName: choisi ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(choisi ? Theme.accent : .secondary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func basculerRubrique(_ rubrique: EtatLettre.Rubrique) {
        var choisies = reglages.rubriques ?? Set(EtatLettre.Rubrique.allCases)
        if choisies.contains(rubrique) { choisies.remove(rubrique) } else { choisies.insert(rubrique) }
        reglages.rubriques = choisies
    }

    private func plateformeRetenue(_ identifiant: Int) -> Bool {
        reglages.plateformes?.contains(identifiant) ?? false
    }

    private func basculerPlateforme(_ identifiant: Int) {
        var choisies = reglages.plateformes ?? []
        if choisies.contains(identifiant) { choisies.remove(identifiant) } else { choisies.insert(identifiant) }
        reglages.plateformes = choisies
    }

    private func chaineRetenue(_ nom: String) -> Bool {
        reglages.chaines?.contains(nom) ?? false
    }

    private func basculerChaine(_ nom: String) {
        var choisies = reglages.chaines ?? []
        if choisies.contains(nom) { choisies.remove(nom) } else { choisies.insert(nom) }
        reglages.chaines = choisies
    }

    /// Les jours retenus, l'ancien réglage à un seul jour compris.
    private var joursChoisis: Set<Int> { reglages.joursRetenus }

    /// Coche ou décoche un jour ; il en reste toujours au moins un.
    private func basculerJour(_ numero: Int) {
        var choisis = joursChoisis
        if choisis.contains(numero) {
            guard choisis.count > 1 else { return }
            choisis.remove(numero)
        } else {
            choisis.insert(numero)
        }
        reglages.jours = choisis
        reglages.jour = choisis.min() ?? numero
    }
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

            // Ce que la lettre contient (6.5) : chacun choisit ses rubriques, ses plateformes et ses chaînes.
            Section {
                ForEach(EtatLettre.Rubrique.allCases) { rubrique in
                    Button { basculerRubrique(rubrique) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: rubrique.symbole)
                                .foregroundStyle(reglages.veut(rubrique) ? Theme.accent : .secondary)
                                .frame(width: 26)
                            Text(rubrique.nom).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: reglages.veut(rubrique) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(reglages.veut(rubrique) ? Theme.accent : .secondary)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(rubrique.nom)
                    .accessibilityAddTraits(reglages.veut(rubrique) ? [.isButton, .isSelected] : .isButton)
                }
            } header: {
                Text("Ce que je veux recevoir")
            } footer: {
                Text("Décochée, une rubrique ne paraît pas dans l'e-mail — et s'il n'en reste aucune à dire, l'e-mail ne part pas.")
            }

            if reglages.veut(.nouveautes), !abonnements.isEmpty {
                Section {
                    ForEach(abonnements) { abonnement in
                        Button { basculerPlateforme(abonnement.providerID) } label: {
                            ligneCochee(abonnement.nom, choisi: plateformeRetenue(abonnement.providerID))
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Nouveautés de quelles plateformes")
                } footer: {
                    Text("Rien de coché : toutes celles de tes abonnements.")
                }
            }

            if reglages.veut(.passagesTele), !chaines.isEmpty {
                Section {
                    ForEach(chaines) { chaine in
                        Button { basculerChaine(chaine.nom) } label: {
                            ligneCochee(chaine.nom, choisi: chaineRetenue(chaine.nom))
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Passages sur quelles chaînes")
                } footer: {
                    Text("Rien de coché : toutes tes chaînes.")
                }
            }

            Section {
                // Plusieurs jours possibles (6.5) : la lettre peut partir deux ou trois fois par semaine.
                ForEach(Self.jours, id: \.0) { numero, nom in
                    Button { basculerJour(numero) } label: {
                        HStack {
                            Text(nom).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: joursChoisis.contains(numero) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(joursChoisis.contains(numero) ? Theme.accent : .secondary)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(nom)
                    .accessibilityAddTraits(joursChoisis.contains(numero) ? [.isButton, .isSelected] : .isButton)
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
                Text("Quels jours")
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
