import Foundation
import Testing
@testable import SeanceKit

@Suite("Relais vidéo local")
struct RelaisVideoTests {
    /// Un fichier de deux mégaoctets et quelques, pour que le relais ait plusieurs tranches à envoyer.
    private func fichierDEssai() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "relais-\(UUID().uuidString).bin")
        var octets = Data(count: 0)
        for valeur in 0 ..< 2_100_000 { octets.append(UInt8(valeur % 251)) }
        try octets.write(to: url)
        return url
    }

    @Test func liseLEnteteDeRequete() {
        let requete = RelaisVideo.analyser("GET /jeton HTTP/1.1\r\nHost: 127.0.0.1\r\nRange: bytes=100-199\r\n\r\n")
        #expect(requete?.methode == "GET")
        #expect(requete?.chemin == "/jeton")
        #expect(requete?.plage == 100 ..< 200)
        // Une plage ouverte va jusqu'au bout du fichier.
        #expect(RelaisVideo.plage("Range: bytes=512-")?.lowerBound == 512)
        #expect(RelaisVideo.plage("Range: bytes=512-")?.upperBound == UInt64.max)
    }

    @Test func servLeFichierEntierPuisUnePlage() async throws {
        let fichier = try fichierDEssai()
        defer { try? FileManager.default.removeItem(at: fichier) }
        let attendu = try Data(contentsOf: fichier)

        let relais = RelaisVideo(source: SourceVideoFichier(url: fichier), typeMIME: "video/quicktime")
        let adresse = try await relais.demarrer()
        defer { Task { await relais.arreter() } }

        // 1. Tout le fichier : le lecteur commence souvent par là.
        let (entier, reponse) = try await URLSession.shared.data(from: adresse)
        let http = try #require(reponse as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        #expect(http.value(forHTTPHeaderField: "Accept-Ranges") == "bytes")
        #expect(http.value(forHTTPHeaderField: "Content-Type") == "video/quicktime")
        #expect(entier == attendu)

        // 2. Une plage au milieu, comme quand on avance dans la vidéo.
        var requete = URLRequest(url: adresse)
        requete.setValue("bytes=1048576-1048675", forHTTPHeaderField: "Range")
        let (tranche, reponsePlage) = try await URLSession.shared.data(for: requete)
        let httpPlage = try #require(reponsePlage as? HTTPURLResponse)
        #expect(httpPlage.statusCode == 206)
        #expect(httpPlage.value(forHTTPHeaderField: "Content-Range") == "bytes 1048576-1048675/2100000")
        #expect(tranche == attendu[1_048_576 ..< 1_048_676])
    }

    @Test func refuseUneAdresseSansLeBonJeton() async throws {
        let fichier = try fichierDEssai()
        defer { try? FileManager.default.removeItem(at: fichier) }
        let relais = RelaisVideo(source: SourceVideoFichier(url: fichier))
        let adresse = try await relais.demarrer()
        defer { Task { await relais.arreter() } }

        let intrus = adresse.deletingLastPathComponent().appending(path: "au-hasard")
        let (_, reponse) = try await URLSession.shared.data(from: intrus)
        #expect((reponse as? HTTPURLResponse)?.statusCode == 404)
    }
}
