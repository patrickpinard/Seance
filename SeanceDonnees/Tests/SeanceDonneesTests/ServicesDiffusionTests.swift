import Foundation
import SeanceKit
import SwiftData
import Testing
@testable import SeanceDonnees

/// Sert un fichier XMLTV compressé comme le ferait XML TV Fr.
private actor ServeurXMLTV: TransportHTTP {
    private let corps: Data

    init(xml: String) {
        corps = ServeurXMLTV.gzip(Data(xml.utf8))
    }

    func envoyer(_ requete: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (corps, HTTPURLResponse(url: requete.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    /// En-tête gzip minimal, flux DEFLATE brut, puis CRC (non vérifié à la lecture) et taille.
    static func gzip(_ donnees: Data) -> Data {
        var resultat = Data([0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0x03])
        resultat.append(try! (donnees as NSData).compressed(using: .zlib) as Data)
        resultat.append(contentsOf: [0, 0, 0, 0])
        let taille = UInt32(donnees.count)
        resultat.append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: taille >> ($0 * 8)) })
        return resultat
    }
}

private actor RechercheFixe: RechercheTMDB {
    func rechercherFilms(_ texte: String, page: Int) async throws -> PageTMDB<FilmResume> {
        let json = texte == "La chute de Londres"
            ? #"[{"id": 267860, "title": "La Chute de Londres", "original_title": "London Has Fallen", "original_language": "en", "overview": "", "genre_ids": [28], "vote_average": 6.3, "vote_count": 5000, "popularity": 30, "release_date": "2016-03-02"}]"#
            : "[]"
        return try JSONDecoder().decode(PageTMDB<FilmResume>.self, from: Data(#"{"page": 1, "results": \#(json), "total_pages": 1, "total_results": 1}"#.utf8))
    }

    func rechercherSeries(_ texte: String, page: Int) async throws -> PageTMDB<SerieResume> {
        try JSONDecoder().decode(PageTMDB<SerieResume>.self, from: Data(#"{"page": 1, "results": [], "total_pages": 1, "total_results": 0}"#.utf8))
    }
}

@Suite("Programmes TV et disponibilité en magasin")
@MainActor
struct ServicesDiffusionTests {
    private let maintenant = Date(timeIntervalSince1970: 1_789_660_800) // 17.09.2026 18:00 en Suisse

    private let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv>
      <channel id="M6.fr"><display-name>M6</display-name></channel>
      <channel id="TF1.fr"><display-name>TF1</display-name></channel>
      <programme start="20260917211000 +0200" stop="20260917225500 +0200" channel="M6.fr">
        <title>La chute de Londres</title><date>2016</date><category>Film</category>
      </programme>
      <programme start="20260917140000 +0200" stop="20260917153000 +0200" channel="M6.fr">
        <title>La chute de Londres</title><date>2016</date><category>Film</category>
      </programme>
      <programme start="20260917211000 +0200" stop="20260917230000 +0200" channel="TF1.fr">
        <title>Inconnu au bataillon</title><date>2001</date><category>Film</category>
      </programme>
    </tv>
    """

    @Test func actualiserNeGardeQueLesDiffusionsARattacheesEtAVenir() async throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let contexte = conteneur.mainContext
        contexte.insert(Chaine(identifiantGuide: "M6.fr", nom: "M6", source: .xmltvfr))
        contexte.insert(Chaine(identifiantGuide: "TF1.fr", nom: "TF1", source: .xmltvfr))
        try contexte.save()

        let service = ServiceProgrammesTV(
            contexte: contexte,
            guide: GuideTVClient(transport: ServeurXMLTV(xml: xml)),
            rattachement: RattachementGuide(recherche: RechercheFixe())
        )
        let rapport = try await service.actualiser(maintenant: maintenant)
        #expect(rapport == ServiceProgrammesTV.Rapport(
            programmesLus: 2, diffusionsEnregistrees: 1, recherchesEnEchec: 0,
            filmsLus: 2, filmsRattaches: 1, filmsNonRattaches: ["Inconnu au bataillon"],
            filmsNonReconnus: [.init(titre: "Inconnu au bataillon", annee: 2001)]
        ))

        // Une seconde actualisation remplace au lieu d'accumuler.
        try await service.actualiser(maintenant: maintenant)
        let diffusions = try contexte.fetch(FetchDescriptor<Diffusion>())
        #expect(diffusions.map(\.tmdbID) == [267_860])

        let disponibilite = ServiceDisponibilite(contexte: contexte)
        let chute = ReferenceTitre(type: .film, tmdbID: 267_860)
        guard case .aLaTeleBientot(let diffusion) = try disponibilite.etat(chute, offres: nil, maintenant: maintenant) else {
            Issue.record("La diffusion de ce soir aurait dû être proposée")
            return
        }
        #expect(diffusion.chaine == "M6")
    }

    @Test func chainesParDefautEtRythmeDeLecture() throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let contexte = conteneur.mainContext
        #expect(try ServiceProgrammesTV.preparerChaines(contexte))
        #expect(try ServiceProgrammesTV.chainesActives(contexte).contains("RTSUn.ch"))
        // Une fois les chaînes réglées, un choix de Patrick n'est plus jamais écrasé.
        try contexte.fetch(FetchDescriptor<Chaine>()).forEach { $0.active = false }
        #expect(try ServiceProgrammesTV.preparerChaines(contexte) == false)
        #expect(try ServiceProgrammesTV.chainesActives(contexte).isEmpty)

        let lues = ["M6.fr", "RTSUn.ch"]
        #expect(ServiceProgrammesTV.doitActualiser(derniereLecture: nil, chainesLues: nil, chainesActives: lues))
        #expect(!ServiceProgrammesTV.doitActualiser(derniereLecture: maintenant, chainesLues: lues, chainesActives: lues,
                                                    maintenant: maintenant.addingTimeInterval(3600)))
        #expect(ServiceProgrammesTV.doitActualiser(derniereLecture: maintenant, chainesLues: lues, chainesActives: lues,
                                                   maintenant: maintenant.addingTimeInterval(13 * 3600)))
        #expect(ServiceProgrammesTV.doitActualiser(derniereLecture: maintenant, chainesLues: ["M6.fr"], chainesActives: lues,
                                                   maintenant: maintenant.addingTimeInterval(60)))
    }

    @Test func leNASEtLesAbonnementsDuMagasin() throws {
        let conteneur = try EntrepotSeance.conteneur(.memoire)
        let contexte = conteneur.mainContext
        let heat = ReferenceTitre(type: .film, tmdbID: 949)
        contexte.insert(FichierNAS(chemin: "/Films/Heat (1995) 1080p.mkv", type: .film, tmdbID: 949, qualite: "1080p"))
        contexte.insert(FichierNAS(chemin: "/Films/Heat (1995) 2160p.mkv", type: .film, tmdbID: 949, qualite: "4K"))
        let netflix = Abonnement(providerID: 8, nom: "Netflix")
        contexte.insert(netflix)
        try contexte.save()

        let service = ServiceDisponibilite(contexte: contexte)
        #expect(try service.etat(heat, offres: nil, maintenant: maintenant) == .surNAS(qualite: .uhd4K))

        let offres = try JSONDecoder().decode(OffresRegion.self, from: Data(#"{"flatrate": [{"provider_id": 8, "provider_name": "Netflix", "display_priority": 1}]}"#.utf8))
        let taken = ReferenceTitre(type: .film, tmdbID: 8681)
        guard case .dansAbonnements(let fournisseurs) = try service.etat(taken, offres: offres, maintenant: maintenant) else {
            Issue.record("Netflix est coché")
            return
        }
        #expect(fournisseurs.map(\.nom) == ["Netflix"])

        netflix.actif = false
        try contexte.save()
        #expect(try service.etat(taken, offres: offres, maintenant: maintenant) == .introuvable)
    }
}
