import Foundation
import SeanceDonnees
import SwiftData

/// Le magasin SwiftData de l'app, ouvert une seule fois : l'interface, Siri et les raccourcis le partagent.
@MainActor
enum ConteneurApp {
    static let resultat: Result<ModelContainer, any Error> = Result {
        #if DEBUG
        if Demonstration.active {
            // La démonstration repart de réglages vierges : un test ne laisse rien au suivant (prénom, apparence,
            // dossier de synchronisation…). Première chose faite au lancement, avant que quiconque ne lise un réglage.
            if let identifiant = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: identifiant) }
            let conteneur = try EntrepotSeance.conteneur(.memoire)
            if !Demonstration.vide { Demonstration.remplir(conteneur.mainContext) }
            return conteneur
        }
        #endif
        return try EntrepotSeance.conteneur(.groupeApp)
    }

    static var conteneur: ModelContainer? {
        try? resultat.get()
    }
}

/// Nom commun avec le widget : le ✓ des épisodes s'exécute dans l'un ou l'autre processus.
@MainActor
enum ConteneurPartage {
    static var conteneur: ModelContainer? {
        ConteneurApp.conteneur
    }
}
