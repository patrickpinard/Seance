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
    /// Image sans son : le fichier a bien une piste audio, mais iOS ne sait pas la décoder (6.3) ; son codec, s'il se nomme.
    @State private var sansSon = false
    @State private var sonIllisible: String?

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
        .overlay(alignment: .bottom) {
            if sansSon {
                VStack(spacing: 10) {
                    Text("Cette vidéo a un son \(sonIllisible ?? "que l'iPhone ne sait pas décoder") : l'image passe, le son non.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    Button("L'ouvrir avec le son") { surEchec("Le son de cette vidéo ne se décode pas ici.") }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                }
                .padding(16)
                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.bottom, 90)
            }
        }
        // Les deux coins du haut appartiennent au lecteur d'Apple : AirPlay à gauche, le volume à droite. La croix
        // de Séance s'y posait dessus, et un toucher partait au hasard sur l'un ou sur l'autre (6.5). Elle descend
        // donc sous cette rangée, dans la bande laissée libre — et un glissement vers le bas ferme aussi, comme
        // partout sur iOS.
        .overlay(alignment: .topLeading) {
            Button { fermer() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .padding(.leading, 20)
            .padding(.top, 76)
            .accessibilityLabel("Fermer le lecteur")
        }
        .gesture(
            DragGesture(minimumDistance: 60)
                .onEnded { glissement in
                    if glissement.translation.height > 80 { fermer() }
                }
        )
        // L'iPhone tourne à l'horizontale le temps de la vidéo (7.0).
        .onAppear { OrientationLecture.ouvrir() }
        .task { await ouvrir() }
        .onDisappear {
            OrientationLecture.fermer()
            Task { await ranger() }
        }
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
            preparerLeSon()
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

    /// Le son (6.3). Sans catégorie déclarée, une app est en « soloAmbient » : le commutateur latéral de l'iPhone
    /// coupe alors le son de la vidéo — l'image tournait sans un bruit —, et le son s'arrête dès que l'écran se
    /// verrouille. « Playback » est la catégorie d'un lecteur : il sonne même en silencieux, et met en pause la
    /// musique qui jouait. Le Mac n'a pas de commutateur, et sa session audio n'a rien à régler.
    private func preparerLeSon() {
        #if !targetEnvironment(macCatalyst)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
        #endif
    }

    private func rendreLeSon() {
        #if !targetEnvironment(macCatalyst)
        // La musique interrompue peut reprendre.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
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
                // Un « .mp4 » n'est qu'une boîte : ce qui compte est le codec dedans. Du Xvid ou du DivX y passe
                // encore souvent, et iOS ne le décode pas — l'écran restait noir sans un mot (6.3). On le nomme.
                var decodable = false
                for piste in images where ((try? await piste.load(.isDecodable)) ?? false) { decodable = true }
                if !decodable {
                    let codec = await Self.codec(images[0]) ?? "dans un format"
                    return echouer("Cette vidéo est \(codec), qu'iOS ne sait pas décoder.")
                }
                // L'image passe, le son pas toujours : un MP4 à piste AC-3 ou DTS se lit en silence (6.3). Plutôt que
                // de tout arrêter, on le dit et on propose d'ouvrir la vidéo là où elle s'entend.
                let sons = (try? await element.asset.loadTracks(withMediaType: .audio)) ?? []
                var entendu = sons.isEmpty
                for piste in sons where ((try? await piste.load(.isDecodable)) ?? false) { entendu = true }
                if !entendu, let son = sons.first { sonIllisible = await Self.codec(son) }
                sansSon = !entendu
                return
            default:
                continue
            }
        }
        echouer("Cette vidéo ne démarre pas dans Séance.")
    }

    /// Le nom lisible du codec d'une piste, tiré de son identifiant à quatre lettres — « mp4v » pour du MPEG-4
    /// Part 2 (Xvid, DivX), « avc1 » pour du H.264. Sert à dire pourquoi une vidéo ne passe pas.
    static func codec(_ piste: AVAssetTrack) async -> String? {
        guard let format = (try? await piste.load(.formatDescriptions))?.first else { return nil }
        let type = CMFormatDescriptionGetMediaSubType(format)
        let lettres = String(UnicodeScalar((type >> 24) & 255)!) + String(UnicodeScalar((type >> 16) & 255)!)
            + String(UnicodeScalar((type >> 8) & 255)!) + String(UnicodeScalar(type & 255)!)
        let noms = ["mp4v": "du MPEG-4 Part 2 (Xvid ou DivX)", "avc1": "du H.264", "hvc1": "du HEVC", "hev1": "du HEVC",
                    "vp09": "du VP9", "av01": "de l'AV1", "mjpa": "du Motion JPEG", "mjpb": "du Motion JPEG",
                    "ac-3": "de l'AC-3", "ec-3": "de l'E-AC-3", "dtsc": "du DTS", "mp4a": "de l'AAC"]
        return noms[lettres] ?? "au format « \(lettres.trimmingCharacters(in: .whitespaces)) »"
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
        rendreLeSon()
        await relais?.arreter()
        relais = nil
        await source?.fermer()
        source = nil
    }
}
