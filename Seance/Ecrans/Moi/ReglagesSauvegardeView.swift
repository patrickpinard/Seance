import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Sauvegarde dans un fichier (EF-70) : exporter pour protéger ses données, importer pour les reprendre
/// sur un autre appareil. L'import ajoute ce qui manque sans rien effacer.
struct ReglagesSauvegardeView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @State private var document: DocumentSauvegarde?
    @State private var exportOuvert = false
    @State private var importOuvert = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Button {
                    exporter()
                } label: {
                    Label("Exporter une sauvegarde", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("Un fichier avec tes listes, épisodes vus, notes, alertes, filtres, plateformes et chaînes. Il ne contient ni clé ni mot de passe.")
            }

            Section {
                Button {
                    importOuvert = true
                } label: {
                    Label("Importer une sauvegarde", systemImage: "square.and.arrow.down")
                }
            } footer: {
                Text("L'import ajoute ce qui manque, sans rien effacer ni remplacer. Pratique pour retrouver tes listes sur le Mac ou sur un autre iPhone.")
            }

            if let message {
                Section {
                    Text(message).font(.footnote)
                }
            }
        }
        .pageReglages("Sauvegarde")
        .fileExporter(isPresented: $exportOuvert, document: document, contentType: .json,
                      defaultFilename: Sauvegarde.nomFichier(pour: .now)) { resultat in
            switch resultat {
            case .success: message = "Sauvegarde enregistrée."
            case .failure(let erreur):
                message = "La sauvegarde n'a pas pu être enregistrée."
                etat.journal.noter(.general, "La sauvegarde n'a pas pu être enregistrée.", erreur: erreur)
            }
        }
        .fileImporter(isPresented: $importOuvert, allowedContentTypes: [.json]) { resultat in
            importer(resultat)
        }
    }

    private func exporter() {
        do {
            document = DocumentSauvegarde(donnees: try ServiceSauvegarde(contexte: contexte).exporter().encoder())
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
            let sauvegarde = try Sauvegarde.decoder(Data(contentsOf: url))
            let plan = try ServiceSauvegarde(contexte: contexte).importer(sauvegarde)
            if plan.estVide {
                message = "Rien de nouveau : tout ce que contient ce fichier est déjà là."
            } else {
                var parties: [String] = []
                if !plan.suivis.isEmpty { parties.append("\(plan.suivis.count) titre\(plan.suivis.count > 1 ? "s" : "")") }
                if !plan.visionnages.isEmpty { parties.append("\(plan.visionnages.count) visionnage\(plan.visionnages.count > 1 ? "s" : "")") }
                if !plan.filtres.isEmpty { parties.append("\(plan.filtres.count) filtre\(plan.filtres.count > 1 ? "s" : "")") }
                if !plan.abonnements.isEmpty { parties.append("\(plan.abonnements.count) plateforme\(plan.abonnements.count > 1 ? "s" : "")") }
                message = parties.isEmpty ? "Sauvegarde importée." : "Importé : \(parties.joined(separator: ", "))."
            }
            Task { await etat.alertes.planifier(contexte: contexte, tmdb: etat.tmdb) }
        } catch {
            message = "Ce fichier n'a pas pu être importé. Vérifie qu'il s'agit bien d'une sauvegarde de Séance."
            etat.journal.noter(.general, "Une sauvegarde n'a pas pu être importée.", erreur: error)
        }
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
