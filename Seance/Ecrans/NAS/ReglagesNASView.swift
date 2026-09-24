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
    /// Les dossiers trouvés sur le partage (6.4) : on les coche au lieu de les écrire.
    @State private var dossiersDuPartage: [String] = []
    @State private var lectureDesDossiers = false
    @State private var motDePasse = ""
    @State private var enTest = false
    @State private var resultatTest: String?
    @State private var doublonsVisibles = false
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
                Text("Le mot de passe reste dans le trousseau de l'appareil. Il n'est ni sauvegardé ni envoyé ailleurs qu'au NAS et à l'app de lecture.")
            }

            Section {
                // Cochés plutôt qu'écrits (6.4) : Séance connaît déjà les dossiers du partage.
                if !dossiersDuPartage.isEmpty {
                    let choisis = Set(dossiersChoisis)
                    ForEach(dossiersDuPartage, id: \.self) { nom in
                        Button { basculer(nom) } label: {
                            HStack {
                                Text(nom).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: choisis.contains(nom) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(choisis.contains(nom) ? Theme.accent : .secondary)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(nom)
                        .accessibilityAddTraits(choisis.contains(nom) ? [.isButton, .isSelected] : .isButton)
                    }
                } else {
                    TextField("Films, NEW, Séries", text: $dossiers)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                    Button {
                        Task { await lireLesDossiers() }
                    } label: {
                        HStack {
                            Text(lectureDesDossiers ? "Lecture du partage…" : "Voir les dossiers du partage")
                            if lectureDesDossiers { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(lectureDesDossiers || hote.isEmpty || partage.isEmpty)
                }
            } header: {
                Text("Dossiers analysés")
            } footer: {
                Text(dossiersDuPartage.isEmpty
                     ? "Séparés par des virgules. Seuls ces dossiers du partage sont lus."
                     : "Seuls les dossiers cochés sont lus.")
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
                if etat.nas.derniereAnalyse != nil, !etat.nas.analyseAJour, !etat.nas.enCours {
                    Label("Réglages modifiés : relance l'analyse pour mettre la bibliothèque à jour.", systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if let rapport = etat.nas.rapport {
                    LabeledContent("Vidéos lues", value: "\(rapport.videosLues)")
                    ForEach(rapport.videosParDossier.sorted(by: { $0.key < $1.key }), id: \.key) { dossier, nombre in
                        LabeledContent("   \(dossier)", value: "\(nombre) vidéo\(nombre > 1 ? "s" : "")")
                            .font(.footnote)
                    }
                    LabeledContent("Films reconnus", value: "\(rapport.filmsReconnus)")
                    LabeledContent("Séries reconnues", value: "\(rapport.seriesReconnues)")
                    LabeledContent("Vidéos reconnues", value: "\(rapport.reconnues) sur \(rapport.videosRetenues)")
                    if !rapport.copiesEnDouble.isEmpty {
                        DisclosureGroup("Copies en double (\(rapport.doublons))", isExpanded: $doublonsVisibles) {
                            ForEach(rapport.copiesEnDouble, id: \.gardee.chemin) { doublon in
                                CopiesEnDouble(doublon: doublon)
                            }
                            let recuperable = rapport.copiesEnDouble.flatMap(\.ecartees).reduce(Int64(0)) { $0 + $1.taille }
                            Text("Séance garde la meilleure qualité, puis le fichier le plus lourd. Supprimer les autres copies libérerait \(ByteCountFormatter.string(fromByteCount: recuperable, countStyle: .file)) sur le NAS.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
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
                NavigationLink(value: DestinationReglage.lecture) {
                    LabeledContent("App de lecture", value: etat.nas.lecteur.nom)
                }
            } footer: {
                Text("Infuse ou VLC lisent la vidéo directement sur le NAS, sans la copier. Le choix et ce que chaque app demande sont dans Réglages › Lecture.")
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .pageReglages("NAS")
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

    /// Les dossiers retenus, qu'ils viennent des cases ou du champ.
    private var dossiersChoisis: [String] {
        dossiers.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func basculer(_ nom: String) {
        var liste = dossiersChoisis
        if let rang = liste.firstIndex(of: nom) { liste.remove(at: rang) } else { liste.append(nom) }
        dossiers = liste.joined(separator: ", ")
    }

    private func lireLesDossiers() async {
        lectureDesDossiers = true
        defer { lectureDesDossiers = false }
        enregistrerSansTester()
        dossiersDuPartage = (try? await etat.nas.dossiersDuPartage()) ?? []
        if dossiersDuPartage.isEmpty { resultatTest = "Aucun dossier lisible à la racine du partage." }
    }

    /// Enregistre la connexion sans rien tester : il faut qu'elle soit connue pour lire les dossiers du partage.
    private func enregistrerSansTester() {
        etat.nas.enregistrer(ReglagesNAS(
            hote: hote.trimmingCharacters(in: .whitespaces), partage: partage.trimmingCharacters(in: .whitespaces),
            dossiers: dossiersChoisis, utilisateur: utilisateur.trimmingCharacters(in: .whitespaces)
        ))
        if !motDePasse.isEmpty {
            try? etat.nas.enregistrerMotDePasse(motDePasse)
            motDePasse = ""
        }
    }

    private func enregistrerEtTester() async {
        let liste = dossiersChoisis
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
            // Nouveaux dossiers, autre partage : la bibliothèque est relue aussitôt.
            if !etat.nas.analyseAJour {
                await etat.nas.analyser(contexte: contexte, tmdb: etat.tmdb)
            }
        } catch {
            resultatTest = ErreurNAS.message(error)
            etat.journal.noter(.nas, EtatNAS.injoignable(error) ? "Le NAS n'est pas joignable." : "Le test de connexion au NAS a échoué.",
                               erreur: error, conseil: ErreurNAS.message(error))
        }
    }
}

/// Un film ou un épisode en plusieurs copies : celle que Séance lit, puis celles qu'elle ignore.
private struct CopiesEnDouble: View {
    let doublon: DoublonNAS

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ligne(doublon.gardee, gardee: true)
            ForEach(doublon.ecartees, id: \.chemin) { copie in
                ligne(copie, gardee: false)
            }
        }
        .padding(.vertical, 2)
    }

    private func ligne(_ fichier: FichierDistant, gardee: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: gardee ? "checkmark.circle.fill" : "doc.on.doc")
                .foregroundStyle(gardee ? Theme.accent : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(fichier.chemin).font(.footnote.weight(gardee ? .semibold : .regular))
                Text("\(gardee ? "Lue par Séance" : "Ignorée") · \(ByteCountFormatter.string(fromByteCount: fichier.taille, countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
