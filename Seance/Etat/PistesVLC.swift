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

/// Les MKV (8.0) : le démultiplexeur MKV de VLCKit 4 lit à l'envers le rapport de pixels des vidéos anamorphiques —
/// « Unabomber », 1280 × 720 à pixels 90:67, s'affichait en 1,32:1 au lieu de 2,39:1, comme une vingtaine d'autres films
/// du NAS. Celui de FFmpeg le lit juste ; imposer un format d'image après coup n'y changeait rien.
enum OptionsVLC {
    static func pour(_ chemin: String) -> [String] {
        (chemin as NSString).pathExtension.lowercased() == "mkv" ? [":demux=avformat"] : []
    }
}
#endif
