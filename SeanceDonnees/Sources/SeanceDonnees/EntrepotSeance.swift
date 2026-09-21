import Foundation
import SwiftData

/// Ouvre le magasin SwiftData de Séance : deux configurations locales, sans CloudKit
/// (pas de compte Apple Developer payant). Le widget ouvre le même magasin via l'App Group.
public enum EntrepotSeance {
    public static let groupeApp = "group.ch.patrick.seance"

    public enum Emplacement: Sendable {
        /// Conteneur partagé avec le widget ; c'est l'emplacement de l'app.
        case groupeApp
        /// Famille (Séance 6.0) : le magasin d'un autre profil du foyer, à côté de celui du profil principal. Ses listes,
        /// ses notes et ses goûts sont à lui ; le cache (TMDB, guide TV, NAS) reste commun. Pas de changement de schéma.
        case profil(String)
        /// Pour les tests et les aperçus SwiftUI.
        case memoire
        case dossier(URL)
        /// Apple TV (6.0.1) : le magasin d'un autre profil de la famille dans ce dossier, à côté du cache commun.
        case dossierProfil(URL, String)
    }

    /// Dossier partagé avec le widget, pour ce qui n'est pas dans SwiftData (liste des prochains épisodes).
    public static var dossierPartage: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupeApp)
    }

    public static var modelesUtilisateur: [any PersistentModel.Type] {
        [Suivi.self, Visionnage.self, ListePerso.self, FiltreEnregistre.self,
         Interet.self, Abonnement.self, Chaine.self, SourceNAS.self, SuggestionReportee.self, SelectionSoir.self, ActeurSuivi.self,
         TitreAime.self, Favori.self]
    }

    public static var modelesCache: [any PersistentModel.Type] {
        [TitreCache.self, Diffusion.self, EtatPlateformes.self, AlertePlanifiee.self, FichierNAS.self, Echeance.self]
    }

    /// Ouvre le magasin avec le plan de migration (SchemaSeance.swift). Si cette ouverture échoue, le magasin est
    /// rouvert comme avant la 2.4, par la migration automatique : une erreur du plan ne doit jamais couper
    /// l'app de ses données.
    public static func conteneur(_ emplacement: Emplacement = .groupeApp) throws -> ModelContainer {
        var nomUtilisateur = "Utilisateur"
        if case .profil(let identifiant) = emplacement { nomUtilisateur = "Utilisateur-\(identifiant)" }
        if case .dossierProfil(_, let identifiant) = emplacement { nomUtilisateur = "Utilisateur-\(identifiant)" }
        let utilisateur = configuration(nomUtilisateur, modelesUtilisateur, emplacement)
        let cache = configuration("Cache", modelesCache, emplacement)
        do {
            return try ModelContainer(
                for: Schema(versionedSchema: SchemaSeanceV4.self),
                migrationPlan: PlanMigrationSeance.self,
                configurations: utilisateur, cache
            )
        } catch {
            derniereErreurDuPlan = String(describing: error)
            return try ModelContainer(
                for: Schema(modelesUtilisateur + modelesCache),
                configurations: utilisateur, cache
            )
        }
    }

    /// Le seul magasin « Utilisateur » d'un autre profil de la famille, pour y lire ses goûts (« Qui regarde ce soir ? »)
    /// sans rouvrir le cache commun, que le profil actif tient déjà.
    public static func conteneurDesGouts(_ profil: ProfilFamille) throws -> ModelContainer {
        let nom = profil.estPrincipal ? "Utilisateur" : "Utilisateur-\(profil.id)"
        return try ModelContainer(for: Schema(modelesUtilisateur), configurations: configuration(nom, modelesUtilisateur, profil.emplacement))
    }

    /// Renseignée quand le plan de migration n'a pas pu ouvrir le magasin ; l'app la note dans son journal.
    public nonisolated(unsafe) static var derniereErreurDuPlan: String?

    /// Pour les tests : une base de la version 3 du schéma (Séance 4.7 à 5.2), sans les favoris.
    static func conteneurV3(dossier: URL) throws -> ModelContainer {
        let utilisateur = configuration("Utilisateur", SchemaSeanceV3.modelesUtilisateur, .dossier(dossier))
        let cache = configuration("Cache", modelesCache, .dossier(dossier))
        return try ModelContainer(for: Schema(versionedSchema: SchemaSeanceV3.self), configurations: utilisateur, cache)
    }

    /// Pour les tests : une base de la version 2 du schéma (Séance 2.4 à 4.6), sans les « J'aime ».
    static func conteneurV2(dossier: URL) throws -> ModelContainer {
        let utilisateur = configuration("Utilisateur", SchemaSeanceV2.modelesUtilisateur, .dossier(dossier))
        let cache = configuration("Cache", modelesCache, .dossier(dossier))
        return try ModelContainer(for: Schema(versionedSchema: SchemaSeanceV2.self), configurations: utilisateur, cache)
    }

    /// Pour les tests : une base telle que Séance 2.3 la créait, sans version (comme les bases installées)
    /// ou déclarée en version 1.
    static func conteneurV1(dossier: URL, versionne: Bool) throws -> ModelContainer {
        let utilisateur = configuration("Utilisateur", SchemaSeanceV1.modelesUtilisateur, .dossier(dossier))
        let cache = configuration("Cache", modelesCache, .dossier(dossier))
        let schema = versionne ? Schema(versionedSchema: SchemaSeanceV1.self) : Schema(SchemaSeanceV1.models)
        return try ModelContainer(for: schema, configurations: utilisateur, cache)
    }

    private static func configuration(
        _ nom: String, _ modeles: [any PersistentModel.Type], _ emplacement: Emplacement
    ) -> ModelConfiguration {
        let schema = Schema(modeles)
        switch emplacement {
        case .groupeApp, .profil:
            return ModelConfiguration(nom, schema: schema, groupContainer: .identifier(groupeApp), cloudKitDatabase: .none)
        case .memoire:
            return ModelConfiguration(nom, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        case .dossier(let dossier), .dossierProfil(let dossier, _):
            return ModelConfiguration(nom, schema: schema, url: dossier.appending(path: "\(nom).store"), cloudKitDatabase: .none)
        }
    }
}
