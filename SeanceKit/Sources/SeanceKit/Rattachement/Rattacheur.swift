import Foundation

/// Un titre TMDB auquel on cherche à rattacher une diffusion TV ou un fichier du NAS.
public struct CandidatRattachement: Sendable, Hashable {
    public let tmdbID: Int
    public let type: TypeTitre
    public let titre: String
    public let titreOriginal: String
    /// Année de sortie d'un film, ou de première diffusion d'une série.
    public let annee: Int?

    public init(tmdbID: Int, type: TypeTitre, titre: String, titreOriginal: String, annee: Int?) {
        self.tmdbID = tmdbID
        self.type = type
        self.titre = titre
        self.titreOriginal = titreOriginal
        self.annee = annee
    }
}

extension FilmResume {
    public var candidat: CandidatRattachement {
        CandidatRattachement(tmdbID: id, type: .film, titre: titre, titreOriginal: titreOriginal, annee: dateSortie?.annee)
    }
}

extension SerieResume {
    public var candidat: CandidatRattachement {
        CandidatRattachement(tmdbID: id, type: .serie, titre: nom, titreOriginal: nomOriginal, annee: premiereDiffusion?.annee)
    }
}

public enum NormalisationTitre {
    private static let articlesInitiaux: Set<String> = ["le", "la", "les", "l", "un", "une", "the", "a", "an"]

    /// « Mission : Impossible – Fallout » et « Mission: Impossible - Fallout » donnent
    /// tous deux « mission impossible fallout ». L'article initial est retiré : les guides TV
    /// l'omettent souvent.
    public static func normaliser(_ titre: String) -> String {
        let minuscules = titre.lowercased()
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "æ", with: "ae")
            .replacingOccurrences(of: "&", with: " et ")
        let replie = minuscules.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "fr_FR"))
        let mots = replie.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined()
            .split(separator: " ")
            .map(String.init)
        guard mots.count > 1, let premier = mots.first, articlesInitiaux.contains(premier) else {
            return mots.joined(separator: " ")
        }
        return mots.dropFirst().joined(separator: " ")
    }
}

/// Règle de rattachement du cahier des exigences : titre français ou original identique
/// après normalisation, et année cohérente ; sinon rien n'est rattaché (EF-51).
public enum Rattacheur {
    public static let toleranceAnnees = 1

    public static func correspond(titre: String, annee: Int?, candidat: CandidatRattachement) -> Bool {
        guard let annee, let anneeCandidat = candidat.annee else { return false }
        switch candidat.type {
        case .film:
            guard abs(annee - anneeCandidat) <= toleranceAnnees else { return false }
        case .serie:
            // L'année d'un guide TV est celle de l'épisode : elle suit la première diffusion.
            guard annee >= anneeCandidat - toleranceAnnees else { return false }
        }
        let normalise = NormalisationTitre.normaliser(titre)
        guard !normalise.isEmpty else { return false }
        return normalise == NormalisationTitre.normaliser(candidat.titre)
            || normalise == NormalisationTitre.normaliser(candidat.titreOriginal)
    }

    /// Le candidat retenu, ou `nil` si aucun ne correspond ou si plusieurs titres TMDB différents correspondent.
    public static func rattacher(titre: String, annee: Int?, parmi candidats: [CandidatRattachement]) -> CandidatRattachement? {
        let retenus = candidats.filter { correspond(titre: titre, annee: annee, candidat: $0) }
        let identifiants = Set(retenus.map { "\($0.type.rawValue):\($0.tmdbID)" })
        return identifiants.count == 1 ? retenus.first : nil
    }
}

extension ProgrammeTV {
    /// Rattache une diffusion à TMDB ; les programmes qui ne sont ni films ni séries ne le sont jamais.
    public func rattacher(parmi candidats: [CandidatRattachement]) -> CandidatRattachement? {
        let type: TypeTitre
        switch nature {
        case .film: type = .film
        case .serie: type = .serie
        case .autre: return nil
        }
        return Rattacheur.rattacher(titre: titre, annee: annee, parmi: candidats.filter { $0.type == type })
    }
}
