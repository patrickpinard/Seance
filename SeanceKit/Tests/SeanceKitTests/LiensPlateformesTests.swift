import Foundation
import Testing
@testable import SeanceKit

@Suite("Liens vers les plateformes")
struct LiensPlateformesTests {
    @Test func rechercheSurLaPlateforme() {
        #expect(LiensPlateformes.lien(plateforme: 8, titre: "Reacher")?.absoluteString == "https://www.netflix.com/search?q=Reacher")
        #expect(LiensPlateformes.lien(plateforme: 350, titre: "Ted Lasso")?.absoluteString == "https://tv.apple.com/search?term=Ted%20Lasso")
    }

    @Test func titreAvecSignesEtAccents() {
        let lien = LiensPlateformes.lien(plateforme: 9, titre: " Tom & Jerry : l'été ? ")
        #expect(lien?.absoluteString == "https://www.primevideo.com/search?phrase=Tom%20%26%20Jerry%20:%20l'%C3%A9t%C3%A9%20%3F")
    }

    @Test func plateformeInconnueOuTitreVide() {
        #expect(LiensPlateformes.lien(plateforme: 999_999, titre: "Heat") == nil)
        #expect(LiensPlateformes.lien(plateforme: 8, titre: "  ") == nil)
    }

    // MARK: - Liens directs (6.1)

    private let johnWick2 = ReferenceTitre(type: .film, tmdbID: 324552)
    private let strangerThings = ReferenceTitre(type: .serie, tmdbID: 66732)

    @Test func lectureDeLaReponseDeWikidata() throws {
        let lus = try RequeteWikidata.lire(Fixture.donnees("wikidata-identifiants"))
        #expect(lus.count == 6)
        #expect(lus[johnWick2] == IdentifiantsPlateformes(netflix: "80131552", appleTV: "umc.cmc.dwfq3iu2xmm7lkzh4ao9cxpp", prime: "B01MUZ1MIA"))
        #expect(lus[ReferenceTitre(type: .film, tmdbID: 550)]?.disney == "38HCX4uW3BlA")
        #expect(lus[strangerThings]?.netflix == "80057281")
        #expect(lus[ReferenceTitre(type: .serie, tmdbID: 84958)]?.disney == "6pARMvILBGzF")
        #expect(lus[ReferenceTitre(type: .film, tmdbID: 999_999_999)] == nil)
    }

    @Test func requeteFilmsEtSeriesEnUnLot() {
        let requete = RequeteWikidata.requete([johnWick2, strangerThings])
        let texte = RequeteWikidata.sparql([johnWick2, strangerThings])
        #expect(texte.contains("VALUES ?film { \"324552\" }"))
        #expect(texte.contains("VALUES ?serie { \"66732\" }"))
        #expect(texte.contains("UNION"))
        #expect(!RequeteWikidata.sparql([johnWick2]).contains("?serie {"))
        #expect(requete.url?.host() == "query.wikidata.org")
        #expect(requete.value(forHTTPHeaderField: "Accept") == "application/sparql-results+json")
        #expect(requete.value(forHTTPHeaderField: "User-Agent") == "Seance/6.1 (application personnelle)")
    }

    @Test func identifiantsInattendusEcartes() {
        #expect(RequeteWikidata.propre("80131552") == "80131552")
        #expect(RequeteWikidata.propre("umc.cmc.dwfq3iu2xmm7lkzh4ao9cxpp") != nil)
        #expect(RequeteWikidata.propre("../../x?y") == nil)
        #expect(RequeteWikidata.propre("abc def") == nil)
        #expect(RequeteWikidata.propre("") == nil)
    }

