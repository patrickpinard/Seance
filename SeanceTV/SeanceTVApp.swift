import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Séance sur Apple TV (EF-141) : la même logique que sur l'iPhone — SeanceKit, SeanceDonnees, SeanceNAS — sous une
/// interface faite pour la télécommande et pour être lue à trois mètres.
@main
struct SeanceTVApp: App {
    @State private var etat = EtatTV()
    @State private var conteneur = ConteneurTV.conteneur
    /// Change avec le profil de la famille : tous les écrans se reconstruisent sur son magasin.
    @State private var generation = 0

    init() {
        // Le jour et l'heure d'arrivée de cette version (8.1), pour Réglages › Versions.
        InstallationsVersions.noter()
    }

    var body: some Scene {
        WindowGroup {
            if let conteneur {
                RacineTV()
                    .id(generation)
                    .onReceive(NotificationCenter.default.publisher(for: ConteneurTV.profilChange)) { _ in
                        self.conteneur = ConteneurTV.conteneur
                        etat = EtatTV()
                        generation += 1
                    }
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
    /// La famille sur la TV : le registre vit dans les réglages de l'app (pas de groupe d'apps partagé avec l'iPhone) ; les
    /// personnes y arrivent par la synchronisation.
    static let famille = ProfilsFamille(defauts: .standard)
    static let profilChange = Notification.Name("seance.tv.profilChange")

    #if DEBUG
    private static var demonstrations: [String: ModelContainer] = [:]
    #endif

    private(set) static var conteneur: ModelContainer? = ouvrir()

    /// « Qui regarde ? » : le magasin de cette personne s'ouvre, à côté du cache commun (NAS, guide TV).
    static func changerDeProfil(vers profil: ProfilFamille) {
        guard profil.id != famille.actif.id else { return }
        famille.activer(profil)
        conteneur = ouvrir()
        NotificationCenter.default.post(name: profilChange, object: nil)
    }

    private static func ouvrir() -> ModelContainer? {
        #if DEBUG
        if Demonstration.active {
            // Au lancement, la famille de la démonstration : vide, ou celle de `SEANCE_TV_FAMILLE=Anne,Léo` (tests, captures).
            if demonstrations.isEmpty {
                for profil in famille.profils where !profil.estPrincipal { famille.supprimer(profil) }
                famille.activer(famille.profils[0])
                for prenom in (ProcessInfo.processInfo.environment["SEANCE_TV_FAMILLE"] ?? "").split(separator: ",") {
                    famille.ajouter(prenom: String(prenom), symbole: "star.fill")
                }
            }
            if let connu = demonstrations[famille.actif.id] { return connu }
            guard let conteneur = try? EntrepotSeance.conteneur(.memoire) else { return nil }
            if !Demonstration.vide, famille.actif.estPrincipal { Demonstration.remplir(conteneur.mainContext) }
            demonstrations[famille.actif.id] = conteneur
            return conteneur
        }
        #endif
        let dossier = URL.cachesDirectory.appending(path: "Seance")
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let profil = famille.actif
        if let ouvert = ouverts[profil.id] { return ouvert }
        let conteneur = try? EntrepotSeance.conteneur(profil.estPrincipal ? .dossier(dossier) : .dossierProfil(dossier, profil.id))
        ouverts[profil.id] = conteneur
        return conteneur
    }

    /// Comme sur l'iPhone (8.2.18) : le magasin de chaque personne reste ouvert jusqu'à la fin du lancement — les pages
    /// de celle qu'on quitte, défaites un peu plus tard, ne retrouvent pas leur magasin relâché.
    private static var ouverts: [String: ModelContainer] = [:]
}
