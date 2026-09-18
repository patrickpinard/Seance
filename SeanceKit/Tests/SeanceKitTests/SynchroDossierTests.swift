import Foundation
import Testing
@testable import SeanceKit

@Suite("Synchronisation par un dossier")
struct SynchroDossierTests {
    private let t0 = Date(timeIntervalSince1970: 1_789_000_000)

    @Test func seulsLesFichiersDesAutresAppareilsQuiOntChange() {
        let propre = SynchroDossier.nomFichier(appareil: "iPhone 3F2A")
        #expect(propre == "Séance — iPhone 3F2A.json")
        let fichiers = [
            SynchroDossier.Fichier(nom: propre, modifieLe: t0.addingTimeInterval(500)),
            SynchroDossier.Fichier(nom: "Séance — iPad 77C1.json", modifieLe: t0.addingTimeInterval(100)),
            SynchroDossier.Fichier(nom: "Séance — Mac 0B9E.json", modifieLe: t0.addingTimeInterval(50)),
            // Une sauvegarde exportée à la main, une photo : pas des fichiers d'appareil.
            SynchroDossier.Fichier(nom: "Séance 2026-09-18.json", modifieLe: t0.addingTimeInterval(900)),
            SynchroDossier.Fichier(nom: "IMG_0042.jpg", modifieLe: t0),
        ]
        let premiers = SynchroDossier.aImporter(fichiers, propre: propre, dejaImportes: [:])
        #expect(premiers.map(\.nom) == ["Séance — Mac 0B9E.json", "Séance — iPad 77C1.json"])

        // Le Mac n'a pas bougé depuis son import ; l'iPad, si.
        let deja = ["Séance — Mac 0B9E.json": t0.addingTimeInterval(50), "Séance — iPad 77C1.json": t0.addingTimeInterval(10)]
        #expect(SynchroDossier.aImporter(fichiers, propre: propre, dejaImportes: deja).map(\.nom) == ["Séance — iPad 77C1.json"])
    }

    @Test func fichierPasEncoreTelecharge() {
        #expect(SynchroDossier.nomReel(".Séance — iPad 77C1.json.icloud") == "Séance — iPad 77C1.json")
        #expect(SynchroDossier.nomReel("Séance — iPad 77C1.json") == "Séance — iPad 77C1.json")
        let fichiers = [SynchroDossier.Fichier(nom: ".Séance — iPad 77C1.json.icloud", modifieLe: t0)]
        #expect(SynchroDossier.aImporter(fichiers, propre: "Séance — Mac 0B9E.json", dejaImportes: [:]).map(\.nom) == ["Séance — iPad 77C1.json"])
    }
}
