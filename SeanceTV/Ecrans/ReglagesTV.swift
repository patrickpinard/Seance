import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// La mise en route sur la TV (EF-145) : la clé TMDB et le NAS, saisis une fois — le clavier de l'iPhone se propose
/// tout seul. Tout le reste se règle sur l'iPhone, l'iPad ou le Mac.
struct ReglagesTV: View {
    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte

    @State private var cle = ""
    @State private var etatCle: String?
    @State private var verification = false

    @State private var hote = ""
    @State private var partage = ""
    @State private var dossiers = ""
    @State private var utilisateur = ""
    @State private var motDePasse = ""
    @State private var etatNAS: String?
    @State private var test = false
    @State private var configuration = false

    var body: some View {
        Form {
            Section {
                etatLigne("Clé TMDB", pret: etat.tmdb != nil, detail: etat.tmdb != nil ? "Enregistrée dans le trousseau de cette Apple TV" : "À saisir : affiches, fiches et plateformes en dépendent")
                etatLigne("NAS", pret: etat.nasPret, detail: etat.nasPret ? "\(etat.nas.hote) · partage « \(etat.nas.partage) »" : "À configurer pour lire tes films et tes séries")
                Button { configuration = true } label: {
                    Label("Configurer depuis mon iPhone", systemImage: "iphone.and.arrow.forward")
                }
            } header: {
                Text("État de Séance sur cette TV")
            } footer: {
                Text("Le plus simple : la TV affiche un code, ton iPhone envoie la clé, le NAS et tes listes. Sinon, saisis-les ci-dessous.")
            }

            Section {
                SecureField("Clé d'API ou jeton de lecture TMDB", text: $cle)
                Button(verification ? "Vérification…" : "Enregistrer et tester") { enregistrerCle() }
                    .disabled(cle.isEmpty || verification)
                if let etatCle { Text(etatCle).foregroundStyle(.secondary) }
            } header: {
                Text("Clé TMDB")
            } footer: {
                Text("La même que sur ton iPhone. Elle reste dans le trousseau de cette Apple TV et ne voyage dans aucun fichier. Tu la retrouves sur themoviedb.org, dans Paramètres › API.")
            }

            Section {
                TextField("Adresse du NAS (192.168.1.220)", text: $hote)
                TextField("Partage (Films)", text: $partage)
                TextField("Dossiers, séparés par des virgules", text: $dossiers)
                TextField("Compte", text: $utilisateur)
                SecureField(etat.motDePasseNAS ? "Mot de passe (déjà enregistré)" : "Mot de passe", text: $motDePasse)
                Button(test ? "Connexion au NAS…" : "Enregistrer, tester et lire le NAS") { enregistrerNAS() }
                    .disabled(test || hote.isEmpty || partage.isEmpty || utilisateur.isEmpty)
                if let etatNAS { Text(etatNAS).foregroundStyle(.secondary) }
                if etat.analyseEnCours { Label("Lecture de la bibliothèque…", systemImage: "arrow.triangle.2.circlepath") }
                if let rapport = etat.rapport {
                    Text("\(rapport.filmsReconnus) films et \(rapport.seriesReconnues) séries reconnus, sur \(rapport.videosLues) vidéos lues.").foregroundStyle(.secondary)
                }
            } header: {
                Text("NAS")
            } footer: {
                Text("Pour lire avec Infuse, ajoute aussi ce partage dans Infuse sur cette Apple TV : Séance lui demande d'ouvrir le titre dans sa bibliothèque.")
            }

            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                Text("Ce produit utilise l'API TMDB mais n'est ni approuvé ni certifié par TMDB. Disponibilités en Suisse fournies par JustWatch, via TMDB.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("À propos")
            }
        }
        .fullScreenCover(isPresented: $configuration, onDismiss: relire) { ConfigurationTV() }
        .onAppear {
            hote = etat.nas.hote
            partage = etat.nas.partage
            dossiers = etat.nas.dossiers.joined(separator: ", ")
            utilisateur = etat.nas.utilisateur
        }
    }

    /// Après une configuration reçue, les champs montrent ce qui est arrivé.
    private func relire() {
        hote = etat.nas.hote
        partage = etat.nas.partage
        dossiers = etat.nas.dossiers.joined(separator: ", ")
        utilisateur = etat.nas.utilisateur
    }

    private func etatLigne(_ titre: String, pret: Bool, detail: String) -> some View {
        HStack(spacing: 20) {
            Image(systemName: pret ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(pret ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(titre)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func enregistrerCle() {
        verification = true
        Task {
            let erreur = await etat.enregistrerCleTMDB(cle)
            verification = false
            etatCle = erreur ?? "Clé acceptée par TMDB et enregistrée."
            if erreur == nil { cle = "" }
        }
    }

    private func enregistrerNAS() {
        let liste = dossiers.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        etat.enregistrerNAS(ReglagesNAS(hote: hote.trimmingCharacters(in: .whitespaces), partage: partage.trimmingCharacters(in: .whitespaces),
                                        dossiers: liste, utilisateur: utilisateur.trimmingCharacters(in: .whitespaces)), motDePasse: motDePasse)
        motDePasse = ""
        test = true
        Task {
            switch await etat.testerNAS() {
            case .reussi(let comptes):
                let total = comptes.values.reduce(0, +)
                etatNAS = "Connexion réussie : \(total) vidéos dans \(comptes.count) dossier\(comptes.count > 1 ? "s" : "")."
                test = false
                await etat.analyserNAS(contexte: contexte)
            case .echec(let message):
                etatNAS = message
                test = false
            }
        }
    }
}
