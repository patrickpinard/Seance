import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Sauvegarde et synchronisation (EF-70) : un dossier d'iCloud Drive partagé entre tes appareils, l'envoi direct à un
/// autre appareil (AirDrop), et le fichier à exporter ou importer. L'import ajoute et complète, sans rien effacer.
struct ReglagesSauvegardeView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @State private var document: DocumentSauvegarde?
    @State private var exportOuvert = false
    /// Un seul sélecteur de fichiers pour la page : une sauvegarde à importer, ou le dossier de synchronisation.
    @State private var selection: Selection?
    @State private var message: String?
    /// Le fichier « .seance » prêt à partir par AirDrop.
    @State private var fichierAPartager: URL?

    private enum Selection {
        case sauvegarde, dossier
    }

    var body: some View {
        @Bindable var synchro = etat.synchro
        Form {
            Section {
                if let dossier = etat.synchro.nomDossier {
                    LabeledContent("Dossier", value: dossier)
                    if let derniere = etat.synchro.derniereSynchro {
                        LabeledContent("Dernière synchronisation") {
                            Text(derniere, format: .relative(presentation: .named))
                        }
                    }
                    Toggle("À chaque ouverture de Séance", isOn: $synchro.automatique).tint(Theme.accent)
                    Button {
                        Task { await etat.synchro.synchroniser(etat: etat, contexte: contexte) }
                    } label: {
                        HStack {
                            Label("Synchroniser maintenant", systemImage: "arrow.triangle.2.circlepath")
                            if etat.synchro.enCours { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(etat.synchro.enCours)
                    if let recu = etat.synchro.dernierMessage {
                        Text(recu).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Changer de dossier…") { selection = .dossier }
                    Button("Ne plus synchroniser", role: .destructive) { etat.synchro.oublier() }
                } else {
                    Button { selection = .dossier } label: {
                        Label("Choisir un dossier d'iCloud Drive…", systemImage: "icloud")
                    }
                }
            } header: {
                Text("Synchroniser mes appareils")
            } footer: {
                Text(etat.synchro.estConfiguree
                     ? "Chaque appareil dépose son fichier dans ce dossier et fusionne ceux des autres quand ils ont changé : ce que tu ajoutes, modifies ou supprimes sur l'un arrive sur les autres, le changement le plus récent l'emportant. Choisis le même dossier sur ton iPhone, ton iPad et ton Mac. Le sous-dossier « Sauvegardes datées » garde les cinq derniers états de chaque appareil : de quoi revenir en arrière en important l'un d'eux."
                     : "Crée un dossier « Séance » dans iCloud Drive, puis choisis-le ici sur chacun de tes appareils : iPhone, iPad et Mac se tiennent alors à jour tout seuls, sans compte à créer. N'importe quel dossier de Fichiers partagé entre tes appareils convient aussi.")
            }

            Section {
                if let fichierAPartager {
                    ShareLink(item: fichierAPartager, preview: SharePreview("Sauvegarde de Séance", image: Image(systemName: "externaldrive"))) {
                        Label("Envoyer à un autre appareil…", systemImage: "airplayaudio")
                            .labelStyle(EtiquetteEnvoi())
                    }
                } else {
                    Label("Préparation de la sauvegarde…", systemImage: "hourglass").foregroundStyle(.secondary)
                }
            } header: {
                Text("AirDrop, Messages, Mail")
            } footer: {
                Text("Pour un appareil qui n'est pas sur ton compte Apple, ou sans iCloud Drive : l'autre appareil reçoit un fichier « .seance », propose « Ouvrir avec Séance », et l'import se confirme d'un geste.")
            }

            Section {
                Button {
                    exporter()
                } label: {
                    Label("Exporter une sauvegarde", systemImage: "square.and.arrow.up")
                }
                Button {
                    selection = .sauvegarde
                } label: {
                    Label("Importer une sauvegarde", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Fichier")
            } footer: {
                Text("La sauvegarde contient tes listes, épisodes vus, notes, soirées prévues, acteurs suivis, filtres, goûts, plateformes, chaînes et réglages (prénom, accueil, alertes, adresse du NAS). Jamais une clé ni un mot de passe : la clé TMDB, la clé Claude et le mot de passe du NAS se saisissent sur chaque appareil. L'import ajoute ce qui manque et complète les titres déjà là, sans rien effacer ; ce que tu supprimes sur un appareil n'est pas supprimé sur l'autre.")
            }

            if let message {
                Section {
                    Text(message).font(.footnote)
                }
            }
        }
        .pageReglages("Sauvegarde")
        .task { fichierAPartager = try? ImportSauvegarde.fichierAPartager(contexte: contexte) }
        .fileExporter(isPresented: $exportOuvert, document: document, contentType: .json,
                      defaultFilename: Sauvegarde.nomFichier(pour: .now)) { resultat in
            switch resultat {
            case .success: message = "Sauvegarde enregistrée."
            case .failure(let erreur):
                message = "La sauvegarde n'a pas pu être enregistrée."
                etat.journal.noter(.general, "La sauvegarde n'a pas pu être enregistrée.", erreur: erreur)
            }
        }
        .fileImporter(isPresented: Binding { selection != nil } set: { if !$0 { selection = nil } },
                      allowedContentTypes: selection == .dossier ? [.folder] : [.json, .sauvegardeSeance]) { resultat in
            let choix = selection
            selection = nil
            switch choix {
            case .dossier: choisirDossier(resultat)
            default: importer(resultat)
            }
        }
    }

    private func choisirDossier(_ resultat: Result<URL, any Error>) {
        do {
            try etat.synchro.choisir(try resultat.get())
            message = nil
            Task { await etat.synchro.synchroniser(etat: etat, contexte: contexte) }
        } catch {
            message = "Ce dossier n'a pas pu être retenu. Choisis un dossier d'iCloud Drive ou de Fichiers dans lequel Séance peut écrire."
            etat.journal.noter(.general, "Le dossier de synchronisation n'a pas pu être retenu.", erreur: error)
        }
    }

    private func exporter() {
        do {
            document = DocumentSauvegarde(donnees: try ImportSauvegarde.exporter(contexte: contexte).encoder())
            exportOuvert = true
        } catch {
            message = "La sauvegarde n'a pas pu être préparée."
            etat.journal.noter(.general, "La sauvegarde n'a pas pu être préparée.", erreur: error)
        }
    }

    private func importer(_ resultat: Result<URL, any Error>) {
        do {
            let url = try resultat.get()
            let acces = url.startAccessingSecurityScopedResource()
            defer { if acces { url.stopAccessingSecurityScopedResource() } }
            let bilan = try ImportSauvegarde.importer(try Data(contentsOf: url), etat: etat, contexte: contexte)
            if bilan.estVide {
                message = "Rien de nouveau : tout ce que contient ce fichier est déjà là."
            } else {
                message = "Importé : \(bilan.phrase).\(etat.tmdb == nil ? " Il reste à saisir ta clé TMDB dans Réglages › TMDB : les clés ne voyagent pas dans la sauvegarde." : "")"
            }
        } catch {
            message = "Ce fichier n'a pas pu être importé. Vérifie qu'il s'agit bien d'une sauvegarde de Séance."
            etat.journal.noter(.general, "Une sauvegarde n'a pas pu être importée.", erreur: error)
        }
    }
}

/// Le libellé de l'envoi : l'icône de partage du système, pas celle d'AirPlay.
private struct EtiquetteEnvoi: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label { configuration.title } icon: { Image(systemName: "square.and.arrow.up.on.square") }
    }
}

/// Le fichier JSON d'une sauvegarde, pour le panneau d'enregistrement du système.
struct DocumentSauvegarde: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let donnees: Data

    init(donnees: Data) {
        self.donnees = donnees
    }

    init(configuration: ReadConfiguration) throws {
        donnees = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: donnees)
    }
}
