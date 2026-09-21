import Foundation
import SeanceKit
import SwiftData
import Testing
@testable import SeanceDonnees

@Suite("Famille")
@MainActor
struct FamilleTests {
    private func registre() -> ProfilsFamille {
        let suite = "tests.famille.\(UUID().uuidString)"
        let defauts = UserDefaults(suiteName: suite)!
        defauts.removePersistentDomain(forName: suite)
        return ProfilsFamille(defauts: defauts)
    }

    @Test func leProfilPrincipalEstToujoursLa() {
        let famille = registre()
        #expect(famille.profils.count == 1 && famille.actif.estPrincipal && !famille.aPlusieursProfils)
        #expect(famille.actif.dossierSynchro == nil)

        let anne = famille.ajouter(prenom: " Anne ", symbole: "star.fill")
        #expect(famille.profils.map(\.prenom) == ["", "Anne"] && famille.aPlusieursProfils)
        #expect(anne.dossierSynchro == "Famille/Anne")
        famille.activer(anne)
        #expect(famille.actif == anne)

        var principal = famille.profils[0]
        principal.prenom = "Patrick"
        famille.modifier(principal)
        #expect(famille.profils.map(\.prenom) == ["Patrick", "Anne"])

        famille.supprimer(famille.profils[0])   // le principal ne se supprime pas
        famille.supprimer(anne)
        #expect(famille.profils.map(\.prenom) == ["Patrick"] && famille.actif.estPrincipal)
        #expect(ProfilFamille.nomDeDossier("Jean/Luc: 2") == "Jean-Luc- 2")
    }

    @Test func leFoyerSePartageLesListesNon() throws {
        let patrick = try EntrepotSeance.conteneur(.memoire)
        let anne = try EntrepotSeance.conteneur(.memoire)
        patrick.mainContext.insert(Abonnement(providerID: 8, nom: "Netflix"))
        patrick.mainContext.insert(Suivi(reference: ReferenceTitre(type: .film, tmdbID: 949), titre: "Heat"))
        try patrick.mainContext.save()

        try ServiceFamille.partagerLeFoyer(de: patrick.mainContext, vers: anne.mainContext)
        #expect(try anne.mainContext.fetch(FetchDescriptor<Abonnement>()).map(\.providerID) == [8])
        #expect(try anne.mainContext.fetch(FetchDescriptor<Suivi>()).isEmpty)

        // Netflix décochée par Patrick : en entrant dans le profil d'Anne, elle l'est aussi.
        try patrick.mainContext.fetch(FetchDescriptor<Abonnement>()).first?.actif = false
        try ServiceFamille.partagerLeFoyer(de: patrick.mainContext, vers: anne.mainContext)
        #expect(try anne.mainContext.fetch(FetchDescriptor<Abonnement>()).first?.actif == false)
    }

    @Test func quiRegardeCeSoir() {
        var patrick = ProfilGouts()
        patrick.genres = [28: 0.9, 27: 0.6, 35: 0.1]
        patrick.observations = 30
        var anne = ProfilGouts()
        anne.genres = [28: 0.5, 27: -0.8, 35: 0.7]
        anne.observations = 10
        let ensemble = ServiceFamille.fondre([patrick, anne])
        #expect(abs(ensemble.affinite(genre: 28) - 0.7) < 0.001)
        // L'horreur, qu'Anne déteste, ne passe pas à la moyenne : elle est évitée.
        #expect(ensemble.affinite(genre: 27) <= -0.25 && ensemble.genresEvites.contains(27))
        #expect(ensemble.affinite(genre: 35) > 0.3 && ensemble.observations == 40)
        #expect(ServiceFamille.fondre([patrick]) == patrick)

        let vuParAnne = ReferenceTitre(type: .film, tmdbID: 1)
        let ecarteParPatrick = ReferenceTitre(type: .film, tmdbID: 2)
        let fondu = ServiceFamille.fondre([CollecteurCandidats.Contexte(abonnements: [8], exclus: [ecarteParPatrick]),
                                          CollecteurCandidats.Contexte(abonnements: [8, 9], dejaVus: [vuParAnne])])
        #expect(fondu.dejaVus == [vuParAnne] && fondu.exclus == [ecarteParPatrick] && Set(fondu.abonnements) == [8, 9])
    }
}
