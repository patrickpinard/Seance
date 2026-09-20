import AVKit
import SeanceKit
import SeanceNAS
import SwiftUI

/// Le lecteur de Séance, pour les vidéos personnelles : la vidéo reste sur le NAS, et le lecteur d'iOS la lit par
/// morceaux à travers un relais local (`RelaisVideo`). Rien n'est copié sur l'appareil, et il n'y a plus d'app
/// extérieure à convaincre d'ouvrir un chemin SMB — ce qui ne démarrait pas toujours sur l'iPhone.
///
/// Les formats sont ceux qu'AVFoundation sait lire : MP4, MOV, M4V — donc ce que filme un iPhone. Un MKV ou un AVI
/// ne s'ouvrira pas ; l'écran le dit et propose de passer à VLC.
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

    /// Les formats qu'AVFoundation ouvre sans extension ni conversion.
    private static let formatsLus: Set<String> = ["mp4", "m4v", "mov", "qt"]

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
        guard Self.formatsLus.contains(extensionFichier) else {
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
            let joueur = AVPlayer(url: adresse)
            joueur.play()
            lecteur = joueur
        } catch {
            let texte = ErreurNAS.message(error)
            message = texte
            surEchec(texte)
            await nouvelle.fermer()
        }
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
