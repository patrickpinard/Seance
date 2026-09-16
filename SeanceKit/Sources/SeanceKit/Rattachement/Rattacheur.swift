import Foundation

/// Un titre TMDB auquel on cherche à rattacher une diffusion TV ou un fichier du NAS.
public struct CandidatRattachement: Sendable, Hashable {
    public let tmdbID: Int
    public let type: TypeTitre
    public let titre: String
    public let titreOriginal: String
    /// Année de sortie d'un film, ou de première diffusion d'une série.
    public let annee: Int?
    /// Images TMDB, reprises par les cartes « Ce soir à la télé ».
    public var cheminAffiche: String?
    public var cheminFond: String?

    public init(tmdbID: Int, type: TypeTitre, titre: String, titreOriginal: String, annee: Int?,
                cheminAffiche: String? = nil, cheminFond: String? = nil) {
        self.tmdbID = tmdbID
        self.type = type
        self.titre = titre
        self.titreOriginal = titreOriginal
        self.annee = annee
        self.cheminAffiche = cheminAffiche
        self.cheminFond = cheminFond
    }
}

extension FilmResume {
    public var candidat: CandidatRattachement {
        CandidatRattachement(tmdbID: id, type: .film, titre: titre, titreOriginal: titreOriginal, annee: dateSortie?.annee,
                             cheminAffiche: cheminAffiche, cheminFond: cheminFond)
    }
}

extension SerieResume {
    public var candidat: CandidatRattachement {
        CandidatRattachement(tmdbID: id, type: .serie, titre: nom, titreOriginal: nomOriginal, annee: premiereDiffusion?.annee,
                             cheminAffiche: cheminAffiche, cheminFond: cheminFond)
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
            // « Jerry and Marge » et « Jerry & Marge » : la conjonction anglaise vaut l'esperluette.
            .map { $0 == "and" ? "et" : String($0) }
        guard mots.count > 1, let premier = mots.first, articlesInitiaux.contains(premier) else {
            return mots.joined(separator: " ")
        }
        return mots.dropFirst().joined(separator: " ")
    }

    /// Forme sans espaces : « Tyler Perrys » et « Tyler Perry's » se rejoignent.
    public static func compacter(_ titre: String) -> String {
        normaliser(titre).replacingOccurrences(of: " ", with: "")
    }

    /// Égalité normale ou compacte.
    public static func equivalents(_ a: String, _ b: String) -> Bool {
        let na = normaliser(a)
        guard !na.isEmpty else { return false }
        return na == normaliser(b) || compacter(a) == compacter(b)
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
        return NormalisationTitre.equivalents(titre, candidat.titre)
            || NormalisationTitre.equivalents(titre, candidat.titreOriginal)
    }

    /// Programme sans année (fréquent dans les guides TV) : retenu seulement si un seul titre TMDB
    /// porte ce nom, en français ou en version originale.
    public static func rattacherSansAnnee(titre: String, parmi candidats: [CandidatRattachement]) -> CandidatRattachement? {
        let retenus = candidats.filter {
            NormalisationTitre.equivalents(titre, $0.titre) || NormalisationTitre.equivalents(titre, $0.titreOriginal)
        }
        return Set(retenus.map(\.tmdbID)).count == 1 ? retenus.first : nil
    }

    /// Le candidat retenu, ou `nil` si aucun ne correspond ou si plusieurs titres TMDB différents correspondent.
    public static func rattacher(titre: String, annee: Int?, parmi candidats: [CandidatRattachement]) -> CandidatRattachement? {
        let retenus = candidats.filter { correspond(titre: titre, annee: annee, candidat: $0) }
        let identifiants = Set(retenus.map { "\($0.type.rawValue):\($0.tmdbID)" })
        if identifiants.count == 1 { return retenus.first }
        // Homonymes à un an près (« Safe House » 2024 et 2025) : l'année exacte départage, si elle est unique.
        let exacts = retenus.filter { $0.annee == annee }
        return Set(exacts.map(\.tmdbID)).count == 1 ? exacts.first : nil
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
        let memeType = candidats.filter { $0.type == type }
        guard let annee else { return Rattacheur.rattacherSansAnnee(titre: titre, parmi: memeType) }
        return Rattacheur.rattacher(titre: titre, annee: annee, parmi: memeType)
    }
}
