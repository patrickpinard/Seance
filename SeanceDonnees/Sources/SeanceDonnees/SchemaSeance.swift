import Foundation
import SeanceKit
import SwiftData

// Versions du schéma SwiftData. Jusqu'à Séance 2.3, chaque champ ajouté reposait sur la migration automatique,
// sans trace de version. Désormais : une version par changement de modèle, une étape de migration entre deux
// versions, et un test qui ouvre une base de l'ancienne version (EntrepotSeanceTests).
//
// Pour changer un modèle : recopier ici, dans la version courante, la classe telle qu'elle est AVANT le changement ;
// créer la version suivante avec les modèles d'aujourd'hui ; ajouter l'étape au plan ; compléter le test.

/// Version 1 : le schéma de Séance 2.3, tel qu'il existe dans les bases déjà installées. Seul le modèle modifié
/// depuis y est recopié ; les autres sont ceux d'aujourd'hui, inchangés.
public enum SchemaSeanceV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var modelesUtilisateur: [any PersistentModel.Type] {
        [Suivi.self, Visionnage.self, SchemaSeanceV1.ListePerso.self, FiltreEnregistre.self,
         Interet.self, Abonnement.self, Chaine.self, SourceNAS.self, SuggestionReportee.self, SelectionSoir.self, ActeurSuivi.self]
    }

    public static var models: [any PersistentModel.Type] {
        modelesUtilisateur + EntrepotSeance.modelesCache
    }

    /// La liste nommée de la 2.3 : des références seulement, sans de quoi les afficher.
    @Model
    public final class ListePerso {
        public var nom: String = ""
        public var creeeLe: Date = Date.now
        public var titres: [ReferenceTitre] = []

        public init(nom: String) {
            self.nom = nom
        }
    }
}

/// Version 2 (Séance 2.4) : les listes nommées gardent le nom et l'affiche de chaque titre.
public enum SchemaSeanceV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    /// Les modèles de la version 2 : ceux d'aujourd'hui, sans `TitreAime`, arrivé en version 3.
    static var modelesUtilisateur: [any PersistentModel.Type] {
        EntrepotSeance.modelesUtilisateur.filter { ObjectIdentifier($0) != ObjectIdentifier(TitreAime.self) }
    }

    public static var models: [any PersistentModel.Type] {
        modelesUtilisateur + EntrepotSeance.modelesCache
    }
}

/// Version 3 (Séance 4.7) : les « J'aime » (`TitreAime`), un modèle de plus.
public enum SchemaSeanceV3: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        EntrepotSeance.modelesUtilisateur + EntrepotSeance.modelesCache
    }
}

public enum PlanMigrationSeance: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SchemaSeanceV1.self, SchemaSeanceV2.self, SchemaSeanceV3.self]
    }

    public static var stages: [MigrationStage] {
        // Un champ ajouté avec sa valeur par défaut : migration légère.
        // Un champ ajouté avec sa valeur par défaut, puis un modèle ajouté : migrations légères.
        [.lightweight(fromVersion: SchemaSeanceV1.self, toVersion: SchemaSeanceV2.self),
         .lightweight(fromVersion: SchemaSeanceV2.self, toVersion: SchemaSeanceV3.self)]
    }
}
