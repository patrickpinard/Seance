import Foundation
import SeanceKit
import SwiftData
import Testing
@testable import SeanceDonnees

@Suite("Magasin SwiftData")
@MainActor
struct EntrepotSeanceTests {
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
