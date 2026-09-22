import AVKit
import SeanceKit
import SeanceNAS
import SwiftUI

/// Le lecteur de Séance, pour les vidéos personnelles : la vidéo reste sur le NAS, et le lecteur d'iOS la lit par
/// morceaux à travers un relais local (`RelaisVideo`). Rien n'est copié sur l'appareil, et il n'y a plus d'app
/// extérieure à convaincre d'ouvrir un chemin SMB — ce qui ne démarrait pas toujours sur l'iPhone.
///
/// Les formats sont ceux qu'AVFoundation sait lire : MP4, MOV, M4V — donc ce que filme un iPhone. Un MKV ou un AVI
/// ne s'ouvrira pas. Un MP4 au codec qu'iOS ne décode pas non plus (6.2) : le lecteur surveille que la vidéo démarre
/// vraiment, et sinon passe la main (`surEchec`) — l'écran d'appel l'ouvre alors dans Infuse ou VLC.
struct LecteurIntegre: View {
    let video: VideoPerso
    let acces: ReglagesNAS
    let motDePasse: String
    /// Appelé quand la vidéo ne peut pas être lue ici : l'écran d'appel propose alors VLC.
    var surEchec: (String) -> Void = { _ in }

    @Environment(\.dismiss) private var fermer
    @State private var lecteur: AVPlayer?
    @State private var relais: RelaisVideo?
    @State private var source: SourceVideoSMB?
    @State private var message: String?

    /// Les formats qu'AVFoundation ouvre sans extension ni conversion. Un MKV, un AVI ou un WMV n'en font pas
    /// partie : ils passent par VLC, qui les lit tous.
    static let formatsLus: Set<String> = ["mp4", "m4v", "mov", "qt"]

    /// Vrai si Séance sait lire ce fichier elle-même.
    static func lisible(_ chemin: String) -> Bool {
        formatsLus.contains((chemin as NSString).pathExtension.lowercased())
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let lecteur {
                VideoPlayer(player: lecteur)
                    .ignoresSafeArea()
            } else if let message {
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
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .topLeading) {
            Button { fermer() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .padding(20)
            .accessibilityLabel("Fermer le lecteur")
        }
        .task { await ouvrir() }
        .onDisappear { Task { await ranger() } }
    }

    private func ouvrir() async {
        guard lecteur == nil, message == nil else { return }
        let extensionFichier = (video.chemin as NSString).pathExtension.lowercased()
        guard Self.lisible(video.chemin) else {
            let texte = "Séance ne sait pas lire les fichiers « \(extensionFichier) ». Ouvre-la dans VLC."
            message = texte
            surEchec(texte)
            return
        }
        let nouvelle = SourceVideoSMB(reglages: acces, motDePasse: motDePasse, chemin: video.chemin)
        await nouvelle.ouvrir()
        source = nouvelle
        let nouveau = RelaisVideo(source: nouvelle, typeMIME: extensionFichier == "mp4" ? "video/mp4" : "video/quicktime")
        do {
            let adresse = try await nouveau.demarrer()
            relais = nouveau
            let element = AVPlayerItem(url: adresse)
            let joueur = AVPlayer(playerItem: element)
            joueur.play()
            lecteur = joueur
            await surveiller(element)
        } catch {
            let texte = ErreurNAS.message(error)
            message = texte
            surEchec(texte)
            await nouvelle.fermer()
        }
    }

    /// La vidéo démarre-t-elle vraiment ? Un fichier au codec inconnu d'iOS reste sur un écran noir sans rien dire :
    /// au bout de douze secondes sans image lisible, ou dès qu'AVFoundation renonce, on passe la main.
    private func surveiller(_ element: AVPlayerItem) async {
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled || lecteur == nil { return }
            switch element.status {
            case .failed:
                return echouer("Le lecteur d'iOS ne sait pas lire cette vidéo.")
            case .readyToPlay:
                let lisible = (try? await element.asset.load(.isPlayable)) ?? false
                let images = (try? await element.asset.loadTracks(withMediaType: .video)) ?? []
                if !lisible || images.isEmpty { return echouer("Le lecteur d'iOS ne sait pas décoder cette vidéo.") }
                return
            default:
                continue
            }
        }
        echouer("Cette vidéo ne démarre pas dans Séance.")
    }

    private func echouer(_ texte: String) {
        lecteur?.pause()
        lecteur = nil
        message = texte
        surEchec(texte)
    }

    private func ranger() async {
        lecteur?.pause()
        lecteur = nil
        await relais?.arreter()
        relais = nil
        await source?.fermer()
        source = nil
    }
}
