import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Un nouvel appareil, sans repartir de zéro : trois étapes sur un seul écran — reprendre ses données (dossier de
/// synchronisation ou fichier), saisir sa clé TMDB, redonner le mot de passe du NAS. Les clés et les mots de passe ne
/// voyagent jamais dans une sauvegarde : c'est ici qu'on les redonne.
struct NouvelAppareilView: View {
    /// Appelé quand on touche « Terminé ».
    let terminer: () -> Void
    /// En page dans les Réglages (8.2.3), plutôt qu'en feuille.
    var enPage = false

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @State private var selection: Selection?
    @State private var messageDonnees: String?
    @State private var repriseEnCours = false
    @State private var jeton = ""
    @State private var testCle = false
    @State private var messageCle: String?
    @State private var motDePasseNAS = ""
    @State private var messageNAS: String?
    @State private var messageCode: String?

    private enum Selection { case dossier, fichier }

    private var donneesReprises: Bool {
        etat.synchro.nomDossier != nil || messageDonnees != nil
    }

    var body: some View {
        PileSiFeuille(enPage: enPage) {
            Form {
                Section {
                    if let messageCode {
                        Label(messageCode, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        ReceptionParCode { messageCode = $0 }
                    }
                } header: {
                    Text("Le plus simple")
                } footer: {
                    Text("Tu as Séance sur un autre appareil, à côté de toi ? Il envoie tout d'un coup — données, clé TMDB et NAS — par le Wi-Fi de la maison. Sinon, fais les trois étapes ci-dessous.")
                }
                Section {
                    if let dossier = etat.synchro.nomDossier {
                        Label("Synchronisé avec le dossier « \(dossier) »", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button { selection = .dossier } label: {
                            Label("Choisir le dossier iCloud Drive de Séance…", systemImage: "icloud")
                        }
                        Button { selection = .fichier } label: {
                            Label("Importer un fichier de sauvegarde…", systemImage: "square.and.arrow.down")
                        }
                    }
                    if repriseEnCours {
                        HStack { Text("Reprise de tes données…"); Spacer(); ProgressView() }
                    }
                    if let messageDonnees {
                        Text(messageDonnees).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    etape(1, "Tes données", faite: donneesReprises)
                } footer: {
                    Text("Le dossier est celui que tu as choisi sur ton autre appareil (Réglages › Sauvegarde) : tes appareils resteront ensuite à jour tout seuls. Sans dossier, envoie-toi une sauvegarde par AirDrop depuis l'autre appareil : elle s'ouvre directement dans Séance.")
                }

                Section {
                    if etat.tmdb != nil {
                        Label("Clé TMDB enregistrée", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        SecureField("Clé d'API ou jeton d'accès en lecture", text: $jeton)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            Task { await enregistrerCle() }
                        } label: {
                            HStack { Text("Enregistrer et tester"); if testCle { Spacer(); ProgressView() } }
                        }
                        .disabled(jeton.isEmpty || testCle)
                    }
                    if let messageCle {
                        Text(messageCle).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    etape(2, "Ta clé TMDB", faite: etat.tmdb != nil)
                } footer: {
                    Text("La même que sur ton autre appareil : elle reste dans le trousseau de chacun, et ne voyage dans aucune sauvegarde. Tu la retrouves sur themoviedb.org, dans Paramètres › API.")
                }

                if etat.nas.reglages.estComplet {
                    Section {
                        if etat.nas.estConfigure {
                            Label("NAS « \(etat.nas.reglages.hote) » prêt", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            SecureField("Mot de passe de \(etat.nas.reglages.utilisateur)", text: $motDePasseNAS)
                            Button("Enregistrer le mot de passe") {
                                do {
                                    try etat.nas.enregistrerMotDePasse(motDePasseNAS)
                                    motDePasseNAS = ""
                                    messageNAS = "Enregistré. L'analyse du NAS se lancera toute seule."
                                } catch {
                                    messageNAS = "Le mot de passe n'a pas pu être enregistré."
                                }
                            }
                            .disabled(motDePasseNAS.isEmpty)
                        }
                        if let messageNAS {
                            Text(messageNAS).font(.footnote).foregroundStyle(.secondary)
                        }
                    } header: {
                        etape(3, "Ton NAS", faite: etat.nas.estConfigure)
                    } footer: {
                        Text("L'adresse et les dossiers sont arrivés avec tes données ; il ne manque que le mot de passe.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.fond)
            .titre("Nouvel appareil", enPage: enPage)
            .toolbar {
                if !enPage {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Terminé") { terminer() }
                    }
                }
            }
            .fileImporter(isPresented: Binding { selection != nil } set: { if !$0 { selection = nil } },
                          allowedContentTypes: selection == .dossier ? [.folder] : [.json, .sauvegardeSeance]) { resultat in
                let choix = selection
                selection = nil
                Task { await reprendre(resultat, dossier: choix == .dossier) }
            }
        }
        .presentationBackground(Theme.fond)
    }

    private func etape(_ numero: Int, _ titre: String, faite: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: faite ? "checkmark.circle.fill" : "\(numero).circle.fill")
                .foregroundStyle(faite ? AnyShapeStyle(Color.green) : AnyShapeStyle(Theme.accentClair))
            Text(titre)
        }
        .font(.headline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Étape \(numero) : \(titre)\(faite ? ", faite" : "")")
    }

    private func reprendre(_ resultat: Result<URL, any Error>, dossier: Bool) async {
        repriseEnCours = true
        defer { repriseEnCours = false }
        do {
            let url = try resultat.get()
            if dossier {
                try etat.synchro.choisir(url)
                await etat.synchro.synchroniser(etat: etat, contexte: contexte)
                messageDonnees = etat.synchro.dernierMessage ?? "Dossier retenu."
            } else {
                let acces = url.startAccessingSecurityScopedResource()
                defer { if acces { url.stopAccessingSecurityScopedResource() } }
                let bilan = try ImportSauvegarde.importer(try Data(contentsOf: url), etat: etat, contexte: contexte)
                messageDonnees = bilan.estVide ? "Rien de nouveau dans ce fichier." : "Importé : \(bilan.phrase)."
            }
        } catch {
            messageDonnees = "Cela n'a pas abouti. Vérifie qu'il s'agit bien du dossier, ou d'une sauvegarde, de Séance."
            etat.journal.noter(.general, "La reprise des données sur un nouvel appareil n'a pas abouti.", erreur: error)
        }
    }

    private func enregistrerCle() async {
        testCle = true
        defer { testCle = false }
        do {
            try await etat.enregistrerCle(jeton)
            jeton = ""
            messageCle = nil
        } catch ErreurTMDB.identifiantsRefuses {
            messageCle = "TMDB refuse cette clé. Vérifie-la sur themoviedb.org, dans Paramètres › API."
        } catch {
            messageCle = Journal.conseil(error) ?? "Le test n'a pas abouti : vérifie la connexion Internet, puis réessaie."
        }
    }
}
