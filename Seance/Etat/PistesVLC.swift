#if !targetEnvironment(macCatalyst)
import SeanceKit
import VLCKit

/// La langue et les sous-titres retenus (8.1), posés sur le lecteur de VLC dès qu'il annonce les pistes du fichier.
/// Commun à l'iPhone, à l'iPad et à l'Apple TV (compilé dans les deux cibles par `project.yml`).
extension VLCMediaPlayer {
    /// Faux tant que VLC n'a pas encore décrit les pistes : il faudra réessayer.
    @discardableResult
    func appliquer(_ preferences: PreferencesPistes) -> Bool {
        let audio = audioTracks
        guard !audio.isEmpty else { return false }
        let decrire: (VLCMediaPlayer.Track) -> PreferencesPistes.Piste = {
            PreferencesPistes.Piste(id: $0.trackId, nom: $0.trackName, langue: $0.language)
        }
        let texte = textTracks
        let choix = preferences.choisir(audio: audio.map(decrire), sousTitres: texte.map(decrire),
                                        audioActuelle: audio.first(where: \.isSelected)?.trackId)
        if let id = choix.audio { audio.first { $0.trackId == id }?.isSelectedExclusively = true }
        switch choix.sousTitres {
        case .garder: break
        case .aucun: deselectAllTextTracks()
        case .piste(let id): texte.first { $0.trackId == id }?.isSelectedExclusively = true
        }
        return true
    }
}

/// Où un lecteur de VLC arrêté attend avant d'être libéré (8.2.7). Libéré aussitôt, il l'était parfois depuis le fil de
/// VLC, qui s'en servait encore : VLC s'arrêtait net (`vlc_player_Lock`), et Séance avec lui — rapports de l'Apple TV
/// du 26.09.2026. Gardé cinq secondes, il est relâché sur le fil principal, une fois VLC au repos.
@MainActor
enum CimetiereVLC {
    private static var enAttente: [VLCMediaPlayer] = []

    static func garder(_ lecteur: VLCMediaPlayer) {
        lecteur.delegate = nil
        lecteur.drawable = nil
        enAttente.append(lecteur)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if let rang = enAttente.firstIndex(where: { $0 === lecteur }) { enAttente.remove(at: rang) }
        }
    }
}

/// Les MKV (8.0) : le démultiplexeur MKV de VLCKit 4 lit à l'envers le rapport de pixels des vidéos anamorphiques —
/// « Unabomber », 1280 × 720 à pixels 90:67, s'affichait en 1,32:1 au lieu de 2,39:1, comme une vingtaine d'autres films
/// du NAS. Celui de FFmpeg le lit juste ; imposer un format d'image après coup n'y changeait rien.
///
/// 8.3 : mais celui de FFmpeg perd les sous-titres — ils s'appellent « Track 0 » et aucun ne se choisit (Mayday, essai
/// de VLCKit sur le Mac, 27.09.2026). Un MKV s'ouvre donc avec le démultiplexeur de VLC, qui les garde ; s'il annonce
/// des pixels non carrés, le lecteur repart aussitôt, à la même seconde, avec celui de FFmpeg (`anamorphique`).
enum OptionsVLC {
    static let ffmpeg = ":demux=avformat"

    /// Plus rien d'office (8.3) : voir `anamorphique`.
    static func pour(_ chemin: String) -> [String] { [] }

    static func estMKV(_ chemin: String) -> Bool {
        (chemin as NSString).pathExtension.lowercased() == "mkv"
    }

    /// Vrai quand la vidéo a des pixels non carrés (écart de plus de 3 %), faux sinon ; `nil` tant que VLC ne l'a pas
    /// encore décrite. Mayday, à 100:99, reste avec VLC et ses sous-titres ; Unabomber, à 67:90, passe à FFmpeg.
    static func anamorphique(_ lecteur: VLCMediaPlayer) -> Bool? {
        guard let video = lecteur.videoTracks.first?.video, video.sourceAspectRatio > 0, video.sourceAspectRatioDenominator > 0
        else { return nil }
        return abs(Double(video.sourceAspectRatio) / Double(video.sourceAspectRatioDenominator) - 1) > 0.03
    }
}
#endif
