#if !targetEnvironment(macCatalyst)
import SeanceKit
import SeanceNAS
import SwiftUI
import VLCKit

/// Le lecteur de secours de Séance (6.5) : le moteur de VLC, qui lit ce qu'AVFoundation refuse — AVI, WMV, MKV,
/// DV de caméscope, MJPEG. Il lit le fichier par le relais local, comme le lecteur d'Apple : la vidéo reste sur le
/// NAS, rien n'est copié sur l'appareil.
///
/// Sur le Mac, Séance garde AVFoundation : le binaire de VLCKit n'a pas de tranche Mac Catalyst. Infuse y prend le
/// relais, et il y fonctionne.
struct LecteurVLC: View {
    let video: VideoPerso
    let acces: ReglagesNAS
    let motDePasse: String
    /// Appelé quand même VLC n'y arrive pas : l'écran d'appel propose alors les apps extérieures.
    var surEchec: (String) -> Void = { _ in }

    @Environment(\.dismiss) private var fermer
    @State private var moteur = MoteurVLC()
    @State private var relais: RelaisVideo?
    @State private var source: SourceVideoSMB?
    @State private var message: String?
    @State private var commandesVisibles = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let message {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(Theme.accentClair)
                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 40)
                    Button("Fermer") { fermer() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                }
            } else {
                VueVLC(moteur: moteur).ignoresSafeArea()
                if moteur.enChargement {
                    ProgressView().tint(.white).controlSize(.large)
                }
            }
        }
        .overlay(alignment: .bottom) { if commandesVisibles, message == nil { commandes } }
        .overlay(alignment: .topLeading) {
            Button { fermer() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .padding(.leading, 20)
            .padding(.top, 24)
            .accessibilityLabel("Fermer le lecteur")
        }
        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { commandesVisibles.toggle() } }
        .gesture(
            DragGesture(minimumDistance: 60).onEnded { glissement in
                if glissement.translation.height > 80 { fermer() }
            }
        )
        .statusBarHidden()
        .task { await ouvrir() }
        .onDisappear { Task { await ranger() } }
    }

    /// Les commandes : lecture, position, durée. Le lecteur de VLC n'en fournit aucune — celles-ci sont à nous,
    /// donc aux couleurs de Séance.
    private var commandes: some View {
        VStack(spacing: 10) {
            Slider(value: Binding(get: { moteur.position }, set: { moteur.allerA($0) }), in: 0...1)
                .tint(Theme.accent)
            HStack(spacing: 24) {
                Button { moteur.reculer() } label: { Image(systemName: "gobackward.10") }
                Button { moteur.basculerLecture() } label: {
                    Image(systemName: moteur.enLecture ? "pause.fill" : "play.fill").font(.title)
                }
                Button { moteur.avancer() } label: { Image(systemName: "goforward.10") }
                Spacer()
                Text(moteur.tempsAffiche).font(.caption.monospacedDigit())
            }
            .font(.title3)
            .foregroundStyle(.white)
        }
        .padding(18)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
    }

    private func ouvrir() async {
        guard relais == nil, message == nil else { return }
        let nouvelle = SourceVideoSMB(reglages: acces, motDePasse: motDePasse, chemin: video.chemin)
        await nouvelle.ouvrir()
        source = nouvelle
        let extensionFichier = (video.chemin as NSString).pathExtension.lowercased()
        let nouveau = RelaisVideo(source: nouvelle, typeMIME: Self.typeMIME(extensionFichier))
        do {
            let adresse = try await nouveau.demarrer()
            relais = nouveau
            moteur.lire(adresse)
        } catch {
            let texte = ErreurNAS.message(error)
            message = texte
            surEchec(texte)
            await nouvelle.fermer()
        }
    }

    /// VLC se fie surtout au contenu, mais un type juste lui évite de deviner.
    static func typeMIME(_ extensionFichier: String) -> String {
        switch extensionFichier {
        case "mp4", "m4v": "video/mp4"
        case "mov", "qt": "video/quicktime"
        case "mkv": "video/x-matroska"
        case "avi": "video/x-msvideo"
        case "wmv": "video/x-ms-wmv"
        case "mpg", "mpeg": "video/mpeg"
        default: "application/octet-stream"
        }
    }

    private func ranger() async {
        moteur.arreter()
        await relais?.arreter()
        relais = nil
        await source?.fermer()
        source = nil
    }
}

/// La vue où VLC dessine. `VLCVideoView` est une vue UIKit : SwiftUI la reçoit telle quelle.
private struct VueVLC: UIViewRepresentable {
    let moteur: MoteurVLC

    func makeUIView(context: Context) -> UIView {
        let vue = UIView()
        vue.backgroundColor = .black
        moteur.attacher(a: vue)
        return vue
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Ce que Séance demande au moteur de VLC, et ce qu'elle en lit. Tout passe par le fil principal : `VLCMediaPlayer`
/// n'est pas fait pour être piloté d'ailleurs.
@MainActor
@Observable
final class MoteurVLC {
    private let lecteur = VLCMediaPlayer()
    private var observateur: Task<Void, Never>?

    private(set) var enLecture = false
    private(set) var enChargement = true
    private(set) var position: Double = 0
    private(set) var tempsAffiche = "0:00"

    func attacher(a vue: UIView) {
        lecteur.drawable = vue
    }

    func lire(_ adresse: URL) {
        lecteur.media = VLCMedia(url: adresse)
        lecteur.play()
        enLecture = true
        observateur = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard let self else { return }
                self.position = self.lecteur.position
                self.enLecture = self.lecteur.isPlaying
                self.enChargement = !self.lecteur.isPlaying && self.lecteur.position == 0
                self.tempsAffiche = self.lecteur.time.stringValue
            }
        }
    }

    func basculerLecture() {
        if lecteur.isPlaying { lecteur.pause() } else { lecteur.play() }
        enLecture = lecteur.isPlaying
    }

    func allerA(_ position: Double) {
        lecteur.position = position
        self.position = position
    }

    func avancer() { lecteur.jumpForward(10) }
    func reculer() { lecteur.jumpBackward(10) }

    func arreter() {
        observateur?.cancel()
        observateur = nil
        lecteur.stop()
        enLecture = false
    }
}
#endif