    @Test func lienDirectParPlateforme() {
        let ids = IdentifiantsPlateformes(netflix: "80131552", appleTV: "umc.cmc.x1", disney: "38HCX4uW3BlA", prime: "B01MUZ1MIA")
        #expect(LiensPlateformes.direct(plateforme: 8, reference: johnWick2, identifiants: ids)?.absoluteString == "https://www.netflix.com/watch/80131552")
        #expect(LiensPlateformes.direct(plateforme: 8, reference: strangerThings, identifiants: ids)?.absoluteString == "https://www.netflix.com/title/80131552")
        #expect(LiensPlateformes.direct(plateforme: 350, reference: johnWick2, identifiants: ids)?.absoluteString == "https://tv.apple.com/ch/movie/umc.cmc.x1?action=play")
        #expect(LiensPlateformes.direct(plateforme: 2, reference: strangerThings, identifiants: ids)?.absoluteString == "https://tv.apple.com/ch/show/umc.cmc.x1")
        #expect(LiensPlateformes.direct(plateforme: 337, reference: johnWick2, identifiants: ids)?.absoluteString == "https://www.disneyplus.com/movies/wd/38HCX4uW3BlA")
        #expect(LiensPlateformes.direct(plateforme: 337, reference: strangerThings, identifiants: ids)?.absoluteString == "https://www.disneyplus.com/series/wp/38HCX4uW3BlA")
        // Prime Video : les références de Wikidata sont celles d'Amazon.com, la recherche reste.
        #expect(LiensPlateformes.direct(plateforme: 9, reference: johnWick2, identifiants: ids) == nil)
        #expect(LiensPlateformes.lien(plateforme: 9, titre: "Heat", reference: johnWick2, identifiants: ids)?.absoluteString
                == "https://www.primevideo.com/search?phrase=Heat")
    }

    @Test func sansIdentifiantLaRecherche() {
        let lien = LiensPlateformes.lien(plateforme: 8, titre: "Reacher", reference: strangerThings, identifiants: IdentifiantsPlateformes(appleTV: "umc.cmc.x"))
        #expect(lien?.absoluteString == "https://www.netflix.com/search?q=Reacher")
        #expect(LiensPlateformes.lien(plateforme: 8, titre: "Reacher", reference: strangerThings, identifiants: nil)?.absoluteString
                == "https://www.netflix.com/search?q=Reacher")
    }

    @Test func reserveGardeEtRegroupe() async throws {
        let reponse = try Fixture.donnees("wikidata-identifiants")
        let transport = TransportSimule([.init(code: 200, corps: reponse), .init(code: 200, corps: reponse)])
        let reserve = ReserveIdentifiants(transport: transport, fichier: nil)
        let inconnu = ReferenceTitre(type: .film, tmdbID: 999_999_999)
        // Deux demandes simultanées : John Wick ne part qu'une fois, la seconde attend le même lot.
        async let premier = reserve.identifiants([johnWick2, inconnu])
        async let second = reserve.identifiants([johnWick2, strangerThings])
        let (a, b) = await (premier, second)
        #expect(a[johnWick2]?.netflix == "80131552")
        #expect(a[inconnu] == nil)
        #expect(b[johnWick2]?.netflix == "80131552")
        #expect(b[strangerThings]?.netflix == "80057281")
        let textes = await transport.requetes.compactMap { $0.url?.absoluteString.removingPercentEncoding }
        #expect(textes.filter { $0.contains("324552") }.count == 1)
        // Déjà connu : plus de réseau.
        let avant = await transport.requetes.count
        let encore = await reserve.identifiants([johnWick2, inconnu])
        #expect(encore[johnWick2]?.appleTV == "umc.cmc.dwfq3iu2xmm7lkzh4ao9cxpp")
        #expect(await transport.requetes.count == avant)
        #expect(await reserve.connus(inconnu)?.estVide == true)
    }

    @Test func reservePerimeeEtErreurReseau() async throws {
        let reponse = try Fixture.donnees("wikidata-identifiants")
        let transport = TransportSimule([.init(code: 503), .init(code: 200, corps: reponse)])
        let reserve = ReserveIdentifiants(transport: transport, fichier: nil)
        // Erreur : rien n'est gardé, la demande suivante repart.
        #expect(await reserve.identifiants([johnWick2]).isEmpty)
        #expect(await reserve.connus(johnWick2) == nil)
        let lu = await reserve.identifiants([johnWick2], maintenant: .iso("2026-09-22T12:00:00Z"))
        #expect(lu[johnWick2]?.netflix == "80131552")
        // Trente jours plus tard, le titre est redemandé (et le transport n'a plus rien : on garde l'ancien).
        let plusTard = await reserve.identifiants([johnWick2], maintenant: .iso("2026-10-30T12:00:00Z"))
        #expect(plusTard.isEmpty)
        #expect(await transport.requetes.count == 3)
    }

    @Test func reserveSansReseau() async {
        let reserve = ReserveIdentifiants(transport: nil, fichier: nil)
        #expect(await reserve.identifiants([johnWick2]).isEmpty)
    }

    @Test func reserveGardeSurLeDisque() async throws {
        let fichier = FileManager.default.temporaryDirectory.appending(path: "identifiants-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fichier) }
        let transport = TransportSimule([.init(code: 200, corps: try Fixture.donnees("wikidata-identifiants"))])
        _ = await ReserveIdentifiants(transport: transport, fichier: fichier).identifiants([johnWick2])
        let relue = ReserveIdentifiants(transport: nil, fichier: fichier)
        #expect(await relue.connus(johnWick2)?.netflix == "80131552")
    }

    @Test func chainesDansBlueTV() {
        #expect(LiensChaines.numero(chaine: "RTSUn.ch") == 369)
        #expect(LiensChaines.numero(chaine: "Inconnue.fr") == nil)
        // Toutes les chaînes que Séance propose ont leur numéro.
        #expect(ChaineGuide.catalogue.allSatisfy { LiensChaines.numero(chaine: $0.id) != nil })
    }
}


