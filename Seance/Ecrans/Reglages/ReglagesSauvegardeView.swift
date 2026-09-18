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
                Text("Un fichier avec tes listes, épisodes vus, notes, soirées prévues, acteurs suivis, filtres, goûts, plateformes, chaînes et réglages (prénom, accueil, alertes, adresse du NAS). Il ne contient ni clé ni mot de passe : la clé TMDB, la clé Claude et le mot de passe du NAS se saisissent sur chaque appareil.")
            }

            Section {
                Button {
                    importOuvert = true
                } label: {
                    Label("Importer une sauvegarde", systemImage: "square.and.arrow.down")
                }
            } footer: {
                Text("L'import ajoute ce qui manque et complète les titres déjà là — un film vu ou noté sur l'autre appareil le devient ici — sans rien effacer. Ce que tu as supprimé sur un appareil n'est pas supprimé sur l'autre.")
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
            var sauvegarde = try ServiceSauvegarde(contexte: contexte).exporter()
            sauvegarde.preferences = PreferencesSauvegardees.lire()
            document = DocumentSauvegarde(donnees: try sauvegarde.encoder())
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
            let reglages = PreferencesSauvegardees.appliquer(sauvegarde.preferences ?? [:], etat: etat)
            // Tout ce qui est arrivé est dit : « 12 titres, 3 soirées, 5 réglages », pas seulement les titres.
            let comptes: [(Int, String, String)] = [
                (plan.suivis.count, "titre", "titres"), (plan.suivisCompletes.count, "titre complété", "titres complétés"),
                (plan.visionnages.count, "visionnage", "visionnages"), (plan.soirees.count, "soirée prévue", "soirées prévues"),
                (plan.listes.count + plan.titresAjoutesAuxListes.count, "liste", "listes"), (plan.acteursSuivis.count, "acteur suivi", "acteurs suivis"),
                (plan.filtres.count, "filtre", "filtres"), (plan.interets.count, "goût", "goûts"),
                (plan.abonnements.count, "plateforme", "plateformes"), (plan.chaines.count, "chaîne", "chaînes"),
                (plan.reports.count, "idée reportée", "idées reportées"), (reglages, "réglage", "réglages"),
            ]
            let parties = comptes.filter { $0.0 > 0 }.map { Format.pluriel($0.0, $0.1, $0.2) }
            if parties.isEmpty {
                message = "Rien de nouveau : tout ce que contient ce fichier est déjà là."
            } else {
                message = "Importé : \(parties.joined(separator: ", ")).\(etat.tmdb == nil ? " Il reste à saisir ta clé TMDB dans Réglages › TMDB : les clés ne voyagent pas dans la sauvegarde." : "")"
            }
            etat.ou.actualiserLocal(contexte: contexte)
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
