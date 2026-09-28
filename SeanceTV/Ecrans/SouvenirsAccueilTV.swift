import SeanceDonnees
import SeanceKit
import SwiftUI

/// « Tes souvenirs » sur l'accueil de la TV (8.2, demande de Patrick) : les dernières vidéos personnelles, à deux clics
/// de l'ouverture — avant, il fallait passer par Regarder › NAS › Vidéos. Un clic lance la vidéo tout de suite ;
/// « Tout voir » ouvre la page des vidéos personnelles pour choisir. Rien quand elles ne sont pas réglées.
struct RangeeSouvenirsTV: View {
    @Environment(EtatTV.self) private var etat
    @Environment(\.ouvrirTV) private var ouvrirTV
    @State private var aLire: VideoPerso?

    /// Les vidéos qui ont une vraie image (8.2, demande de Patrick) — « Lorraine 2002-2013 », « Loulou », « Bresse »… —,
    /// pour les reconnaître d'un coup d'œil : seuls mp4, m4v et mov en donnent une. Les plus récentes d'abord ; celles
    /// dont l'image est déjà tirée passent devant, les autres la demandent et arrivent quand elle est prête.
    private var dernieres: [(video: VideoPerso, album: AlbumSouvenirs)] {
        let candidates = etat.videosPerso.albums
            .flatMap { album in album.videos.map { (video: $0, album: album) } }
            .filter { VignettesSouvenirs.possible($0.video.chemin) }
            .sorted { ($0.video.modifieLe ?? .distantPast) > ($1.video.modifieLe ?? .distantPast) }
        let pretes = candidates.filter { etat.videosPerso.vignettes.vignettes[$0.video.chemin] != nil }
        return Array((pretes.isEmpty ? candidates : pretes).prefix(12))
    }

    /// Demande l'image des candidates, deux à la fois (`VignettesSouvenirs`) : la rangée se remplit à mesure.
    private func demanderLesImages() {
        let motDePasse = etat.videosPerso.motDePasse(films: etat.nas)
        for album in etat.videosPerso.albums {
            for video in album.videos where VignettesSouvenirs.possible(video.chemin) {
                etat.videosPerso.vignettes.demander(video, acces: etat.videosPerso.reglages.acces, motDePasse: motDePasse)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let dernieres = dernieres
            if etat.videosPerso.actif, !dernieres.isEmpty {
                EtagereTV(titre: "Tes souvenirs", sousTitre: "Tes dernières vidéos personnelles : un clic et elle démarre",
                          toutVoir: { ouvrirTV?(DossierVideosTV(chemin: "")) }) {
                    ForEach(dernieres, id: \.video.chemin) { element in
                        let choisie = etat.videosPerso.couvertures.couverture(element.video.chemin)
                        Button { lire(element.video) } label: {
                            CarteLargeTV(surtitre: (choisie?.date ?? element.video.modifieLe).map(VideosPersoTV.date),
                                         titre: choisie?.titre ?? element.video.nom,
                                         detail: element.album.estVideoSeule ? nil : element.album.titre,
                                         cheminImage: nil, largeur: CarteLargeTV.largeurGrille,
                                         icone: ArbreVideosPerso.symbole(de: element.video, dans: element.album, couvertures: etat.videosPerso.couvertures),
                                         vignette: vignette(element.video), lectureEnCoin: true)
                        }
                        .buttonStyle(.card)
                    }
                }
            }
        }
        .task {
            guard etat.videosPerso.actif else { return }
            await etat.videosPerso.lire(films: etat.nas)
            demanderLesImages()
        }
        .fullScreenCover(item: $aLire) { video in
            LecteurVLCTV(video: video, acces: etat.videosPerso.reglages.acces,
                         motDePasse: etat.videosPerso.motDePasse(films: etat.nas) ?? "", surEchec: { _ in
                aLire = nil
                etat.dire("Cette vidéo ne se lit pas ici : essaie depuis « Tout voir ».")
            }, depart: etat.positions.aReprendre(video.chemin)?.secondes, surPosition: { secondes, duree in
                etat.noterPosition(video.chemin, secondes: secondes, duree: duree)
            })
        }
    }

    private func lire(_ video: VideoPerso) {
        guard etat.videosPerso.motDePasse(films: etat.nas) != nil else {
            return etat.dire("Le mot de passe de cet accès manque : vois Réglages › Vidéos personnelles.")
        }
        aLire = video
    }

    private func vignette(_ video: VideoPerso) -> Image? {
        guard VignettesSouvenirs.possible(video.chemin) else { return nil }
        etat.videosPerso.vignettes.demander(video, acces: etat.videosPerso.reglages.acces,
                                            motDePasse: etat.videosPerso.motDePasse(films: etat.nas))
        return etat.videosPerso.vignettes.vignettes[video.chemin]
    }
}
