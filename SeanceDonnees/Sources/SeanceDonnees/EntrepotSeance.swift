import Foundation
import SwiftData

/// Ouvre le magasin SwiftData de Séance : deux configurations locales, sans CloudKit
/// (pas de compte Apple Developer payant). Le widget ouvre le même magasin via l'App Group.
public enum EntrepotSeance {
    public static let groupeApp = "group.ch.patrick.seance"

    public enum Emplacement: Sendable {
        /// Conteneur partagé avec le widget ; c'est l'emplacement de l'app.
        case groupeApp
        /// Pour les tests et les aperçus SwiftUI.
        case memoire
        case dossier(URL)
    }

    public static var modelesUtilisateur: [any PersistentModel.Type] {
        [Suivi.self, Visionnage.self, ListePerso.self, FiltreEnregistre.self,
         Interet.self, Abonnement.self, Chaine.self, SourceNAS.self, SuggestionReportee.self, SelectionSoir.self]
    }

    public static var modelesCache: [any PersistentModel.Type] {
        [TitreCache.self, Diffusion.self, EtatPlateformes.self, AlertePlanifiee.self, FichierNAS.self, Echeance.self]
    }

    public static func conteneur(_ emplacement: Emplacement = .groupeApp) throws -> ModelContainer {
        let utilisateur = configuration("Utilisateur", modelesUtilisateur, emplacement)
        let cache = configuration("Cache", modelesCache, emplacement)
        return try ModelContainer(
            for: Schema(modelesUtilisateur + modelesCache),
            configurations: utilisateur, cache
        )
    }

    private static func configuration(
        _ nom: String, _ modeles: [any PersistentModel.Type], _ emplacement: Emplacement
    ) -> ModelConfiguration {
        let schema = Schema(modeles)
        switch emplacement {
        case .groupeApp:
            return ModelConfiguration(nom, schema: schema, groupContainer: .identifier(groupeApp), cloudKitDatabase: .none)
        case .memoire:
            return ModelConfiguration(nom, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        case .dossier(let dossier):
            return ModelConfiguration(nom, schema: schema, url: dossier.appending(path: "\(nom).store"), cloudKitDatabase: .none)
        }
    }
}
