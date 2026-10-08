import Foundation

/// Le menu d'un titre (8.2.15, demande de Patrick) : appui long sur l'iPhone et l'iPad, clic droit sur le Mac, appui
/// long à la télécommande. Une seule liste, dans le même ordre et avec les mêmes mots partout ; chaque plateforme doit
/// traiter chaque action (un `switch` sans `default`) : en oublier une ne compile pas.
public enum ActionTitre: String, CaseIterable, Sendable, Hashable {
    case regarder, voirFiche, aVoir, vuAujourdhui, dejaVuAvant, ceSoir, autreSoir
    case pasInteresse, jAime, jeNaimePas

    /// Ce qui décide des actions montrées.
    public struct Etat: Sendable, Hashable {
        public var dansMaListe: Bool
        public var vu: Bool
        public var prevuCeSoir: Bool

        public init(dansMaListe: Bool = false, vu: Bool = false, prevuCeSoir: Bool = false) {
            self.dansMaListe = dansMaListe
            self.vu = vu
            self.prevuCeSoir = prevuCeSoir
        }
    }

    /// Le menu, dans l'ordre : regarder d'abord, puis ranger, puis dire ce qu'on en pense.
    public static func menu(_ type: TypeTitre, etat: Etat) -> [ActionTitre] {
        allCases.filter { action in
            switch action {
            case .aVoir: !etat.dansMaListe
            case .vuAujourdhui: type == .film && !etat.vu
            case .dejaVuAvant: !etat.vu
            case .ceSoir: !etat.prevuCeSoir
            default: true
            }
        }
    }

    public func libelle(_ type: TypeTitre, etat: Etat = Etat()) -> String {
        switch self {
        case .regarder: "Regarder"
        case .voirFiche: "Voir la fiche"
        case .aVoir: "Ajouter à Ma liste"
        case .vuAujourdhui: "Vu aujourd'hui"
        case .dejaVuAvant: type == .film ? "Déjà vu avant" : "Toute la série déjà vue avant"
        case .ceSoir: "Ce soir"
        case .autreSoir: "Un autre soir…"
        case .pasInteresse: "Pas intéressé pour l'instant"
        case .jAime: "J'aime"
        case .jeNaimePas: "Je n'aime pas"
        }
    }

    public var symbole: String {
        switch self {
        case .regarder: "play.fill"
        case .voirFiche: "info.circle"
        case .aVoir: "plus"
        case .vuAujourdhui: "eye"
        case .dejaVuAvant: "clock.arrow.circlepath"
        case .ceSoir: "moon.stars"
        case .autreSoir: "calendar"
        case .pasInteresse: "hand.raised"
        case .jAime: "hand.thumbsup"
        case .jeNaimePas: "hand.thumbsdown"
        }
    }

    public var destructive: Bool { self == .jeNaimePas }

    /// Un séparateur avant cette action : entre regarder, ranger et donner son avis. 8.11 : sans listes nommées ni
    /// favoris — « J'aime » et la note disent déjà ce qu'on aime.
    public var ouvreUnGroupe: Bool { self == .aVoir || self == .pasInteresse }
}