/// Le vrai Wikidata : `SEANCE_WIKIDATA_REEL=1 outils/tester.sh --filter "Wikidata réel"`.
@Suite("Wikidata réel", .enabled(if: ProcessInfo.processInfo.environment["SEANCE_WIKIDATA_REEL"] != nil))
struct WikidataReelTests {
    @Test func johnWickEtStrangerThings() async {
        let johnWick2 = ReferenceTitre(type: .film, tmdbID: 324552)
        let strangerThings = ReferenceTitre(type: .serie, tmdbID: 66732)
        let lus = await ReserveIdentifiants(transport: URLSession.shared, fichier: nil).identifiants([johnWick2, strangerThings])
        #expect(lus[johnWick2]?.netflix == "80131552")
        #expect(lus[strangerThings]?.netflix == "80057281")
        #expect(lus[strangerThings]?.appleTV?.hasPrefix("umc.cmc.") == true)
    }
}

/// blue TV (6.3) : l'app s'ouvre par son adresse `tvguide://`, sur l'émission en cours quand le catalogue public la donne.
@Suite("blue TV")
struct BlueTVTests {
    @Test func adresseDeLApp() {
        #expect(LiensChaines.appBlueTV(emission: "t0369167512d3a40")?.absoluteString == "tvguide://T=tvguide&I=t0369167512d3a40&AssetType=tvBroadcast")
        #expect(LiensChaines.appBlueTV()?.absoluteString == "tvguide://T=tvguide")
        // Un identifiant inattendu ne compose pas une adresse : l'app s'ouvre sur son guide.
        #expect(LiensChaines.appBlueTV(emission: "t036&x=1")?.absoluteString == "tvguide://T=tvguide")
        #expect(LiensChaines.numero(chaine: "RTSUn.ch") == 369)
        #expect(LiensChaines.siteBlueTV(chaine: "TF1.fr")?.absoluteString == "https://tv.blue.ch/player/livetv/601")
        #expect(LiensChaines.siteBlueTV(chaine: "Inconnue.ch") == nil)
    }

    @Test func requeteDuCatalogue() {
        let requete = CatalogueBlueTV.requete(chaine: 369, autour: .iso("2026-09-22T18:30:00Z"))
        let adresse = requete.url?.absoluteString.removingPercentEncoding ?? ""
        #expect(adresse.contains("ids=369") && adresse.contains("start=202609221829") && adresse.contains("end=202609221831"))
        #expect(requete.value(forHTTPHeaderField: "User-Agent")?.contains("Seance") == true)
    }

    @Test func emissionEnCours() async throws {
        let donnees = try Fixture.donnees("bluetv-emissions")
        // Le créneau de la fixture : « A bon entendeur » sur RTS 1.
        #expect(CatalogueBlueTV.lire(donnees, a: .iso("2026-09-22T18:30:00Z")) == "t03690bf3a92e397")
        // Hors créneau : la première émission connue, faute de mieux.
        #expect(CatalogueBlueTV.lire(donnees, a: .iso("2020-01-01T00:00:00Z")) == "t03690bf3a92e397")
        #expect(CatalogueBlueTV.lire(Data("rien".utf8), a: .now) == nil)
        let transport = TransportSimule([.init(code: 200, corps: donnees)])
        #expect(await CatalogueBlueTV(transport: transport).emission(chaine: 369, a: .iso("2026-09-22T18:30:00Z")) == "t03690bf3a92e397")
        #expect(await CatalogueBlueTV(transport: TransportSimule([.init(code: 500)])).emission(chaine: 369) == nil)
    }
}
