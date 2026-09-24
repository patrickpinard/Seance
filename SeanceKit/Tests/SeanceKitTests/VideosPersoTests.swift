import Foundation
import Testing
@testable import SeanceKit

@Suite("Vidéos personnelles")
struct VideosPersoTests {
    private func jour(_ j: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + j * 86_400)) }

    private var arbre: ArbreVideosPerso {
        ArbreVideosPerso([
            VideoPerso(chemin: "2023/Noël/Sapin.mov", taille: 10, modifieLe: jour(10)),
            VideoPerso(chemin: "2023/Noël/Cadeaux.mp4", taille: 10, modifieLe: jour(11)),
            VideoPerso(chemin: "2023/Été.mov", taille: 10, modifieLe: jour(5)),
            VideoPerso(chemin: "2024/Ski/Descente.mov", taille: 10, modifieLe: jour(40)),
            VideoPerso(chemin: "Accueil.mp4", taille: 10, modifieLe: jour(1)),
        ])
    }

    @Test func racine() {
        #expect(arbre.dossiers(dans: "").map(\.nom) == ["2024", "2023"])   // le plus récemment alimenté d'abord
        #expect(arbre.dossiers(dans: "").first { $0.nom == "2023" }?.nombre == 3)
        #expect(arbre.videos(dans: "").map(\.nom) == ["Accueil"])
    }

    @Test func sousDossier() {
        #expect(arbre.dossiers(dans: "2023").map(\.chemin) == ["2023/Noël"])
        #expect(arbre.videos(dans: "2023").map(\.nom) == ["Été"])
        #expect(arbre.videos(dans: "2023/Noël").map(\.nom) == ["Cadeaux", "Sapin"])
        #expect(arbre.dossiers(dans: "2023/Noël").isEmpty)
    }

    /// « 2023 » ne doit pas avaler « 2023 bis ».
    @Test func prefixeExact() {
        let arbre = ArbreVideosPerso([VideoPerso(chemin: "2023 bis/A.mov", taille: 1), VideoPerso(chemin: "2023/B.mov", taille: 1)])
        #expect(arbre.videos(dans: "2023").map(\.nom) == ["B"])
        #expect(arbre.dossiers(dans: "2023").isEmpty)
    }

    @Test func recentesEtNoms() {
        #expect(arbre.recentes(2).map(\.nom) == ["Descente", "Cadeaux"])
        #expect(VideoPerso(chemin: "2023/Noël 2023.final.mov", taille: 1).nom == "Noël 2023.final")
    }

    @Test func reglages() {
        let films = ReglagesNAS(hote: "192.168.1.220", partage: "Films", dossiers: ["Films"], utilisateur: "admin")
        let videos = ReglagesVideosPerso.depuis(films)
        #expect(!videos.actif && videos.estComplet)
        #expect(videos.acces.partage == "video" && videos.acces.dossiers.isEmpty)
        #expect(videos.partageLeCompte(de: films))
        var ailleurs = videos
        ailleurs.acces.hote = "192.168.1.50"
        #expect(!ailleurs.partageLeCompte(de: films))
    }
}

@Suite("Lecture d'une vidéo personnelle")
struct LectureVideoPersoTests {
    private let acces = ReglagesNAS(hote: "192.168.1.220", partage: "video", dossiers: [], utilisateur: "admin")

    /// Une vidéo de famille n'a pas de fiche TMDB : elle ne peut pas s'ouvrir dans la bibliothèque d'Infuse, seulement
    /// par son adresse. Les deux lecteurs savent recevoir une adresse ; c'est Infuse qui décidera de la lire ou non.
    @Test func parSonAdresse() throws {
        let video = try #require(acces.url(chemin: "2026/Noël.mov", motDePasse: "secret"))
        let infuse = try #require(LecteurVideo.infuse.lien(pour: video))
        let vlc = try #require(LecteurVideo.vlc.lien(pour: video))
        #expect(infuse.absoluteString.hasPrefix("infuse://x-callback-url/play?url="))
        #expect(vlc.absoluteString.hasPrefix("vlc-x-callback://x-callback-url/stream?url="))
        // 6.5 : le lecteur ramène à Séance quand la vidéo est finie.
        #expect(infuse.absoluteString.hasSuffix("&x-success=seance%3A%2F%2F"))
        #expect(vlc.absoluteString.hasSuffix("&x-success=seance%3A%2F%2F"))
        // L'adresse voyage encodée : ni « / » ni « : » ne cassent le lien, et le mot de passe y est.
        #expect(!infuse.absoluteString.contains("smb://"))
        #expect(infuse.absoluteString.contains("secret"))
    }
}

