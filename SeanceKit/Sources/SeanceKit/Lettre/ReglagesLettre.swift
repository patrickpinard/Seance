import Foundation

/// Les réglages de l'e-mail de la semaine (8.2.17 : ici plutôt que dans l'app, pour que l'Apple TV les lise et les
/// modifie aussi). Un jeu par personne de la famille ; le compte d'envoi est celui de l'appareil qui envoie.
public struct ReglagesLettre: Codable, Equatable, Sendable {
    /// Ce que la lettre peut contenir (6.5) : chacun choisit ce qu'il veut recevoir.
    public enum Rubrique: String, Codable, CaseIterable, Identifiable, Sendable {
        case episodes, sorties, passagesTele, acteurs, nouveautes, soirees

        public var id: String { rawValue }

        public var nom: String {
            switch self {
            case .episodes: "Nouveaux épisodes de mes séries"
            case .sorties: "Sorties des titres que je suis"
            case .passagesTele: "Passages à la TV de mes titres"
            case .acteurs: "Nouveaux films de mes acteurs"
            case .nouveautes: "Nouveautés de mes plateformes"
            case .soirees: "Mes soirées prévues"
            }
        }

        public var symbole: String {
            switch self {
            case .episodes: "play.tv"
            case .sorties: "sparkles"
            case .passagesTele: "tv"
            case .acteurs: "person.fill"
            case .nouveautes: "rectangle.stack.badge.play"
            case .soirees: "moon.stars"
            }
        }
    }

    public var actif = false
    /// « a@x.ch ; b@y.ch » : tel que saisi.
    public var destinataires = ""
    public var compte = CompteSMTP()
    /// Jour de la semaine du calendrier (1 = dimanche … 7 = samedi) : gardé pour les réglages d'avant la 6.5.
    public var jour = 6
    public var heure = 17
    /// Les jours d'envoi (6.5) : un e-mail peut partir plusieurs fois par semaine. Vide : le seul `jour`.
    public var jours: Set<Int>?
    /// Les rubriques retenues. Absent : tout, comme avant la 6.5.
    public var rubriques: Set<Rubrique>?
    /// Les plateformes dont on veut les nouveautés (identifiants TMDB). Vide : toutes celles cochées.
    public var plateformes: Set<Int>?
    /// Les chaînes dont on veut les passages (noms). Vide : toutes celles cochées.
    public var chaines: Set<String>?

    public init() {}

    /// Les jours retenus, l'ancien réglage compris.
    public var joursRetenus: Set<Int> { (jours?.isEmpty == false ? jours : nil) ?? [jour] }
    /// Vrai si cette rubrique doit paraître.
    public func veut(_ rubrique: Rubrique) -> Bool { rubriques?.contains(rubrique) ?? true }

    /// Nom de ces réglages dans la synchronisation ; sur l'appareil, une clé par personne de la famille.
    public static let cle = "lettre.reglages"
    public static func cle(profil: String) -> String { profil.isEmpty ? cle : "\(cle).\(profil)" }

    public static func lire(_ defauts: UserDefaults = .standard, profil: String) -> ReglagesLettre? {
        defauts.data(forKey: cle(profil: profil)).flatMap { try? JSONDecoder().decode(ReglagesLettre.self, from: $0) }
    }
}
