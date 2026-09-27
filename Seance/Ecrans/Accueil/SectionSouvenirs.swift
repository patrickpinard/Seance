import SeanceDonnees
import SeanceKit
import SwiftUI

/// « Tes souvenirs » sur l'accueil (8.2), comme sur l'Apple TV : les dernières vidéos personnelles. Un toucher lance la
/// vidéo tout de suite ; « Tout voir » ouvre la page des vidéos personnelles pour choisir. Rien quand elles ne sont pas
/// réglées.
struct SectionSouvenirs: View {
    @Environment(EtatApp.self) private var etat

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
        let motDePasse = etat.videosPerso.motDePasse(films: etat.nas.reglages)
        for album in etat.videosPerso.albums {
            for video in album.videos where VignettesSouvenirs.possible(video.chemin) {
                etat.videosPerso.vignettes.demander(video, acces: etat.videosPerso.reglages.acces, motDePasse: motDePasse)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let dernieres = dernieres
            if etat.videosPerso.actif, !dernieres.isEmpty {
                TitreSection(titre: "Tes souvenirs") {
                    NavigationLink(value: DossierVideosPerso()) { Text("Tout voir") }
                        .accessibilityHint("Ouvre toutes tes vidéos personnelles")
                }
                DefilementHorizontal {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(dernieres, id: \.video.chemin) { element in
                            let choisie = etat.videosPerso.couvertures.couverture(element.video.chemin)
                            let carte = CarteLargeTitre(reference: nil, titre: choisie?.titre ?? VideosPersoView.nomLisible(element.video.nom),
                                                        accroche: (choisie?.date ?? element.video.modifieLe).map(VideosPersoView.date),
                                                        faits: element.album.estVideoSeule ? [] : [element.album.titre], lecture: false,
                                                        icone: ArbreVideosPerso.symbole(de: element.video, dans: element.album, couvertures: etat.videosPerso.couvertures),
                                                        vignette: vignette(element.video), etiquette: "VIDÉO", lectureEnCoin: true)
                                .frame(width: CarteLargeTitre.largeur)
                            #if targetEnvironment(macCatalyst)
                            // Le Mac garde le lecteur d'Apple, posé par la page des vidéos : on y ouvre l'album.
                            NavigationLink(value: DossierVideosPerso(chemin: element.album.estVideoSeule ? "" : element.album.id)) { carte }
                                .buttonStyle(.plain)
                            #else
                            Button { lire(element.video) } label: { carte }
                                .buttonStyle(.plain)
                                .accessibilityHint("Lance la vidéo")
                            #endif
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .task {
            guard etat.videosPerso.actif else { return }
            await etat.videosPerso.lire(films: etat.nas.reglages)
            demanderLesImages()
        }
    }

    #if !targetEnvironment(macCatalyst)
    /// Le lecteur de Séance, comme depuis la page des vidéos : par-dessus l'app, avec la reprise.
    private func lire(_ video: VideoPerso) {
        guard let motDePasse = etat.videosPerso.motDePasse(films: etat.nas.reglages) else {
            return etat.confirmer("Le mot de passe de cet accès manque : vois Réglages › Vidéos personnelles.", symbole: "lock")
        }
        etat.lectureEnImage = false
        etat.lecture = LectureEnCours(video: video, acces: etat.videosPerso.reglages.acces, motDePasse: motDePasse) { _ in
            etat.confirmer("Cette vidéo ne se lit pas ici : essaie depuis « Tout voir ».", symbole: "exclamationmark.triangle")
        }
    }
    #endif

    private func vignette(_ video: VideoPerso) -> Image? {
        guard VignettesSouvenirs.possible(video.chemin) else { return nil }
        etat.videosPerso.vignettes.demander(video, acces: etat.videosPerso.reglages.acces,
                                            motDePasse: etat.videosPerso.motDePasse(films: etat.nas.reglages))
        return etat.videosPerso.vignettes.vignettes[video.chemin]
    }
}
