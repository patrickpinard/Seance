import SeanceKit
import SeanceNAS
import SwiftUI
import VLCKit

/// Le lecteur de l'Apple TV (6.6) : le moteur de VLC, dans Séance. Jusqu'ici la TV passait la main à Infuse ou à
/// VLC, qui lisaient bien — mais au retour on se retrouvait chez eux, pas sur la page d'où l'on venait. Ici, la
/// touche Retour referme le lecteur et rend la main à Séance, exactement là où on l'a quitté.
///
/// La vidéo reste sur le NAS : elle passe par le relais local, comme sur l'iPhone.
struct LecteurVLCTV: View {
    let video: VideoPerso
    let acces: ReglagesNAS
    let motDePasse: String
    /// Appelé si même VLC n'y arrive pas : l'écran d'appel propose alors Infuse.
    var surEchec: (String) -> Void = { _ in }

    @Environment(\.dismiss) private var fermer
    @State private var moteur = MoteurVLCTV()
    @State private var relais: RelaisVideo?
    @State private var source: SourceVideoSMB?
    @State private var message: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let message {
                VStack(spacing: 24) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 64)).foregroundStyle(Theme.accentClair)
                    Text(message)
                        .font(.system(size: 30))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 1100)
                    Text("Touche Retour pour revenir.").font(.system(size: 24)).foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
            } else {
                VueVLCTV(moteur: moteur).ignoresSafeArea()
                if moteur.enChargement {
                    VStack(spacing: 18) {
                        ProgressView().tint(.white).controlSize(.large)
                        Text(video.nom).font(.system(size: 26)).foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
        }
        // La barre de progression, en bas, quand la lecture est en pause ou vient de commencer.
        .overlay(alignment: .bottom) {
            if !moteur.enChargement, message == nil, !moteur.enLecture {
                VStack(spacing: 10) {
                    ProgressView(value: moteur.position).tint(Theme.accent).frame(maxWidth: 1400)
                    Text("\(moteur.tempsAffiche) — en pause").font(.system(size: 24)).foregroundStyle(.white.opacity(0.8))
                }
                .padding(40)
            }
        }
        // La télécommande : Retour ferme, le bouton du milieu met en pause ou reprend.
        .onExitCommand { fermer() }
        .onPlayPauseCommand { moteur.basculerLecture() }
        .task { await ouvrir() }
        .onDisappear { Task { await ranger() } }
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

/// La vue où VLC dessine, sur la TV.
private struct VueVLCTV: UIViewRepresentable {
    let moteur: MoteurVLCTV

    func makeUIView(context: Context) -> UIView {
        let vue = UIView()
        vue.backgroundColor = .black
        moteur.attacher(a: vue)
        return vue
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Le moteur, côté TV : lecture, pause, position. Tout sur le fil principal.
@MainActor
@Observable
final class MoteurVLCTV {
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
                try? await Task.sleep(for: .milliseconds(500))
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

    func arreter() {
        observateur?.cancel()
        observateur = nil
        lecteur.stop()
        enLecture = false
    }
}