/// Piste B (6.2) : les albums de souvenirs, leurs icônes et leurs couvertures choisies.
@Suite("Albums de souvenirs")
struct AlbumsSouvenirsTests {
    private func jour(_ j: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(1_780_000_000 + j * 86_400)) }

    private var arbre: ArbreVideosPerso {
        ArbreVideosPerso([
            VideoPerso(chemin: "2026/Vacances d'été/Plage, premier jour.mov", taille: 1_400, modifieLe: jour(10)),
            VideoPerso(chemin: "2026/Vacances d'été/Coucher de soleil.mov", taille: 600, modifieLe: jour(12)),
            VideoPerso(chemin: "2026/Anniversaire de Camille.mp4", taille: 2_100, modifieLe: jour(50)),
            VideoPerso(chemin: "2025/Noël/Le sapin.mov", taille: 900, modifieLe: jour(-200)),
            VideoPerso(chemin: "Film de famille 2010-2020.mp4", taille: 5_000, modifieLe: jour(-600)),
        ])
    }

    @Test func unDossierEstUnAlbumUneVideoSeuleFaitCarteASoi() {
        let albums = arbre.albums()
        #expect(albums.count == 4)
        let vacances = albums.first { $0.id == "2026/Vacances d'été" }
        #expect(vacances?.titre == "Vacances d'été" && vacances?.videos.map(\.nom) == ["Plage, premier jour", "Coucher de soleil"])
        #expect(vacances?.estVideoSeule == false && vacances?.taille == 2_000)
        let anniversaire = albums.first { $0.id == "2026/Anniversaire de Camille.mp4" }
        #expect(anniversaire?.estVideoSeule == true && anniversaire?.titre == "Anniversaire de Camille")
    }

    @Test func iconesProposeesDApresLeNom() {
        let albums = Dictionary(uniqueKeysWithValues: arbre.albums().map { ($0.titre, $0.symbole) })
        #expect(albums["Vacances d'été"] == "beach.umbrella.fill")
        #expect(albums["Anniversaire de Camille"] == "birthday.cake.fill")
        #expect(albums["Noël"] == "tree.fill")
        #expect(albums["Film de famille 2010-2020"] == "film.stack")
        #expect(IconesSouvenirs.suggerer("Ski à Verbier") == "figure.skiing.downhill")
        #expect(IconesSouvenirs.suggerer("Premiers pas de Léo") == "stroller.fill")
        #expect(IconesSouvenirs.suggerer("Anniversaire à la plage") == "birthday.cake.fill")
        // Un mot entier : « mer », pas « merveilleux » ni « mercredi » ; « chat », pas « château ».
        #expect(IconesSouvenirs.suggerer("Un merveilleux mercredi") == nil)
        #expect(IconesSouvenirs.suggerer("Visite du château") == "airplane")
        #expect(IconesSouvenirs.suggerer("Au bord de la mer") == "beach.umbrella.fill")
        #expect(IconesSouvenirs.suggerer("IMG_0042") == nil)
        #expect(IconesSouvenirs.toutes.count == 24 && Set(IconesSouvenirs.toutes.map(\.symbole)).count == 24)
    }

    @Test func rangesParAnneeLaPlusRecenteDAbord() {
        let sections = ArbreVideosPerso.parAnnee(arbre.albums())
        #expect(sections.map(\.titre) == ["2026", "2025", "2020"])
        // « 2026 » : l'anniversaire, plus récent que les vacances, passe devant.
        #expect(sections[0].albums.map(\.titre) == ["Anniversaire de Camille", "Vacances d'été"])
    }

    @Test func laCouvertureChoisieLEmporte() {
        var couvertures = CouverturesSouvenirs()
        let date = jour(-300)
        couvertures.choisir("2026/Vacances d'été", symbole: "sailboat.fill", titre: "  Croisière en Grèce ", date: date, le: jour(0))
        let album = arbre.albums(couvertures: couvertures).first { $0.id == "2026/Vacances d'été" }
        #expect(album?.symbole == "sailboat.fill" && album?.titre == "Croisière en Grèce")
        #expect(album?.debut == date && album?.fin == date)
        // La date choisie range l'album dans son année.
        #expect(ArbreVideosPerso.parAnnee(arbre.albums(couvertures: couvertures)).first { $0.albums.contains { $0.id == album?.id } }?.titre == "2025")
        // Une vidéo : son icône, celle que son nom évoque, sinon celle de l'album.
        let plage = arbre.videos.first { $0.nom == "Plage, premier jour" }!
        let coucher = arbre.videos.first { $0.nom == "Coucher de soleil" }!
        #expect(ArbreVideosPerso.symbole(de: plage, dans: album!, couvertures: couvertures) == "beach.umbrella.fill")
        #expect(ArbreVideosPerso.symbole(de: coucher, dans: album!, couvertures: couvertures) == "sparkles")
        couvertures.retablir("2026/Vacances d'été", le: jour(1))
        #expect(arbre.albums(couvertures: couvertures).first { $0.id == "2026/Vacances d'été" }?.symbole == "beach.umbrella.fill")
    }

    @Test func periodeDUnAlbum() {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = .suisse
        let premier = Date.suisse("2026-08-01 10:00"), trois = Date.suisse("2026-08-03 18:00")
        #expect(AlbumSouvenirs.periode(premier, premier, calendrier: calendrier) == "1 août 2026")
        #expect(AlbumSouvenirs.periode(premier, trois, calendrier: calendrier) == "1 – 3 août 2026")
        #expect(AlbumSouvenirs.periode(Date.suisse("2026-06-03 10:00"), trois, calendrier: calendrier) == "3 juin – 3 août 2026")
        #expect(AlbumSouvenirs.periode(Date.suisse("2025-06-03 10:00"), trois, calendrier: calendrier) == "juin 2025 – août 2026")
        #expect(AlbumSouvenirs.periode(nil, nil, calendrier: calendrier) == nil)
        // Copiée sur le NAS un an plus tard : l'album de « 2025 » ne montre que l'année, pas la date de la copie.
        let copie = ArbreVideosPerso([VideoPerso(chemin: "2025/Ski à Verbier.mp4", taille: 1, modifieLe: Date.suisse("2026-02-14 10:00"))])
            .albums(calendrier: calendrier)[0]
        #expect(copie.annee == 2025 && copie.debut == nil && copie.periode == "2025")
    }

    @Test func fusionEntreeParEntreeLaPlusRecenteGagne() {
        var ici = CouverturesSouvenirs()
        ici.choisir("A", symbole: "heart.fill", titre: nil, date: nil, le: jour(5))
        ici.choisir("B", symbole: "gift.fill", titre: nil, date: nil, le: jour(1))
        var ailleurs = CouverturesSouvenirs()
        ailleurs.choisir("A", symbole: "tree.fill", titre: nil, date: nil, le: jour(2))    // plus ancien : ignoré
        ailleurs.retablir("B", le: jour(3))                                                // plus récent : rétabli
        ailleurs.choisir("C", symbole: "airplane", titre: "Rome", date: nil, le: jour(4))  // nouveau
        let change = ici.fusionner(ailleurs)
        #expect(change)
        #expect(ici.couverture("A")?.symbole == "heart.fill")
        #expect(ici.couverture("B") == nil)
        #expect(ici.couverture("C")?.titre == "Rome")
        let encore = ici.fusionner(ailleurs)
        #expect(!encore)
        // Aller-retour par les réglages synchronisés.
        #expect(CouverturesSouvenirs(donnees: ici.encoder()) == ici)
        #expect(CouverturesSouvenirs(donnees: Data("n'importe quoi".utf8)).entrees.isEmpty)
    }
}
