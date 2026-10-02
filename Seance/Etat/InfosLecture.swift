import MediaPlayer
import UIKit

/// Ce qui passe, pour le système (8.9, bilan de l'Apple TV) : le titre, l'affiche, la durée et la position dans le
/// Centre de contrôle, sur l'écran verrouillé de l'iPhone et dans la télécommande de l'iPhone pour l'Apple TV ; lecture,
/// pause et sauts de 10 secondes y répondent. Commun aux lecteurs de VLC de l'iPhone, de l'iPad et de la TV.
@MainActor
enum InfosLecture {
    struct Commandes {
        let jouerPause: () -> Void
        let avancer: () -> Void
        let reculer: () -> Void
        /// Aller à une position, en secondes.
        let aller: (Double) -> Void
    }

    private static var infos: [String: Any] = [:]
    private static var cibles: [(MPRemoteCommand, Any)] = []

    static func ouvrir(titre: String, sousTitre: String?, cheminAffiche: String?, commandes: Commandes) {
        fermer()
        infos = [MPMediaItemPropertyTitle: titre, MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue]
        if let sousTitre { infos[MPMediaItemPropertyArtist] = sousTitre }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = infos

        let centre = MPRemoteCommandCenter.shared()
        func brancher(_ commande: MPRemoteCommand, _ action: @escaping () -> Void) {
            commande.isEnabled = true
            let cible = commande.addTarget { _ in
                MainActor.assumeIsolated { action() }
                return .success
            }
            cibles.append((commande, cible))
        }
        brancher(centre.togglePlayPauseCommand, commandes.jouerPause)
        brancher(centre.playCommand, commandes.jouerPause)
        brancher(centre.pauseCommand, commandes.jouerPause)
        centre.skipForwardCommand.preferredIntervals = [10]
        centre.skipBackwardCommand.preferredIntervals = [10]
        brancher(centre.skipForwardCommand, commandes.avancer)
        brancher(centre.skipBackwardCommand, commandes.reculer)
        centre.changePlaybackPositionCommand.isEnabled = true
        let cible = centre.changePlaybackPositionCommand.addTarget { evenement in
            guard let evenement = evenement as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let secondes = evenement.positionTime
            MainActor.assumeIsolated { commandes.aller(secondes) }
            return .success
        }
        cibles.append((centre.changePlaybackPositionCommand, cible))

        // L'affiche arrive après : le titre s'affiche tout de suite.
        guard let url = ImageTMDB.url(cheminAffiche, .affiche) else { return }
        Task {
            guard let (donnees, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: donnees),
                  !infos.isEmpty else { return }
            infos[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = infos
        }
    }

    /// La position, la durée et l'état, toutes les secondes : le système en déduit la barre de progression.
    static func mettreAJour(secondes: Double, duree: Double, enLecture: Bool) {
        guard !infos.isEmpty else { return }
        infos[MPNowPlayingInfoPropertyElapsedPlaybackTime] = secondes
        if duree > 0 { infos[MPMediaItemPropertyPlaybackDuration] = duree }
        infos[MPNowPlayingInfoPropertyPlaybackRate] = enLecture ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = infos
        MPNowPlayingInfoCenter.default().playbackState = enLecture ? .playing : .paused
    }

    static func fermer() {
        for (commande, cible) in cibles { commande.removeTarget(cible) }
        cibles = []
        infos = [:]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}
