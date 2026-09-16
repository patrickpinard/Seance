import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Réglages classés par thème, comme l'app Réglages d'iOS : une ligne par catégorie, avec son état
/// en un coup d'œil, et une page par catégorie.
struct MoiView: View {
    @Environment(EtatApp.self) private var etat
    @Query(filter: #Predicate<Abonnement> { $0.actif }) private var abonnements: [Abonnement]
    @Query(filter: #Predicate<Chaine> { $0.active }) private var chaines: [Chaine]

    var body: some View {
        NavigationStack {
            List {
                Section("Comptes") {
                    NavigationLink { ReglagesTMDBView() } label: {
                        LigneReglage(titre: "TMDB", symbole: "film.stack", couleur: .teal,
                                     valeur: etat.tmdb == nil ? "À saisir" : "Connecté")
                    }
                    NavigationLink { ReglagesClaudeView() } label: {
                        LigneReglage(titre: "Claude", symbole: "sparkles", couleur: .orange,
                                     valeur: etat.claude == nil ? "Facultatif" : "Connecté")
                    }
                }

                Section("Où regarder") {
                    NavigationLink { ReglagesPlateformesView() } label: {
                        LigneReglage(titre: "Plateformes", symbole: "play.rectangle.on.rectangle.fill", couleur: .red,
                                     valeur: abonnements.isEmpty ? "Aucune" : "\(abonnements.count)")
                    }
                    NavigationLink { ReglagesTeleView() } label: {
                        LigneReglage(titre: "Télévision", symbole: "tv.fill", couleur: .blue,
                                     valeur: chaines.isEmpty ? "Aucune chaîne" : "\(chaines.count) chaînes")
                    }
                    NavigationLink { ReglagesNASView() } label: {
                        LigneReglage(titre: "NAS", symbole: "externaldrive.fill", couleur: .green,
                                     valeur: etat.nas.estConfigure ? "Configuré" : "À configurer")
                    }
                }

                Section("Me prévenir") {
                    NavigationLink { ReglagesAlertesView() } label: {
                        LigneReglage(titre: "Alertes", symbole: "bell.badge.fill", couleur: .red, valeur: libelleAlertes)
                    }
                }

                Section("Mes données") {
                    NavigationLink { ReglagesSauvegardeView() } label: {
                        LigneReglage(titre: "Sauvegarde", symbole: "externaldrive.badge.icloud", couleur: .indigo, valeur: nil)
                    }
                }

                Section {
                    NavigationLink { AProposView() } label: {
                        LigneReglage(titre: "À propos", symbole: "info", couleur: .gray, valeur: nil)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.fond)
            .navigationTitle("Moi")
            .task { await etat.alertes.actualiserAutorisation() }
        }
    }

    private var libelleAlertes: String {
        switch etat.alertes.autorisation {
        case .authorized, .provisional, .ephemeral: "Activées"
        case .denied: "Désactivées"
        default: "À activer"
        }
    }
}

/// Ligne de catégorie : pastille colorée, titre et état courant à droite.
private struct LigneReglage: View {
    let titre: String
    let symbole: String
    let couleur: Color
    let valeur: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbole)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(couleur.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(titre)
            Spacer()
            if let valeur {
                Text(valeur).foregroundStyle(.secondary)
            }
        }
    }
}

/// Mise en forme commune des pages de réglages.
extension View {
    func pageReglages(_ titre: String) -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.fond)
            .navigationTitle(titre)
            .navigationBarTitleDisplayMode(.inline)
    }
}

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

/// EF-27 : clé Claude facultative.
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
                    Link("Créer une clé sur console.anthropic.com",
                         destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Sans clé, « Ce soir » classe les titres sur l'appareil, à partir de tes goûts. Avec une clé, Claude lit ta demande et explique ses choix : environ 0,07 $ par demande.")
            }
        }
        .pageReglages("Claude")
    }
}

/// EF-43 : plateformes auxquelles Patrick est abonné, parmi celles que TMDB connaît en Suisse.
struct ReglagesPlateformesView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query private var abonnements: [Abonnement]
    @State private var catalogue: [FournisseurCatalogue] = []

    var body: some View {
        Form {
            Section {
                if etat.tmdb == nil {
                    Text("Enregistre d'abord la clé TMDB.").foregroundStyle(.secondary)
                } else if catalogue.isEmpty {
                    ProgressView()
                }
                ForEach(catalogue) { fournisseur in
                    Toggle(fournisseur.nom, isOn: liaison(fournisseur))
                }
            } footer: {
                Text("Disponibilités en Suisse fournies par JustWatch, via TMDB.")
            }
        }
        .pageReglages("Plateformes")
        .task(id: etat.tmdb == nil) { await charger() }
    }

    private func charger() async {
        guard let client = etat.tmdb else { return }
        let liste = (try? await client.catalogueFournisseurs(.film)) ?? []
        catalogue = liste.sorted { ($0.priorites["CH"] ?? .max) < ($1.priorites["CH"] ?? .max) }
    }

    private func liaison(_ fournisseur: FournisseurCatalogue) -> Binding<Bool> {
        Binding {
            abonnements.contains { $0.providerID == fournisseur.id && $0.actif }
        } set: { actif in
            if let existant = abonnements.first(where: { $0.providerID == fournisseur.id }) {
                existant.actif = actif
            } else if actif {
                contexte.insert(Abonnement(providerID: fournisseur.id, nom: fournisseur.nom, cheminLogo: fournisseur.cheminLogo))
            }
            try? contexte.save()
        }
    }
}

