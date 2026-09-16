import Foundation
import Testing
@testable import SeanceKit

@Suite("Noms de fichiers du NAS")
struct AnalyseNomFichierTests {
    typealias Attendu = (type: TypeTitre, titre: String, annee: Int?, episode: String?, qualite: QualiteVideo?, tmdb: Int?)

    @Test(arguments: [
        ("/Films/John Wick (2014) 2160p.mkv", (.film, "John Wick", 2014, nil, .uhd4K, nil)),
        ("/Films/La.Chute.de.Londres.2016.1080p.BluRay.x264.mkv", (.film, "La Chute de Londres", 2016, nil, .hd1080, nil)),
        ("/Films/1917 (2019)/1917 (2019) [tmdbid-530915].mp4", (.film, "1917", 2019, nil, nil, 530_915)),
        ("/Séries/Reacher (2022)/Season 01/Reacher - S01E03 - Spoonful.mkv", (.serie, "Reacher", nil, "S01E03", nil, nil)),
        ("/Séries/The Night Agent [tmdbid-129552]/Saison 2/S02E05.720p.mkv", (.serie, "The Night Agent", nil, "S02E05", .hd720, 129_552)),
        ("/Séries/Heat/Heat 1x02.avi", (.serie, "Heat", nil, "S01E02", nil, nil)),
    ] as [(String, Attendu)])
    func analyse(chemin: String, attendu: Attendu) throws {
        let fichier = try #require(AnalyseNomFichier.analyser(chemin: chemin))
        #expect(fichier.type == attendu.type)
        #expect(fichier.titre == attendu.titre)
        #expect(fichier.annee == attendu.annee)
        #expect(fichier.episode?.description == attendu.episode)
        #expect(fichier.qualite == attendu.qualite)
        #expect(fichier.tmdbID == attendu.tmdb)
    }

    @Test(arguments: ["/Films/John Wick (2014)/sample.mkv", "/Films/John Wick (2014)/poster.jpg", "/Films/Heat-trailer.mp4", "/Films/notes.nfo"])
    func ignores(chemin: String) {
        #expect(AnalyseNomFichier.analyser(chemin: chemin) == nil)
    }
}

@Suite("Filtres locaux d'Explorer")
struct FiltresLocauxTests {
    private let maintenant = Date.suisse("2026-09-17 19:00")
    private let film = ReferenceTitre(type: .film, tmdbID: 267_860)

    private func resultat(
        langue: String = "en", vu: Bool = false, etat: EtatDisponibilite = .introuvable,
        diffusions: [DiffusionPrevue] = [], type: TypeTitre = .film, acteurs: Set<Int> = []
    ) -> ContexteResultat {
        ContexteResultat(reference: ReferenceTitre(type: type, tmdbID: 1), langueOriginale: langue, estVu: vu,
                         disponibilite: etat, diffusions: diffusions, acteurs: acteurs)
    }

    private func diffusion(_ debut: String, _ fin: String, chaine: String = "M6.fr") -> DiffusionPrevue {
        DiffusionPrevue(chaine: chaine, debut: Date.suisse(debut), fin: Date.suisse(fin))
    }

    @Test func dejaVuEtObtention() {
        var filtres = FiltresLocaux()
        filtres.dejaVu = .pasVus
        filtres.obtention = .surNAS
        #expect(filtres.retient(resultat(etat: .surNAS(qualite: .hd1080)), maintenant: maintenant))
        #expect(!filtres.retient(resultat(vu: true, etat: .surNAS(qualite: nil)), maintenant: maintenant))
        #expect(!filtres.retient(resultat(etat: .dansAbonnements([])), maintenant: maintenant))
    }

    @Test func langueAssoupliePourLaTele() {
        var filtres = FiltresLocaux()
        let coreen = resultat(langue: "ko", diffusions: [diffusion("2026-09-17 21:10", "2026-09-17 23:00")])
        #expect(!filtres.retient(coreen, maintenant: maintenant))
        filtres.tele = .ceSoir
        #expect(filtres.retient(coreen, maintenant: maintenant))
    }

    @Test func ceSoirEntreVingtEtVingtTroisHeures() {
        var filtres = FiltresLocaux()
        filtres.tele = .ceSoir
        #expect(filtres.retient(resultat(diffusions: [diffusion("2026-09-17 21:10", "2026-09-17 22:55")]), maintenant: maintenant))
        #expect(!filtres.retient(resultat(diffusions: [diffusion("2026-09-17 23:30", "2026-09-18 01:00")]), maintenant: maintenant))
        #expect(!filtres.retient(resultat(diffusions: [diffusion("2026-09-18 21:10", "2026-09-18 22:55")]), maintenant: maintenant))
        filtres.tele = .cetteSemaine
        #expect(filtres.retient(resultat(diffusions: [diffusion("2026-09-22 21:10", "2026-09-22 22:55")]), maintenant: maintenant))
        filtres.chaines = ["TF1.fr"]
        #expect(!filtres.retient(resultat(diffusions: [diffusion("2026-09-22 21:10", "2026-09-22 22:55")]), maintenant: maintenant))
    }

    @Test func acteurPourUneSerie() {
        var filtres = FiltresLocaux()
        filtres.acteursSerie = [6384]
        #expect(filtres.retient(resultat(type: .serie, acteurs: [6384, 1]), maintenant: maintenant))
        #expect(!filtres.retient(resultat(type: .serie, acteurs: [1]), maintenant: maintenant))
        // Pour un film, TMDB a déjà filtré par acteur.
        #expect(filtres.retient(resultat(type: .film), maintenant: maintenant))
    }
}
