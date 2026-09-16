import SeanceKit
import SeanceNAS
import SwiftData
import SwiftUI

/// Réglages du NAS (EF-71, EF-86, EF-87) : connexion SMB, dossiers analysés et app de lecture.
struct ReglagesNASView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @State private var hote = ""
    @State private var partage = ""
    @State private var utilisateur = ""
    @State private var dossiers = ""
    @State private var motDePasse = ""
    @State private var enTest = false
    @State private var resultatTest: String?
    @State private var nonReconnuesVisibles = false

    var body: some View {
        Form {
            Section {
                champ("Adresse", "192.168.1.220", texte: $hote, clavier: .URL)
                champ("Partage", "Films", texte: $partage)
                champ("Utilisateur", "admin", texte: $utilisateur)
                if etat.nas.motDePasseEnregistre {
                    LabeledContent("Mot de passe", value: "enregistré")
                    Button("Supprimer le mot de passe", role: .destructive) {
                        try? etat.nas.supprimerMotDePasse()
                        resultatTest = nil
                    }
                } else {
                    SecureField("Mot de passe", text: $motDePasse)
                        .textContentType(.password)
                        .submitLabel(.done)
                }
            } header: {
                Text("Connexion SMB")
            } footer: {
                Text("Le mot de passe reste dans le trousseau de l'iPhone. Il n'est ni sauvegardé ni envoyé ailleurs qu'au NAS et à l'app de lecture.")
            }

            Section {
                TextField("Films, NEW, Séries", text: $dossiers)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
            } header: {
                Text("Dossiers analysés")
            } footer: {
                Text("Séparés par des virgules. Seuls ces dossiers du partage sont lus.")
            }

            Section {
                Button {
                    Task { await enregistrerEtTester() }
                } label: {
                    HStack {
                        Text("Enregistrer et tester la connexion")
                        if enTest { Spacer(); ProgressView() }
                    }
                }
                .disabled(enTest || hote.isEmpty || partage.isEmpty || utilisateur.isEmpty
                          || (motDePasse.isEmpty && !etat.nas.motDePasseEnregistre))
                if let resultatTest {
                    Text(resultatTest).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section {
                if etat.nas.enCours {
                    HStack {
                        Text("Analyse en cours…")
                        Spacer()
                        ProgressView()
                    }
                } else if let date = etat.nas.derniereAnalyse {
                    LabeledContent("Dernière analyse") {
                        Text(date, format: .relative(presentation: .named))
                    }
                }
                if let rapport = etat.nas.rapport {
                    LabeledContent("Vidéos lues", value: "\(rapport.videosLues)")
                    LabeledContent("Reconnues dans TMDB", value: "\(rapport.reconnues) sur \(rapport.videosRetenues)")
                    if rapport.doublons > 0 {
                        LabeledContent("Copies en double", value: "\(rapport.doublons)")
                    }
                    if !rapport.nonReconnues.isEmpty {
                        DisclosureGroup("Non reconnues (\(rapport.nonReconnues.count))", isExpanded: $nonReconnuesVisibles) {
                            ForEach(rapport.nonReconnues, id: \.self) { chemin in
                                Text(chemin).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let erreur = etat.nas.erreur {
                    Label(erreur, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Analyser maintenant") {
                    Task { await etat.nas.analyser(contexte: contexte, tmdb: etat.tmdb) }
                }
                .disabled(etat.nas.enCours || !etat.nas.estConfigure || etat.tmdb == nil)
            } header: {
                Text("Bibliothèque")
            } footer: {
                Text("L'analyse lit les noms de fichiers et les rattache à TMDB. Elle se relance seule une fois par jour.")
            }

            Section {
                Picker("App de lecture", selection: Binding { etat.nas.lecteur } set: { etat.nas.choisir($0) }) {
                    ForEach(LecteurVideo.allCases) { lecteur in
                        Text(lecteur.nom).tag(lecteur)
                    }
                }
            } header: {
                Text("Lecture")
            } footer: {
                Text("Infuse ou VLC lisent la vidéo directement sur le NAS, sans la copier sur l'iPhone.")
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.fond)
        .navigationTitle("NAS")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: charger)
    }

    private func champ(_ libelle: String, _ exemple: String, texte: Binding<String>, clavier: UIKeyboardType = .default) -> some View {
        LabeledContent(libelle) {
            TextField(exemple, text: texte)
                .multilineTextAlignment(.trailing)
                .keyboardType(clavier)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
        }
    }

    private func charger() {
        let reglages = etat.nas.reglages
        hote = reglages.hote
        partage = reglages.partage
        utilisateur = reglages.utilisateur
        dossiers = reglages.dossiers.joined(separator: ", ")
    }

    private func enregistrerEtTester() async {
        let liste = dossiers.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        etat.nas.enregistrer(ReglagesNAS(
            hote: hote.trimmingCharacters(in: .whitespaces), partage: partage.trimmingCharacters(in: .whitespaces),
            dossiers: liste, utilisateur: utilisateur.trimmingCharacters(in: .whitespaces)
        ))
        do {
            try etat.nas.enregistrerMotDePasse(motDePasse)
            motDePasse = ""
        } catch {
            resultatTest = "Mot de passe non enregistré : \(error.localizedDescription)"
            return
        }

        enTest = true
        defer { enTest = false }
        do {
            let comptes = try await etat.nas.tester()
            let detail = liste.map { "\($0) : \(comptes[$0] ?? 0) éléments" }.joined(separator: ", ")
            resultatTest = "Connexion réussie. \(detail)."
            if etat.nas.derniereAnalyse == nil {
                await etat.nas.analyser(contexte: contexte, tmdb: etat.tmdb)
            }
        } catch {
            resultatTest = ErreurNAS.message(error)
        }
    }
}
