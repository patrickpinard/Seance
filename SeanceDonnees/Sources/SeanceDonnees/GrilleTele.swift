import Foundation
import SeanceKit
import SwiftData

/// Un passage à l'écran tel qu'on le lit dans un programme : un film, ou les épisodes d'une même série
/// qui s'enchaînent sur la même chaîne (« S08E01 et E02 »), réunis au lieu d'être répétés.
public struct BlocDiffusion: Identifiable {
    /// Jamais vide, dans l'ordre de passage.
    public let diffusions: [Diffusion]

    public var premiere: Diffusion { diffusions[0] }
    public var id: PersistentIdentifier { premiere.persistentModelID }
    public var debut: Date { premiere.debut }
    public var fin: Date { diffusions[diffusions.count - 1].fin }
    public var estFilm: Bool { premiere.typeBrut == TypeTitre.film.rawValue }

    public var reference: ReferenceTitre? {
        premiere.tmdbID.map { ReferenceTitre(type: TypeTitre(rawValue: premiere.typeBrut) ?? .film, tmdbID: $0) }
    }

    public var dureeMinutes: Int {
        Int(fin.timeIntervalSince(debut) / 60)
    }

    /// La part déjà diffusée, de 0 à 1 ; `nil` hors antenne.
    public func avancement(maintenant: Date = .now) -> Double? {
        guard debut <= maintenant, maintenant < fin, fin > debut else { return nil }
        return maintenant.timeIntervalSince(debut) / fin.timeIntervalSince(debut)
    }

    /// « S08E01 », « S08E01 et E02 », « S08E01 à E04 » ; le nombre d'épisodes quand le guide ne les numérote pas.
    public var libelleEpisodes: String? {
        guard !estFilm else { return nil }
        let numeros = diffusions.compactMap { diffusion -> NumeroEpisode? in
            guard let saison = diffusion.saison, let episode = diffusion.episode else { return nil }
            return NumeroEpisode(saison: saison, episode: episode)
        }
        guard let premier = numeros.first, let dernier = numeros.last, numeros.count == diffusions.count else {
            return diffusions.count > 1 ? "\(diffusions.count) épisodes" : nil
        }
        guard diffusions.count > 1 else { return premier.description }
        // Certains guides donnent le même numéro à tous les épisodes d'une soirée : « S08E01 et E01 » ne dirait rien.
        guard premier != dernier else { return "\(premier.description) · \(diffusions.count) épisodes" }
        let suite = premier.saison == dernier.saison ? String(format: "E%02d", dernier.episode) : dernier.description
        return "\(premier.description) \(diffusions.count == 2 ? "et" : "à") \(suite)"
    }
}

/// Les moments d'une journée de télé, dans l'ordre où on les lit : ce qui passe, la soirée, puis le reste.
public enum MomentTele: Int, CaseIterable, Sendable {
    case enCours, soiree, journee, nuit
}

public enum GrilleTele {
    /// Deux épisodes se suivent s'ils sont séparés de moins d'un quart d'heure (publicité, météo).
    static let pauseMaximale: TimeInterval = 15 * 60

    /// Réunit, chaîne par chaîne, les épisodes d'une même série qui s'enchaînent. Résultat trié par heure de début.
    public static func blocs(_ diffusions: [Diffusion]) -> [BlocDiffusion] {
        var groupes: [[Diffusion]] = []
        var ouvert: [String: Int] = [:]
        for diffusion in diffusions.sorted(by: { $0.debut < $1.debut }) {
            if diffusion.typeBrut == TypeTitre.serie.rawValue, let indice = ouvert[diffusion.chaine],
               let precedente = groupes[indice].last, memeSerie(precedente, diffusion),
               diffusion.debut.timeIntervalSince(precedente.fin) < pauseMaximale {
                groupes[indice].append(diffusion)
            } else {
                ouvert[diffusion.chaine] = groupes.count
                groupes.append([diffusion])
            }
        }
        return groupes.map(BlocDiffusion.init).sorted { $0.debut < $1.debut }
    }

    private static func memeSerie(_ a: Diffusion, _ b: Diffusion) -> Bool {
        guard a.typeBrut == b.typeBrut else { return false }
        if let idA = a.tmdbID, let idB = b.tmdbID { return idA == idB }
        return a.titreGuide.compare(b.titreGuide, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// En soirée : ce qui commence entre 20 h et 23 h. La nuit : après 23 h et avant 6 h.
    public static func moment(_ bloc: BlocDiffusion, maintenant: Date = .now, calendrier: Calendar = .current) -> MomentTele {
        if bloc.debut <= maintenant, maintenant < bloc.fin { return .enCours }
        switch calendrier.component(.hour, from: bloc.debut) {
        case 20..<23: return .soiree
        case 6..<20: return .journee
        default: return .nuit
        }
    }

    /// Le soir auquel un passage appartient : un film de 1 h du matin se regarde la veille au soir.
    public static func soir(_ bloc: BlocDiffusion, calendrier: Calendar = .current) -> Date {
        soir(bloc.debut, calendrier: calendrier)
    }

    private static func soir(_ instant: Date, calendrier: Calendar) -> Date {
        calendrier.component(.hour, from: instant) < 6 ? instant.addingTimeInterval(-86_400) : instant
    }

    /// La journée télé va de 6 h à 6 h, comme une soirée : minuit dix se range à la fin de la veille, après 23 h 50.
    public static func jourTele(_ instant: Date, calendrier: Calendar = .current) -> DateTMDB {
        DateTMDB(soir(instant, calendrier: calendrier))
    }
}
