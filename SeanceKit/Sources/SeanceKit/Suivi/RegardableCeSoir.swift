import Foundation

/// Mes listes, « Regardable ce soir » : ce qui se regarde sans rien acheter ni attendre.
public enum RegardableCeSoir {
    /// Sur le NAS, dans les abonnements (ou gratuit), ou à la TV avant la fin de la soirée (2 h du matin).
    public static func retient(_ etat: EtatDisponibilite, maintenant: Date, fuseau: TimeZone = .suisse) -> Bool {
        switch etat {
        case .surNAS, .dansAbonnements:
            return true
        case .aLaTeleBientot(let diffusion):
            return diffusion.fin > maintenant && diffusion.debut < finDeSoiree(maintenant, fuseau: fuseau)
        case .aLouerOuAcheter, .introuvable:
            return false
        }
    }

    /// 2 h du matin suivant ; après minuit, la soirée en cours se termine à 2 h le même jour.
    static func finDeSoiree(_ maintenant: Date, fuseau: TimeZone) -> Date {
        let jour = DateTMDB(maintenant.addingTimeInterval(-2 * 3600), fuseau: fuseau)
        return jour.instant(heure: 0, fuseau: fuseau).addingTimeInterval(26 * 3600)
    }

    /// Libellé court sous le titre : « Netflix », « Sur le NAS · 4K », « RTS 1 à 20:55 ».
    public static func libelle(_ etat: EtatDisponibilite, fuseau: TimeZone = .suisse) -> String? {
        switch etat {
        case .surNAS(let qualite): return ["Sur le NAS", qualite?.description].compactMap { $0 }.joined(separator: " · ")
        case .dansAbonnements(let fournisseurs): return fournisseurs.first?.nom
        case .aLaTeleBientot(let diffusion):
            let heure = diffusion.debut.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "fr_CH"), timeZone: fuseau))
            return "\(diffusion.chaine) à \(heure)"
        case .aLouerOuAcheter: return "À louer ou acheter"
        case .introuvable: return nil
        }
    }
}

/// Ordre d'une liste de Mes listes.
public enum TriListe: String, CaseIterable, Sendable, Codable {
    case ajout = "Ajout récent"
    case plusCourt = "Plus court d'abord"
    case titre = "Titre"

    public struct Element: Sendable, Hashable {
        public var reference: ReferenceTitre
        public var titre: String
        public var ajouteLe: Date
        /// Durée d'un film, ou d'un épisode pour une série ; inconnue avant la lecture de la fiche.
        public var dureeMinutes: Int?

        public init(reference: ReferenceTitre, titre: String, ajouteLe: Date, dureeMinutes: Int?) {
            self.reference = reference
            self.titre = titre
            self.ajouteLe = ajouteLe
            self.dureeMinutes = dureeMinutes
        }
    }

    /// Une durée inconnue passe en dernier ; à égalité, le plus récemment ajouté d'abord.
    public func trier(_ elements: [Element]) -> [Element] {
        switch self {
        case .ajout:
            return elements.sorted { $0.ajouteLe > $1.ajouteLe }
        case .plusCourt:
            return elements.sorted { a, b in
                switch (a.dureeMinutes, b.dureeMinutes) {
                case let (x?, y?) where x != y: return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.ajouteLe > b.ajouteLe
                }
            }
        case .titre:
            return elements.sorted { $0.titre.localizedStandardCompare($1.titre) == .orderedAscending }
        }
    }
}
