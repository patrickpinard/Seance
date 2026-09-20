import Foundation
import SeanceKit
import SwiftData
@testable import SeanceDonnees

/// Les modèles tels que Séance 5.1 les écrivait, **sans** les `#Index` posés en 5.2 : de quoi fabriquer une base
/// d'avant les index et vérifier que la version suivante la rouvre (`EntrepotSeanceTests.rouvreUneBaseEcriteSansIndex`).
///
/// Ils vivent ici, et non dans `SchemaSeance.swift`, parce qu'un index ne change pas la version du schéma :
/// SwiftData refuse deux versions au même relevé (« Duplicate version checksums »). Seuls les champs comptent ;
/// les propriétés calculées et les initialiseurs complets n'ont pas été recopiés.
enum ModelesSansIndex {
    static var modelesUtilisateur: [any PersistentModel.Type] {
        [ModelesSansIndex.Suivi.self, Visionnage.self, ListePerso.self, FiltreEnregistre.self,
         Interet.self, Abonnement.self, Chaine.self, SourceNAS.self, SuggestionReportee.self, SelectionSoir.self,
         ActeurSuivi.self, TitreAime.self]
    }

    static var modelesCache: [any PersistentModel.Type] {
        [ModelesSansIndex.TitreCache.self, ModelesSansIndex.Diffusion.self, EtatPlateformes.self,
         AlertePlanifiee.self, ModelesSansIndex.FichierNAS.self, ModelesSansIndex.Echeance.self]
    }

    /// Un magasin sur disque écrit avec ces modèles, dans les deux configurations habituelles.
    static func conteneur(dossier: URL) throws -> ModelContainer {
        let utilisateur = ModelConfiguration("Utilisateur", schema: Schema(modelesUtilisateur),
                                             url: dossier.appending(path: "Utilisateur.store"), cloudKitDatabase: .none)
        let cache = ModelConfiguration("Cache", schema: Schema(modelesCache),
                                       url: dossier.appending(path: "Cache.store"), cloudKitDatabase: .none)
        return try ModelContainer(for: Schema(modelesUtilisateur + modelesCache), configurations: utilisateur, cache)
    }

    @Model
    final class Suivi {
        var tmdbID: Int = 0
        var typeBrut: String = TypeTitre.film.rawValue
        var statutBrut: String = StatutSuivi.aVoir.rawValue
        var masque: Bool = false
        var note: Int?
        var exclusionLangue: Bool = false
        var ajouteLe: Date = Date.now
        var titre: String = ""
        var cheminAffiche: String?
        var acteursPrincipaux: [String] = []
        var acteursPrincipauxIDs: [Int] = []
        var genres: [Int] = []
        var alertesActives: Bool = true
        var modeAlertesBrut: String = ModeAlerteSerie.episodes.rawValue

        init(reference: ReferenceTitre, titre: String) {
            tmdbID = reference.tmdbID
            typeBrut = reference.type.rawValue
            self.titre = titre
        }
    }

    @Model
    final class TitreCache {
        var tmdbID: Int = 0
        var typeBrut: String = TypeTitre.film.rawValue
        var donnees: Data = Data()
        var majLe: Date = Date.now

        init(reference: ReferenceTitre, donnees: Data) {
            tmdbID = reference.tmdbID
            typeBrut = reference.type.rawValue
            self.donnees = donnees
        }
    }

    @Model
    final class Diffusion {
        var chaine: String = ""
        var debut: Date = Date.distantPast
        var fin: Date = Date.distantPast
        var titreGuide: String = ""
        var anneeGuide: Int?
        var saison: Int?
        var episode: Int?
        var typeBrut: String = TypeTitre.film.rawValue
        var tmdbID: Int?
        var cheminFond: String?
        var cheminAffiche: String?
        var imageGuide: String?

        init(chaine: String, debut: Date, fin: Date, titreGuide: String) {
            self.chaine = chaine
            self.debut = debut
            self.fin = fin
            self.titreGuide = titreGuide
        }
    }

    @Model
    final class FichierNAS {
        var tmdbID: Int?
        var typeBrut: String = TypeTitre.film.rawValue
        var saison: Int?
        var episode: Int?
        var chemin: String = ""
        var qualite: String?
        var tailleOctets: Int64 = 0
        var indexeLe: Date = Date.now
        var dossier: String = ""
        var titre: String = ""
        var annee: Int?
        var cheminAffiche: String?
        var cheminFond: String?
        var noteMoyenne: Double = 0
        var nombreVotes: Int = 0

        init(chemin: String) {
            self.chemin = chemin
            dossier = chemin.split(separator: "/").first.map(String.init) ?? ""
            titre = (chemin as NSString).lastPathComponent
        }
    }

    @Model
    final class Echeance {
        var tmdbID: Int = 0
        var typeBrut: String = TypeTitre.film.rawValue
        var titre: String = ""
        var cheminAffiche: String?
        var date: Date = Date.now
        var libelle: String = ""
        var natureBrut: String = EcheancePrevue.Nature.sortie.rawValue

        init(reference: ReferenceTitre, titre: String, date: Date) {
            tmdbID = reference.tmdbID
            typeBrut = reference.type.rawValue
            self.titre = titre
            self.date = date
        }
    }
}
