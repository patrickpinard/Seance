import Foundation
import SeanceKit
import Testing
@testable import SeanceNAS

/// Sur le vrai NAS seulement : il faut un compte qui écrit dans le partage.
///   SEANCE_NAS_HOTE=192.168.1.20 SEANCE_NAS_PARTAGE=Films SEANCE_NAS_UTILISATEUR=patrick SEANCE_NAS_MOT_DE_PASSE=… \
///     swift test --package-path SeanceNAS --filter DossierSynchroSMB
@Suite("Dossier de synchronisation sur le NAS réel", .enabled(if: ProcessInfo.processInfo.environment["SEANCE_NAS_MOT_DE_PASSE"] != nil))
struct DossierSynchroSMBTests {
    @Test func ecrirePuisRelire() async throws {
        let env = ProcessInfo.processInfo.environment
        let reglages = ReglagesNAS(hote: env["SEANCE_NAS_HOTE"] ?? "", partage: env["SEANCE_NAS_PARTAGE"] ?? "",
                                   dossiers: [], utilisateur: env["SEANCE_NAS_UTILISATEUR"] ?? "")
        let dossier = DossierSynchroSMB(reglages: reglages, motDePasse: env["SEANCE_NAS_MOT_DE_PASSE"] ?? "", dossier: "Séance — essai")
        let nom = SynchroDossier.nomFichier(appareil: "Essai \(UUID().uuidString.prefix(4))")

        try await dossier.ecrire(Data("un".utf8), nom: nom)
        try await dossier.ecrire(Data("deux".utf8), nom: nom)   // remplace, sans doublon
        let presents = try await dossier.lister().filter { $0.nom == nom }
        #expect(presents.count == 1)
        #expect(try await dossier.lire(nom) == Data("deux".utf8))
    }
}
