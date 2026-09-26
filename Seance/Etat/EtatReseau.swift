import Network
import Observation

/// Le réseau de l'appareil (8.1) : sur le seul réseau mobile, l'iPhone n'est pas à la maison, et le NAS n'y répond
/// qu'à son adresse « hors de la maison » (VPN, Tailscale), s'il en a une. Séance ne lit pas le nom du Wi-Fi (il
/// faudrait une autorisation de localisation) : un autre Wi-Fi que celui de la maison passe pour la maison.
@MainActor
@Observable
final class EtatReseau {
    private(set) var horsMaison = false
    private let surveillance = NWPathMonitor()

    init() {
        surveillance.pathUpdateHandler = { [weak self] chemin in
            let mobileSeulement = chemin.status == .satisfied && chemin.usesInterfaceType(.cellular)
                && !chemin.usesInterfaceType(.wifi) && !chemin.usesInterfaceType(.wiredEthernet)
            Task { @MainActor in self?.horsMaison = mobileSeulement }
        }
        surveillance.start(queue: .global(qos: .utility))
    }

    deinit {
        surveillance.cancel()
    }
}
