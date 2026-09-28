import Foundation
import SeanceDonnees
import SeanceKit

/// Ton prénom, saisi dans Réglages : Séance te parle plus familièrement quand elle propose quelque chose.
/// Vide, les phrases restent neutres.
enum Prenom {
    static let cle = "profil.prenom"

    /// Le prénom nettoyé, ou `nil` s'il n'est pas renseigné.
    static func lire(_ brut: String = UserDefaults.standard.string(forKey: cle) ?? "") -> String? {
        let propre = brut.trimmingCharacters(in: .whitespacesAndNewlines)
        return propre.isEmpty ? nil : String(propre.prefix(30))
    }

    /// « Bonsoir Patrick » le soir et la nuit, « Bonjour Patrick » le jour ; sans prénom, « Bonsoir » tout court.
    static func salut(_ prenom: String?, maintenant: Date = .now, calendrier: Calendar = .current) -> String {
        let heure = calendrier.component(.hour, from: maintenant)
        let mot = (5..<18).contains(heure) ? "Bonjour" : "Bonsoir"
        return prenom.map { "\(mot) \($0)" } ?? mot
    }

    /// Ajoute « , Patrick » à la fin d'une phrase courte : « Rien de prévu ce soir, Patrick ».
    static func interpeller(_ phrase: String, _ prenom: String?) -> String {
        prenom.map { "\(phrase), \($0)" } ?? phrase
    }
}

/// Combien d'idées « Idées pour ce soir » montre à la fois.
enum NombreIdees {
    static let cle = "cesoir.nombreIdees"
    static let choix = [3, 5, 10]
    static let parDefaut = 5

    static func lire(_ brut: Int) -> Int {
        choix.contains(brut) ? brut : parDefaut
    }

    /// Les idées classées d'avance : de quoi remplacer celles qu'on écarte, sans en demander trop à Claude.
    static var aClasser: Int {
        max(12, lire(UserDefaults.standard.integer(forKey: cle)) + 7)
    }
}

/// Les réglages qui voyagent dans la sauvegarde : prénom, personnalisation de l'accueil, tri et présentation des listes,
/// réglages des alertes, adresse et dossiers du NAS. Jamais une clé ni un mot de passe : ils restent dans le trousseau.
@MainActor
enum PreferencesSauvegardees {
    private static let textes = [Prenom.cle, "listes.tri"]
    private static let entiers = [NombreIdees.cle]
    private static let booleens = ["listes.grille", "explorer.liste", BlueTV.cle]
    private static let donnees = ["accueil.sources"]
    static let cleAlertes = "alertes.reglages"
    static let cleNAS = "nas.reglages"

    /// Les alertes et l'e-mail de la semaine se règlent par personne (8.2.17) : sur l'appareil, sous une clé propre au
    /// profil en cours ; dans la synchronisation, sous leur nom commun, dans le sous-dossier de ce profil.
    static func ici(_ cle: String, profil: String = ProfilsFamille().actif.id) -> String {
        switch cle {
        case cleAlertes: EtatAlertes.cleReglages(profil: profil)
        case EtatLettre.cle: EtatLettre.cle(profil: profil)
        case EtatLettre.cleDernier: EtatLettre.cleDernier(profil: profil)
        default: cle
        }
    }

    /// Ce qui a été réglé sur cet appareil ; un réglage jamais touché n'est pas exporté.
    static func lire(_ defauts: UserDefaults = .standard) -> [String: Sauvegarde.Preference] {
        var resultat: [String: Sauvegarde.Preference] = [:]
        for cle in textes { if let valeur = defauts.string(forKey: cle), !valeur.isEmpty { resultat[cle] = .texte(valeur) } }
        for cle in entiers where defauts.object(forKey: cle) != nil { resultat[cle] = .entier(defauts.integer(forKey: cle)) }
        for cle in booleens where defauts.object(forKey: cle) != nil { resultat[cle] = .booleen(defauts.bool(forKey: cle)) }
        for cle in donnees + [cleAlertes, cleNAS, EtatVideosPerso.cleReglages, EtatLettre.cle, CouverturesSouvenirs.cle, PositionsLecture.cle, IdentificationsTMDB.cle] { if let valeur = defauts.data(forKey: ici(cle)) { resultat[cle] = .donnees(valeur) } }
        // La famille : les personnes créées ici arrivent sur les autres appareils, Apple TV comprise.
        if let famille = ProfilsFamille().exporter() { resultat[ProfilsFamille.cleSynchro] = .donnees(famille) }
        // L'e-mail de la semaine : ses réglages voyagent (destinataires, jour, compte — jamais le mot de passe), et la
        // date du dernier envoi aussi, pour que deux appareils ne l'envoient pas chacun de leur côté.
        if let envoi = defauts.object(forKey: ici(EtatLettre.cleDernier)) as? Date { resultat[EtatLettre.cleDernier] = .entier(Int(envoi.timeIntervalSince1970)) }
        return resultat
    }

