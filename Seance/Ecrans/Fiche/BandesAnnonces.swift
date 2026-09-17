import SeanceKit
import SwiftUI
import WebKit

/// UX-09 : vignettes des bandes-annonces et teasers ; toucher lance la lecture en flux.
struct SectionBandesAnnonces: View {
    let videos: [Video]
    let choisir: (Video) -> Void

    var body: some View {
        if !videos.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                TitreSection("Bandes-annonces")
                DefilementHorizontal {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(videos.prefix(8)) { video in
                            Button { choisir(video) } label: { vignette(video) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private func vignette(_ video: Video) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ImageDistante(url: video.urlVignette)
                .frame(width: 240, height: 135)
                .overlay {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(.white, .black.opacity(0.45))
                }
            Text(video.nom)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text([video.type == "Teaser" ? "Teaser" : "Bande-annonce", video.langue == "fr" ? "français" : video.langue?.uppercased()]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 240, alignment: .leading)
    }
}

/// Feuille de lecture : le lecteur YouTube intégré, et YouTube en secours.
struct LecteurBandeAnnonce: View {
    let video: Video
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase
    @State private var lecture = ControleLecture()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                LecteurYouTube(video: video, lecture: lecture)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(video.nom).font(.headline)
                if let url = video.urlYouTube {
                    Button("Ouvrir dans YouTube", systemImage: "arrow.up.right.square") {
                        lecture.arreter()
                        openURL(url)
                    }
                    .font(.subheadline)
                }
                Spacer()
            }
            .padding(20)
            .background(Theme.fond)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer", systemImage: "xmark") {
                        lecture.arreter()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        // Fermée d'un geste, par Échap ou en quittant l'onglet : le son s'arrête avec la feuille.
        .onDisappear { lecture.arreter() }
        // L'app passe en arrière-plan ou la fenêtre du Mac est fermée : pas de son qui continue derrière.
        .onChange(of: phase) { _, nouvelle in
            if nouvelle != .active { lecture.pause() }
        }
    }
}

/// Tient la vue web du lecteur pour l'arrêter au moment voulu : SwiftUI ne la détruit pas toujours à la fermeture
/// de la feuille, et la vidéo continuait alors à jouer derrière, son compris.
@MainActor
final class ControleLecture {
    weak var vue: WKWebView?

    func pause() {
        vue?.pauseAllMediaPlayback()
    }

    /// Met la vidéo en pause, ferme un éventuel plein écran, puis vide la page pour libérer le flux.
    func arreter() {
        guard let vue else { return }
        vue.pauseAllMediaPlayback()
        vue.closeAllMediaPresentations()
        vue.setAllMediaPlaybackSuspended(true)
        vue.stopLoading()
        vue.loadHTMLString("", baseURL: nil)
        self.vue = nil
    }
}

/// Lecteur YouTube dans une vue web. La vidéo est lue en flux : le stockage web est éphémère,
/// rien n'est gardé sur l'iPhone une fois la feuille fermée.
private struct LecteurYouTube: UIViewRepresentable {
    let video: Video
    let lecture: ControleLecture

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        // Pas d'image dans l'image : elle gardait la vidéo et le son une fois la feuille fermée.
        configuration.allowsPictureInPictureMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .nonPersistent()
        let vue = WKWebView(frame: .zero, configuration: configuration)
        vue.isOpaque = false
        vue.backgroundColor = .black
        vue.scrollView.isScrollEnabled = false
        charger(vue)
        lecture.vue = vue
        return vue
    }

    func updateUIView(_ vue: WKWebView, context: Context) {}

    static func dismantleUIView(_ vue: WKWebView, coordinator: ()) {
        // Dernier filet si la feuille disparaît sans passer par `onDisappear`.
        vue.pauseAllMediaPlayback()
        vue.closeAllMediaPresentations()
        vue.loadHTMLString("", baseURL: nil)
    }

    /// YouTube refuse la lecture intégrée sans page d'origine (erreur 153) : la vidéo est placée
    /// dans une petite page dont l'adresse de base sert de référent.
    private func charger(_ vue: WKWebView) {
        guard let url = video.urlIntegration else { return }
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:#000}iframe{position:fixed;inset:0;width:100%;height:100%;border:0}</style>
        </head><body><iframe src="\(url.absoluteString)" allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
        allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe></body></html>
        """
        vue.loadHTMLString(html, baseURL: URL(string: "https://ch.patrick.seance"))
    }
}
