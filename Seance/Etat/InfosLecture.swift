import MediaPlayer
import UIKit

/// Ce qui passe, pour le système (8.9, bilan de l'Apple TV) : le titre, l'affiche, la durée et la position dans le
/// Centre de contrôle, sur l'écran verrouillé de l'iPhone et dans la télécommande de l'iPhone pour l'Apple TV ; lecture,
/// pause et sauts de 10 secondes y répondent. Commun aux lecteurs de VLC de l'iPhone, de l'iPad et de la TV.
@MainActor
enum InfosLecture {
    struct Commandes {
        let jouerPause: @MainActor @Sendable () -> Void
        let avancer: @MainActor @Sendable () -> Void
        let reculer: @MainActor @Sendable () -> Void
        /// Aller à une position, en secondes.
        let aller: @MainActor @Sendable (Double) -> Void
    }

    private static var infos: [String: Any] = [:]
    private static var cibles: [(MPRemoteCommand, Any)] = []

    static func ouvrir(titre: String, sousTitre: String?, cheminAffiche: String?, commandes: Commandes) {
        fermer()
        infos = [MPMediaItemPropertyTitle: titre, MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue]
        if let sousTitre { infos[MPMediaItemPropertyArtist] = sousTitre }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = infos

        let centre = MPRemoteCommandCenter.shared()
        func brancher(_ commande: MPRemoteCommand, _ action: @escaping @MainActor @Sendable () -> Void) {
            commande.isEnabled = true
            cibles.append((commande, Self.cible(commande, action)))
        }
        brancher(centre.togglePlayPauseCommand, commandes.jouerPause)
        brancher(centre.playCommand, commandes.jouerPause)
        brancher(centre.pauseCommand, commandes.jouerPause)
        centre.skipForwardCommand.preferredIntervals = [10]
        centre.skipBackwardCommand.preferredIntervals = [10]
        brancher(centre.skipForwardCommand, commandes.avancer)
        brancher(centre.skipBackwardCommand, commandes.reculer)
        centre.changePlaybackPositionCommand.isEnabled = true
        cibles.append((centre.changePlaybackPositionCommand, Self.cibleDePosition(centre.changePlaybackPositionCommand, commandes.aller)))

        #if DEBUG
        // SEANCE_LIRE_AFFICHE=<image du Mac> : une affiche locale, pour que les tests du lecteur fassent demander l'image
        // par le système, comme sur l'appareil (plantage de la 8.10).
        if let chemin = ProcessInfo.processInfo.environment["SEANCE_LIRE_AFFICHE"], let image = UIImage(contentsOfFile: chemin) {
            infos[MPMediaItemPropertyArtwork] = Self.oeuvre(image)
            MPNowPlayingInfoCenter.default().nowPlayingInfo = infos
            return
        }
        #endif
        // L'affiche arrive après : le titre s'affiche tout de suite.
        guard let url = ImageTMDB.url(cheminAffiche, .affiche) else { return }
        Task {
            guard let (donnees, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: donnees),
                  !infos.isEmpty else { return }
            infos[MPMediaItemPropertyArtwork] = Self.oeuvre(image)
            MPNowPlayingInfoCenter.default().nowPlayingInfo = infos
        }
    }

    // 8.10.1 (plantages de l'Apple TV du 02.10.2026) : MediaPlayer appelle ces blocs depuis sa propre file. Écrits dans
    // une fonction réservée au fil principal, Swift les y réservait aussi, et arrêtait l'app (`dispatch_assert_queue`).
    // Ils sont donc fabriqués hors de toute isolation, et ramènent eux-mêmes l'action sur le fil principal.

    /// L'affiche, que le système demande depuis sa file : le bloc ne touche à rien d'autre que l'image.
    nonisolated private static func oeuvre(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    nonisolated private static func cible(_ commande: MPRemoteCommand, _ action: @escaping @MainActor @Sendable () -> Void) -> Any {
        commande.addTarget { _ in
            Task { @MainActor in action() }
            return .success
        }
    }

    nonisolated private static func cibleDePosition(_ commande: MPRemoteCommand, _ aller: @escaping @MainActor @Sendable (Double) -> Void) -> Any {
        commande.addTarget { evenement in
            guard let evenement = evenement as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let secondes = evenement.positionTime
            Task { @MainActor in aller(secondes) }
            return .success
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
