import Foundation
import SeanceDonnees
import SwiftData

/// Le magasin SwiftData de l'app, ouvert une seule fois : l'interface, Siri et les raccourcis le partagent.
@MainActor
enum ConteneurApp {
    static let resultat: Result<ModelContainer, any Error> = Result {
        #if DEBUG
        if Demonstration.active {
            let conteneur = try EntrepotSeance.conteneur(.memoire)
            Demonstration.remplir(conteneur.mainContext)
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
