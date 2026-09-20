import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Séance sur Apple TV (EF-141) : la même logique que sur l'iPhone — SeanceKit, SeanceDonnees, SeanceNAS — sous une
/// interface faite pour la télécommande et pour être lue à trois mètres.
@main
struct SeanceTVApp: App {
    @State private var etat = EtatTV()

    var body: some Scene {
        WindowGroup {
            if let conteneur = ConteneurTV.conteneur {
                RacineTV()
                    .environment(etat)
                    .modelContainer(conteneur)
                    .preferredColorScheme(.dark)
                    .tint(Theme.accent)
            } else {
                ContentUnavailableView("Séance ne peut pas ouvrir ses données", systemImage: "externaldrive.badge.xmark",
                                       description: Text("Supprime l'app de l'Apple TV, puis réinstalle-la."))
            }
        }
    }
}

/// tvOS peut effacer les données d'une app quand la place manque (EF-145) : le magasin vit dans le cache, et tout ce
/// qui compte se reconstruit — la bibliothèque depuis le NAS, les listes depuis le dossier de synchronisation.
@MainActor
enum ConteneurTV {
    static let conteneur: ModelContainer? = {
        #if DEBUG
        if Demonstration.active {
            guard let conteneur = try? EntrepotSeance.conteneur(.memoire) else { return nil }
            if !Demonstration.vide { Demonstration.remplir(conteneur.mainContext) }
            return conteneur
        }
        #endif
        let dossier = URL.cachesDirectory.appending(path: "Seance")
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        return try? EntrepotSeance.conteneur(.dossier(dossier))
    }()
}
