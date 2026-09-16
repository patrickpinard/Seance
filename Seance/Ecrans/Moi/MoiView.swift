import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

struct MoiView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink("Réglages") { ReglagesView() }
                    NavigationLink("À propos") { AProposView() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.fond)
            .navigationTitle("Moi")
        }
    }
}

/// EF-42 à EF-45 : clé TMDB, abonnements et chaînes.
struct ReglagesView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query private var abonnements: [Abonnement]
    @Query private var chaines: [Chaine]
    @State private var jeton = ""
    @State private var cleClaude = ""
    @State private var enTest = false
    @State private var message: String?
    @State private var messageClaude: String?
    @State private var catalogue: [FournisseurCatalogue] = []

    var body: some View {
        Form {
            Section {
                if etat.tmdb != nil {
                    LabeledContent("Clé TMDB", value: "enregistrée")
                    Button("Supprimer la clé", role: .destructive) {
                        try? etat.supprimerCle()
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
            } header: {
                Text("TMDB")
            }

            Section {
                if etat.claude != nil {
                    LabeledContent("Clé Claude", value: "enregistrée")
                    Button("Supprimer la clé", role: .destructive) {
                        try? etat.supprimerCleClaude()
                        messageClaude = nil
                    }
                } else {
                    SecureField("Clé d'API (sk-ant-…)", text: $cleClaude)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Enregistrer la clé") {
                        do {
                            try etat.enregistrerCleClaude(cleClaude)
                            cleClaude = ""
                            messageClaude = "Clé enregistrée dans le trousseau."
                        } catch {
                            messageClaude = error.localizedDescription
                        }
                    }
                    .disabled(cleClaude.isEmpty)
                    Link("Créer une clé sur console.anthropic.com",
                         destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                }
                if let messageClaude {
                    Text(messageClaude).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Claude")
            } footer: {
                Text("Sans clé, « Ce soir » classe les titres sur l'iPhone, à partir de tes goûts. Avec une clé, Claude lit ta demande et explique ses choix : environ 0,07 $ par demande.")
            }

            Section("Abonnements en Suisse") {
                if etat.tmdb == nil {
                    Text("Enregistre d'abord la clé TMDB.").foregroundStyle(.secondary)
                } else if catalogue.isEmpty {
                    ProgressView()
                }
                ForEach(catalogue) { fournisseur in
                    Toggle(fournisseur.nom, isOn: liaisonAbonnement(fournisseur))
                }
            }

            Section {
                ForEach(ChaineGuide.tntParDefaut, id: \.id) { chaine in
                    Toggle(chaine.nom, isOn: liaisonChaine(chaine))
                }
            } header: {
                Text("Chaînes TV")
            } footer: {
                Text("Programmes des chaînes françaises : XML TV Fr, projet bénévole, sans garantie.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.fond)
        .navigationTitle("Réglages")
        .task(id: etat.tmdb == nil) { await chargerCatalogue() }
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
            message = "Test impossible : \(error.localizedDescription)"
        }
    }

    private func chargerCatalogue() async {
        guard let client = etat.tmdb else { return }
        let liste = (try? await client.catalogueFournisseurs(.film)) ?? []
        catalogue = liste.sorted { ($0.priorites["CH"] ?? .max) < ($1.priorites["CH"] ?? .max) }
    }

    private func liaisonAbonnement(_ fournisseur: FournisseurCatalogue) -> Binding<Bool> {
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

    private func liaisonChaine(_ chaine: ChaineGuide) -> Binding<Bool> {
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

/// À propos (EF-44) : description de l'app, sources des données et droits d'auteur.
struct AProposView: View {
    private var version: String {
        let infos = Bundle.main.infoDictionary
        let version = infos?["CFBundleShortVersionString"] as? String ?? "1.0"
        let construction = infos?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(construction))"
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
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section("L'application") {
                Text("Séance est ton guide personnel des films et séries d'action. Elle te dit où regarder chaque titre en Suisse : sur tes plateformes, à la télévision ou sur ton NAS, ou comment l'obtenir légalement.")
                Text("Elle suit tes séries épisode par épisode, garde la trace de ce que tu as vu et te prévient des nouvelles saisons, des sorties et des passages à la télé. Chaque soir, elle te propose des idées choisies selon tes goûts, toutes vérifiées dans TMDB.")
                Text("Tes données restent sur ton iPhone. Une sauvegarde régulière dans un fichier les protège.")
            }

            Section("Sources des données") {
                Text("Cette application utilise TMDB et les API de TMDB, mais n'est ni approuvée, ni certifiée, ni validée par TMDB.")
                Text("Disponibilités sur les plateformes : JustWatch.")
                Text("Programmes TV des chaînes françaises : XML TV Fr, projet bénévole.")
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
}
