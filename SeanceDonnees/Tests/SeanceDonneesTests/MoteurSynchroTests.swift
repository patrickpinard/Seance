import Foundation
import SeanceKit
import SwiftData
import Testing
@testable import SeanceDonnees

/// Un dossier partagé en mémoire : ce que serait le dossier du NAS, sans NAS.
private final class DossierEnMemoire: TransportSynchro, @unchecked Sendable {
    private let verrou = NSLock()
    private var fichiers: [String: (donnees: Data, modifieLe: Date)] = [:]
    private var horloge = Date(timeIntervalSince1970: 1_800_000_000)

    func lister() async throws -> [SynchroDossier.Fichier] {
        verrou.withLock { fichiers.map { SynchroDossier.Fichier(nom: $0.key, modifieLe: $0.value.modifieLe) } }
    }

    func lire(_ nom: String) async throws -> Data {
        guard let fichier = verrou.withLock({ fichiers[nom] }) else { throw CocoaError(.fileNoSuchFile) }
        return fichier.donnees
    }

    func ecrire(_ donnees: Data, nom: String) async throws {
        verrou.withLock {
            horloge = horloge.addingTimeInterval(60)
            fichiers[nom] = (donnees, horloge)
        }
    }

    var noms: [String] { verrou.withLock { fichiers.keys.sorted() } }
}

@Suite("Synchronisation par un dossier partagé, de bout en bout")
@MainActor
struct MoteurSynchroTests {
    /// Un appareil : son magasin, ses réglages à lui, son état de synchronisation.
    @MainActor
    private struct Appareil {
        let conteneur: ModelContainer
        let moteur: MoteurSynchro

        init(_ nom: String, dossier: DossierEnMemoire) throws {
            conteneur = try EntrepotSeance.conteneur(.memoire)
            let suite = "tests.synchro.\(UUID().uuidString)"
            let defauts = UserDefaults(suiteName: suite)!
            defauts.removePersistentDomain(forName: suite)
            let etat = FileManager.default.temporaryDirectory.appending(path: "\(suite).json")
            moteur = MoteurSynchro(contexte: conteneur.mainContext, transport: dossier, appareil: nom, espace: "synchro.nas",
                                   fichierEtat: etat, defauts: defauts)
        }

        var contexte: ModelContext { conteneur.mainContext }
    }

    @Test func lIPhoneDeposeLaTeleRecoitPuisSupprime() async throws {
        let dossier = DossierEnMemoire()
        let iphone = try Appareil("iPhone 3F2A", dossier: dossier)
        let tele = try Appareil("Apple TV 9C01", dossier: dossier)
        let heat = ReferenceTitre(type: .film, tmdbID: 949)
        let jour = Date.now

        // L'iPhone garde un film « à voir » et le prévoit pour ce soir ; il dépose son fichier.
        iphone.contexte.insert(Suivi(reference: heat, titre: "Heat", statut: .aVoir, cheminAffiche: "/heat.jpg"))
        try ServiceSoiree(contexte: iphone.contexte).retenir(heat, titre: "Heat", cheminAffiche: "/heat.jpg")
        try iphone.contexte.save()
        let premier = try await iphone.moteur.synchroniser(maintenant: jour)
        #expect(premier.deposees != nil && premier.recus.isEmpty)
        #expect(dossier.noms == ["Séance — iPhone 3F2A.json"])

        // La TV lit le dossier : la liste et la soirée arrivent, et elle dépose son fichier à son tour.
        let recu = try await tele.moteur.synchroniser(maintenant: jour.addingTimeInterval(60))
        #expect(recu.recus.count == 1)
        #expect(try ServiceSuivi(contexte: tele.contexte).suivi(heat)?.statut == .aVoir)
        #expect(try ServiceSoiree(contexte: tele.contexte).estRetenu(heat))
        #expect(dossier.noms.count == 2)

        // Rien n'a changé : personne ne retouche son fichier, personne ne réimporte.
        let calme = try await iphone.moteur.synchroniser(maintenant: jour.addingTimeInterval(120))
        #expect(calme.deposees == nil && calme.recus.isEmpty)
        let calmeTele = try await tele.moteur.synchroniser(maintenant: jour.addingTimeInterval(180))
        #expect(calmeTele.deposees == nil && calmeTele.recus.isEmpty)

        // Sur la TV, le film est retiré de la liste : la suppression voyage jusqu'à l'iPhone.
        if let suivi = try ServiceSuivi(contexte: tele.contexte).suivi(heat) { tele.contexte.delete(suivi) }
        try tele.contexte.save()
        _ = try await tele.moteur.synchroniser(maintenant: jour.addingTimeInterval(3600))
        let retour = try await iphone.moteur.synchroniser(maintenant: jour.addingTimeInterval(3700))
        #expect(retour.recus.first?.supprimes == 1)
        #expect(try ServiceSuivi(contexte: iphone.contexte).suivi(heat) == nil)
    }

    @Test func unDossierIllisibleNeCasseRien() async throws {
        let dossier = DossierEnMemoire()
        try await dossier.ecrire(Data("pas du JSON".utf8), nom: "Séance — iPad 77C1.json")
        let iphone = try Appareil("iPhone 3F2A", dossier: dossier)
        let bilan = try await iphone.moteur.synchroniser()
        #expect(bilan.recus.isEmpty && bilan.deposees != nil)
    }
}
