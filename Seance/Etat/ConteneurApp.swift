import Foundation
import SeanceDonnees
import SwiftData

/// Le magasin SwiftData de l'app, ouvert une seule fois : l'interface, Siri et les raccourcis le partagent.
@MainActor
enum ConteneurApp {
    /// Le magasin du profil actif (Famille, 6.0). Il change avec le profil : voir `changerDeProfil`.
    private(set) static var resultat: Result<ModelContainer, any Error> = ouvrir()

    #if DEBUG
    private static var demonstrations: [String: ModelContainer] = [:]
    #endif

    private static func ouvrir() -> Result<ModelContainer, any Error> { Result {
        #if DEBUG
        if Demonstration.active {
            // La démonstration repart de réglages vierges : un test ne laisse rien au suivant (prénom, apparence,
            // dossier de synchronisation…). Première chose faite au lancement, avant que quiconque ne lise un réglage.
            // Dans le simulateur seulement : sur le Mac ou un vrai appareil, ces réglages sont ceux de la vraie app
            // (même identifiant), et une démonstration lancée pour une capture les effacerait.
            // Au lancement seulement : un changement de profil rouvre le magasin sans toucher aux réglages.
            let profil = ProfilsFamille().actif
            if demonstrations.isEmpty {
                #if targetEnvironment(simulator)
                if let identifiant = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: identifiant) }
                // La famille vit dans les réglages du groupe d'apps : elle repart aussi de zéro.
                UserDefaults(suiteName: EntrepotSeance.groupeApp)?.removePersistentDomain(forName: EntrepotSeance.groupeApp)
                #endif
            }
            // Un magasin en mémoire par profil, gardé le temps du lancement : on retrouve ses listes en y revenant.
            if let connu = demonstrations[profil.id] { return connu }
            let conteneur = try EntrepotSeance.conteneur(.memoire)
            if !Demonstration.vide, ProfilsFamille().actif.estPrincipal { Demonstration.remplir(conteneur.mainContext) }
            demonstrations[ProfilsFamille().actif.id] = conteneur
            return conteneur
        }
        #endif
        return try EntrepotSeance.conteneur(ProfilsFamille().actif.emplacement)
    } }

    /// Passe à un autre profil de la famille : le foyer (plateformes, chaînes) suit, le prénom aussi, puis le magasin
    /// s'ouvre. L'app, prévenue par `Notification.Name.profilChange`, reconstruit son état et ses écrans.
    static func changerDeProfil(vers profil: ProfilFamille) {
        let famille = ProfilsFamille()
        var ancien = famille.actif
        guard ancien.id != profil.id else { return }
        // Le prénom saisi dans Réglages › Toi appartient au profil qu'on quitte.
        if let prenom = Prenom.lire(), prenom != ancien.prenom { ancien.prenom = prenom; famille.modifier(ancien) }
        let source = conteneur
        famille.activer(profil)
        UserDefaults.standard.set(profil.prenom, forKey: Prenom.cle)
        resultat = ouvrir()
        if let source, let cible = conteneur { try? ServiceFamille.partagerLeFoyer(de: source.mainContext, vers: cible.mainContext) }
        NotificationCenter.default.post(name: .profilChange, object: nil)
    }

    static var conteneur: ModelContainer? {
        try? resultat.get()
    }
}

/// Nom commun avec le widget : le ✓ des épisodes s'exécute dans l'un ou l'autre processus.
@MainActor
enum ConteneurPartage {
    static var conteneur: ModelContainer? {
        ConteneurApp.conteneur
    }
}

extension Notification.Name {
    /// Un autre profil de la famille vient d'être choisi : l'app rouvre son magasin et reconstruit son état.
    static let profilChange = Notification.Name("seance.profilChange")
}