    /// Applique les réglages importés qui n'ont jamais été touchés ici, comme le reste de l'import : rien n'est écrasé.
    /// Renvoie le nombre de réglages repris.
    /// `remplacer` : pour les réglages qu'un autre appareil a modifiés plus récemment (synchronisation).
    static func appliquer(_ preferences: [String: Sauvegarde.Preference], etat: EtatApp, remplacer: Bool = false, defauts: UserDefaults = .standard) -> Int {
        var repris = 0
        // La date du dernier e-mail envoyé se compare toujours : la plus récente l'emporte. Les couvertures des souvenirs
        // aussi, entrée par entrée (6.2).
        for (cle, valeur) in preferences where remplacer || defauts.object(forKey: ici(cle)) == nil || cle == EtatLettre.cleDernier || cle == CouverturesSouvenirs.cle || cle == PositionsLecture.cle
            || cle == IdentificationsTMDB.cle {
            switch (cle, valeur) {
            case (cleAlertes, .donnees(let brut)):
                // Les alertes et le NAS gardent leurs réglages en mémoire : ils passent par leur propre porte.
                guard let reglages = try? JSONDecoder().decode(ReglagesAlertes.self, from: brut) else { continue }
                etat.alertes.modifier { $0 = reglages }
            case (cleNAS, .donnees(let brut)):
                guard let reglages = try? JSONDecoder().decode(ReglagesNAS.self, from: brut) else { continue }
                etat.nas.enregistrer(reglages)
            case (ProfilsFamille.cleSynchro, .donnees(let brut)):
                guard ProfilsFamille().fusionner(brut) > 0 else { continue }
            case (EtatLettre.cle, .donnees(let brut)):
                guard let reglages = try? JSONDecoder().decode(EtatLettre.Reglages.self, from: brut) else { continue }
                etat.lettre.enregistrer(reglages)
            case (EtatLettre.cleDernier, .entier(let secondes)):
                etat.lettre.noterEnvoiAilleurs(Date(timeIntervalSince1970: TimeInterval(secondes)))
            case (CouverturesSouvenirs.cle, .donnees(let brut)):
                guard etat.videosPerso.recevoirCouvertures(brut) else { continue }
            // Où l'on s'est arrêté (8.0) : la position la plus récente l'emporte, vidéo par vidéo.
            case (PositionsLecture.cle, .donnees(let brut)):
                guard etat.nas.recevoirPositions(brut) else { continue }
            // Les titres identifiés à la main (8.4) : le choix le plus récent l'emporte, œuvre par œuvre.
            case (IdentificationsTMDB.cle, .donnees(let brut)):
                guard etat.nas.recevoirIdentifications(brut) else { continue }
            case (EtatVideosPerso.cleReglages, .donnees(let brut)):
                guard let reglages = try? JSONDecoder().decode(ReglagesVideosPerso.self, from: brut) else { continue }
                etat.videosPerso.enregistrer(reglages)
            case (_, .texte(let texte)) where textes.contains(cle): defauts.set(texte, forKey: cle)
            case (_, .entier(let entier)) where entiers.contains(cle): defauts.set(entier, forKey: cle)
            case (_, .booleen(let booleen)) where booleens.contains(cle): defauts.set(booleen, forKey: cle)
            case (_, .donnees(let brut)) where donnees.contains(cle): defauts.set(brut, forKey: cle)
            default: continue
            }
            repris += 1
        }
        return repris
    }
}