/// EF-45 à EF-51 : chaînes reçues et lecture du guide.
struct ReglagesTeleView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query private var chaines: [Chaine]
    @State private var nonReconnusVisibles = false

    var body: some View {
        Form {
            Section {
                if etat.teleEnCours {
                    HStack {
                        Text("Lecture des programmes…")
                        Spacer()
                        ProgressView()
                    }
                } else if let derniere = etat.derniereLectureTele {
                    LabeledContent("Dernière lecture") {
                        Text(derniere, format: .relative(presentation: .named))
                    }
                }
                if let rapport = etat.rapportTele {
                    LabeledContent("Films reconnus", value: "\(rapport.filmsRattaches) sur \(rapport.filmsLus)")
                    LabeledContent("Diffusions à venir", value: "\(rapport.diffusionsEnregistrees)")
                    if !rapport.filmsNonRattaches.isEmpty {
                        DisclosureGroup("Films non reconnus (\(rapport.filmsNonRattaches.count))", isExpanded: $nonReconnusVisibles) {
                            ForEach(rapport.filmsNonRattaches, id: \.self) { titre in
                                Text(titre).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let erreur = etat.erreurTele {
                    Label(erreur, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Actualiser maintenant") {
                    Task { await etat.actualiserTele(contexte: contexte, force: true) }
                }
                .disabled(etat.teleEnCours || etat.tmdb == nil)
            } header: {
                Text("Guide des programmes")
            } footer: {
                Text("Le guide est relu toutes les 12 heures et dès que tu changes de chaînes. Un film n'apparaît que s'il est reconnu dans TMDB sans hésitation.")
            }

            Section {
                ForEach(ChaineGuide.suisses) { chaine in
                    Toggle(chaine.nom, isOn: liaison(chaine))
                }
            } header: {
                Text("Suisse")
            } footer: {
                Text("Avec la RTS, Séance télécharge le guide complet (18 Mo) au lieu du guide TNT (1 Mo).")
            }

            Section {
                ForEach(ChaineGuide.tntParDefaut) { chaine in
                    Toggle(chaine.nom, isOn: liaison(chaine))
                }
            } header: {
                Text("France")
            } footer: {
                Text("Programmes : XML TV Fr, projet bénévole, sans garantie.")
            }
        }
        .pageReglages("Télévision")
        // Les chaînes ont pu changer : le guide est relu en quittant la page, si nécessaire.
        .onDisappear {
            Task { await etat.actualiserTele(contexte: contexte) }
        }
    }

    private func liaison(_ chaine: ChaineGuide) -> Binding<Bool> {
        Binding {
            chaines.contains { $0.identifiantGuide == chaine.id && $0.active }
        } set: { active in
            if let existante = chaines.first(where: { $0.identifiantGuide == chaine.id }) {
                existante.active = active
            } else if active {
                contexte.insert(Chaine(identifiantGuide: chaine.id, nom: chaine.nom, source: .xmltvfr))
            }
            try? contexte.save()
        }
    }
}

/// À propos (EF-44) : l'application, ses sources et les droits d'auteur, et l'historique des versions.
struct AProposView: View {
    enum Onglet: String, CaseIterable, Identifiable {
        case application = "Séance"
        case versions = "Versions"
        case journal = "Journal"

        var id: String { rawValue }
    }

    @State private var onglet = Onglet.application

    private var numeroVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.9"
    }

    private var version: String {
        let construction = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(numeroVersion) (\(construction))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .accessibilityHidden(true)
                    Text("Séance").font(.title.weight(.heavy))
                    Text(version).font(.footnote).foregroundStyle(.secondary)
                    Picker("Onglet", selection: $onglet) {
                        ForEach(Onglet.allCases) { onglet in
                            Text(onglet.rawValue).tag(onglet)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            switch onglet {
            case .application:
                application
            case .versions:
                ListeVersions(versionInstallee: numeroVersion)
            case .journal:
                SectionsJournal()
            }

            Section {
                Text("© 2026 Patrick Pinard. Tous droits réservés.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.fond)
        .navigationTitle("À propos")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var application: some View {
        Section("L'application") {
            Text("Séance est ton guide personnel des films et séries d'action. Elle te dit où regarder chaque titre en Suisse : sur tes plateformes, à la télévision ou sur ton NAS, ou comment l'obtenir légalement.")
            Text("Elle suit tes séries épisode par épisode, garde la trace de ce que tu as vu et te prévient des nouvelles saisons, des sorties et des passages à la télé. Chaque soir, elle te propose des idées choisies selon tes goûts, toutes vérifiées dans TMDB.")
            Text("Tes données restent sur ton appareil. Une sauvegarde dans un fichier, depuis Moi › Sauvegarde, les protège et permet de les reprendre sur un autre appareil.")
        }

        Section("Sources des données") {
            Text("Cette application utilise TMDB et les API de TMDB, mais n'est ni approuvée, ni certifiée, ni validée par TMDB.")
            Text("Disponibilités sur les plateformes : JustWatch.")
            Text("Programmes TV de la RTS et des chaînes françaises : XML TV Fr, projet bénévole.")
            Text("Accès au NAS : AMSMB2 et libsmb2, sous licence LGPL.")
        }
    }
}
