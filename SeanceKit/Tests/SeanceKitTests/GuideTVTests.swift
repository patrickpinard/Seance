import Foundation
import Testing
@testable import SeanceKit

@Suite("Programmes TV")
struct GuideTVTests {
    private func extrait() throws -> Data {
        try Gzip.decompresser(Fixture.donnees("xmltv_extrait.xml", extension: "gz"))
    }

    // MARK: gzip

    @Test func decompresseLeFichierDeXMLTVFr() throws {
        let xml = try #require(String(data: try extrait(), encoding: .utf8))
        #expect(xml.hasPrefix("<?xml"))
        #expect(xml.contains("La chute de Londres"))
    }

    @Test func refuseUnFichierQuiNEstPasGzip() {
        #expect(throws: Gzip.Erreur.enteteInvalide) {
            try Gzip.decompresser(Data("<?xml version=\"1.0\"?><tv/>".utf8))
        }
    }

    @Test func detecteUneTailleIncoherente() throws {
        var octets = [UInt8](try Fixture.donnees("xmltv_extrait.xml", extension: "gz"))
        octets[octets.count - 4] ^= 0xFF
        #expect {
            try Gzip.decompresser(Data(octets))
        } throws: { erreur in
            if case Gzip.Erreur.tailleIncorrecte = erreur { return true }
            return false
        }
    }

    // MARK: XMLTV

    @Test func litChainesEtProgrammes() throws {
        let guide = try XMLTV.lire(try extrait())
        #expect(guide.chaines.map(\.id) == ["TF1.fr", "France2.fr", "M6.fr", "NT1.fr"])
        #expect(guide.chaines.last?.nom == "TFX")
        #expect(guide.programmes.count == 5)
    }

    @Test func filmComplet() throws {
        let guide = try XMLTV.lire(try extrait())
        let film = try #require(guide.programmes.first { $0.titre == "La chute de Londres" })
        #expect(film.chaine == "M6.fr")
        #expect(film.debut == Date.iso("2026-09-17T19:10:00Z"))
        #expect(film.dureeMinutes == 105)
        #expect(film.annee == 2016)
        #expect(film.nature == .film)
        #expect(film.categories == ["Film", "Action"])
        #expect(film.realisateurs == ["Babak Najafi"])
        #expect(film.acteurs == ["Gerard Butler", "Aaron Eckhart", "Morgan Freeman"])
        // L'icône du programme, pas celle de la signalétique CSA.
        #expect(film.image?.host() == "img.bouygtel.fr")
    }

    @Test func episodeDeSerie() throws {
        let guide = try XMLTV.lire(try extrait())
        let episode = try #require(guide.programmes.first { $0.titre == "New York Unité Spéciale" })
        #expect(episode.nature == .serie)
        #expect(episode.saison == 20)
        #expect(episode.episode == 19)
        #expect(episode.sousTitre == "Vous ne pouvez pas embrasser la mariée")
        #expect(episode.acteurs == ["Mariska Hargitay", "Ice-T"])
    }

    @Test func filmSansAnneeEtMagazine() throws {
        let guide = try XMLTV.lire(try extrait())
        #expect(guide.programmes.first { $0.titre == "Que le meilleur gagne !" }?.annee == nil)
        #expect(guide.programmes.first { $0.chaine == "France2.fr" }?.nature == .autre)
    }

    @Test func neGardeQueLesChainesCochees() throws {
        let guide = try XMLTV.lire(try extrait(), chaines: ["M6.fr", "NT1.fr"])
        #expect(guide.chaines.map(\.id) == ["M6.fr", "NT1.fr"])
        #expect(guide.programmes.map(\.titre) == ["La chute de Londres", "Taken 2"])
    }

    @Test func xmlInvalide() {
        #expect {
            try XMLTV.lire(Data("<tv><programme>".utf8))
        } throws: { erreur in
            if case XMLTV.Erreur.xmlInvalide = erreur { return true }
            return false
        }
    }

    @Test(arguments: [
        ("19.18.", "xmltv_ns", 20, 19),
        ("0.15.0/1", "xmltv_ns", 1, 16),
        ("1/3.0.", "xmltv_ns", 2, 1),
        ("S02E05", "onscreen", 2, 5),
    ] as [(String, String, Int, Int)])
    func numerotationDesEpisodes(texte: String, systeme: String, saison: Int, episode: Int) {
        let numero = XMLTV.numeroEpisode(texte, systeme: systeme)
        #expect(numero.saison == saison)
        #expect(numero.episode == episode)
    }

    @Test func dateSansDecalageEnHeureDeParis() {
        #expect(XMLTV.date("20260917211000") == Date.iso("2026-09-17T19:10:00Z"))
    }

    // MARK: client

    @Test func clientNeGardeQueFilmsEtSeries() async throws {
        let transport = TransportSimule([.init(code: 200, corps: try Fixture.donnees("xmltv_extrait.xml", extension: "gz"))])
        let guide = try await GuideTVClient(transport: transport)
            .programmes(chaines: ["TF1.fr", "France2.fr", "M6.fr"])

        #expect(guide.programmes.map(\.titre).sorted() == ["La chute de Londres", "New York Unité Spéciale", "Que le meilleur gagne !"])
        let requete = try #require(await transport.requetes.first)
        #expect(requete.url?.absoluteString == "https://xmltvfr.fr/xmltv/xmltv_tnt.xml.gz")
    }

    @Test func clientErreurHTTP() async throws {
        let transport = TransportSimule([.init(code: 503)])
        await #expect(throws: ErreurGuideTV.http(code: 503)) {
            _ = try await GuideTVClient(transport: transport).programmes(chaines: ["M6.fr"])
        }
    }
}
