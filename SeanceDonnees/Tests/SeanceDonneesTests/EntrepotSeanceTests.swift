import Foundation
import SeanceKit
import SwiftData
import Testing
@testable import SeanceDonnees

@Suite("Magasin SwiftData")
@MainActor
struct EntrepotSeanceTests {
    /// Une base de la 2.3 sur disque, sans version comme celles déjà installées puis déclarée en version 1 :
    /// la 2.4 l'ouvre par son plan de migration, garde tout, et les listes reçoivent leur champ ajouté.
    @Test(arguments: [false, true]) func migreUneBaseDeLaVersion1(versionne: Bool) throws {
        let dossier = FileManager.default.temporaryDirectory.appending(path: "seance-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dossier) }
        let heat = ReferenceTitre(type: .film, tmdbID: 949)

        do {
            let ancien = try EntrepotSeance.conteneurV1(dossier: dossier, versionne: versionne)
            let liste = SchemaSeanceV1.ListePerso(nom: "Soirées Statham")
            liste.titres = [heat]
            ancien.mainContext.insert(liste)
            ancien.mainContext.insert(Suivi(reference: heat, titre: "Heat"))
            ancien.mainContext.insert(EtatPlateformes(reference: heat, fournisseurs: [8]))
            try ancien.mainContext.save()
        }

        EntrepotSeance.derniereErreurDuPlan = nil
        let conteneur = try EntrepotSeance.conteneur(.dossier(dossier))
        #expect(EntrepotSeance.derniereErreurDuPlan == nil, "le plan de migration a échoué, l'ouverture de secours a servi")
        let contexte = conteneur.mainContext
        let liste = try #require(try contexte.fetch(FetchDescriptor<ListePerso>()).first)
        #expect(liste.nom == "Soirées Statham" && liste.titres == [heat] && liste.apercus.isEmpty)
        #expect(try contexte.fetch(FetchDescriptor<Suivi>()).map(\.titre) == ["Heat"])
        #expect(try contexte.fetch(FetchDescriptor<EtatPlateformes>()).first?.fournisseurs == [8])

        // La base migrée s'écrit et se rouvre.
        liste.apercus = [ApercuTitre(reference: heat, titre: "Heat", cheminAffiche: "/heat.jpg")]
        try contexte.save()
    }

    /// Une base de la 4.6 (schéma version 2) : la 4.7 l'ouvre par son plan, garde tout, et accueille les « J'aime ».
    @Test func migreUneBaseDeLaVersion2() throws {
        let dossier = FileManager.default.temporaryDirectory.appending(path: "seance-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dossier) }
        let heat = ReferenceTitre(type: .film, tmdbID: 949)

        do {
            let ancien = try EntrepotSeance.conteneurV2(dossier: dossier)
            ancien.mainContext.insert(Suivi(reference: heat, titre: "Heat"))
            let liste = ListePerso(nom: "Soirées Statham")
            liste.titres = [heat]
            ancien.mainContext.insert(liste)
            try ancien.mainContext.save()
        }

        EntrepotSeance.derniereErreurDuPlan = nil
        let conteneur = try EntrepotSeance.conteneur(.dossier(dossier))
        #expect(EntrepotSeance.derniereErreurDuPlan == nil, "le plan de migration a échoué, l'ouverture de secours a servi")
        let contexte = conteneur.mainContext
        #expect(try contexte.fetch(FetchDescriptor<Suivi>()).map(\.titre) == ["Heat"])
        #expect(try contexte.fetch(FetchDescriptor<ListePerso>()).first?.titres == [heat])
        contexte.insert(TitreAime(reference: heat, titre: "Heat", genres: [80, 53]))
        try contexte.save()
        #expect(try contexte.fetchCount(FetchDescriptor<TitreAime>()) == 1)
    }

    /// Une base écrite par la 5.1, dont les modèles n'ont pas d'index : la 5.2, qui en pose cinq, la rouvre
    /// et relit tout. SwiftData ne compte pas les index dans la version du schéma — d'où ce test plutôt qu'une
    /// version de plus au plan de migration.
    @Test func rouvreUneBaseEcriteSansIndex() throws {
        let dossier = FileManager.default.temporaryDirectory.appending(path: "seance-index-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dossier) }
        let heat = ReferenceTitre(type: .film, tmdbID: 949)

        do {
            let ancien = try ModelesSansIndex.conteneur(dossier: dossier)
            ancien.mainContext.insert(ModelesSansIndex.Suivi(reference: heat, titre: "Heat"))
            ancien.mainContext.insert(ModelesSansIndex.FichierNAS(chemin: "Films/Heat.1995.mkv"))
            ancien.mainContext.insert(ModelesSansIndex.Echeance(reference: heat, titre: "Heat", date: .now))
            try ancien.mainContext.save()
        }

        EntrepotSeance.derniereErreurDuPlan = nil
        let conteneur = try EntrepotSeance.conteneur(.dossier(dossier))
        #expect(EntrepotSeance.derniereErreurDuPlan == nil, "le plan de migration a échoué, l'ouverture de secours a servi")
        let contexte = conteneur.mainContext
        #expect(try contexte.fetch(FetchDescriptor<Suivi>()).map(\.titre) == ["Heat"])
        #expect(try contexte.fetch(FetchDescriptor<FichierNAS>()).map(\.chemin) == ["Films/Heat.1995.mkv"])
        #expect(try contexte.fetchCount(FetchDescriptor<Echeance>()) == 1)

        // La requête que pose chaque affiche : par identifiant, désormais indexée.
        let id = heat.tmdbID
        #expect(try contexte.fetchCount(FetchDescriptor<Suivi>(predicate: #Predicate { $0.tmdbID == id })) == 1)
    }

    /// Une base de la 5.2 (schéma version 3) : la 5.3 l'ouvre par son plan, garde tout, et accueille les favoris.
    @Test func migreUneBaseDeLaVersion3() throws {
        let dossier = FileManager.default.temporaryDirectory.appending(path: "seance-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dossier) }
        let heat = ReferenceTitre(type: .film, tmdbID: 949)

        do {
            let ancien = try EntrepotSeance.conteneurV3(dossier: dossier)
            ancien.mainContext.insert(Suivi(reference: heat, titre: "Heat"))
            ancien.mainContext.insert(TitreAime(reference: heat, titre: "Heat", genres: [80]))
            try ancien.mainContext.save()
        }

        EntrepotSeance.derniereErreurDuPlan = nil
        let conteneur = try EntrepotSeance.conteneur(.dossier(dossier))
        #expect(EntrepotSeance.derniereErreurDuPlan == nil, "le plan de migration a échoué, l'ouverture de secours a servi")
        let contexte = conteneur.mainContext
        #expect(try contexte.fetch(FetchDescriptor<Suivi>()).map(\.titre) == ["Heat"])
        #expect(try contexte.fetchCount(FetchDescriptor<TitreAime>()) == 1)
        #expect(try contexte.fetchCount(FetchDescriptor<Favori>()) == 0)

        let favoris = ServiceFavoris(contexte: contexte)
        #expect(try favoris.basculer(heat, titre: "Heat", annee: 1995))
        #expect(try favoris.estFavori(heat))
        #expect(try !favoris.basculer(heat, titre: "Heat"))
        #expect(try favoris.tous().isEmpty)
    }

    /// Vérification à la demande sur la copie d'une vraie base : `TEST_RUNNER_SEANCE_BASE_REELLE=/dossier xcodebuild test …`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SEANCE_BASE_REELLE"] != nil))
    func ouvreLaCopieDUneVraieBase() throws {
        let dossier = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SEANCE_BASE_REELLE"] ?? "")
        EntrepotSeance.derniereErreurDuPlan = nil
        let conteneur = try EntrepotSeance.conteneur(.dossier(dossier))
        #expect(EntrepotSeance.derniereErreurDuPlan == nil, "le plan de migration a échoué sur la vraie base")
        let contexte = conteneur.mainContext
        let suivis = try contexte.fetchCount(FetchDescriptor<Suivi>())
        let visionnages = try contexte.fetchCount(FetchDescriptor<Visionnage>())
        print("BASE RÉELLE : \(suivis) suivis, \(visionnages) visionnages, \(try contexte.fetchCount(FetchDescriptor<ActeurSuivi>())) acteurs suivis")
        #expect(suivis > 0)
    }

    @Test func ouvreLesDeuxConfigurationsEnMemoire() throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let contexte = conteneur.mainContext
        let fightClub = ReferenceTitre(type: .film, tmdbID: 550)

        contexte.insert(Suivi(reference: fightClub, titre: "Fight Club"))
        contexte.insert(Visionnage(reference: fightClub, dureeMinutes: 139))
        contexte.insert(EtatPlateformes(reference: fightClub, fournisseurs: [119, 337]))
        try contexte.save()

        #expect(try contexte.fetchCount(FetchDescriptor<Suivi>()) == 1)
        #expect(try contexte.fetchCount(FetchDescriptor<Visionnage>()) == 1)
        #expect(try contexte.fetch(FetchDescriptor<EtatPlateformes>()).first?.fournisseurs == [119, 337])
    }

    @Test func filtreEnregistreGardeSesCriteres() throws {
        // Le conteneur doit rester en vie : son contexte ne le retient pas.
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let contexte = conteneur.mainContext
        var criteres = CriteresDecouverte()
        criteres.acteurs = [6384]
        criteres.genresInclus = [28]
        contexte.insert(FiltreEnregistre(nom: "Keanu, action", type: .film, criteres: criteres))
        try contexte.save()

        let relu = try #require(try contexte.fetch(FetchDescriptor<FiltreEnregistre>()).first)
        #expect(relu.criteres == criteres)
    }

    @Test func listePersoDeReferences() throws {
        // Le conteneur doit rester en vie : son contexte ne le retient pas.
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let contexte = conteneur.mainContext
        let liste = ListePerso(nom: "Soirées Statham")
        liste.titres = [ReferenceTitre(type: .film, tmdbID: 345_940), ReferenceTitre(type: .serie, tmdbID: 108_978)]
        contexte.insert(liste)
        try contexte.save()

        #expect(try contexte.fetch(FetchDescriptor<ListePerso>()).first?.titres.map(\.type) == [.film, .serie])
    }
}
