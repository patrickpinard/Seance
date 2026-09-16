import Foundation

/// Règle de langue du cahier (EF-28, EF-29).
public enum RegleLangue {
    public static let languesOriginalesAcceptees: Set<String> = ["fr", "en"]

    /// - Parameters:
    ///   - exclu: Patrick a signalé « Ni VF ni sous-titres FR » ; l'exclusion vaut partout.
    ///   - diffuseSurChaineFrancophone: les chaînes francophones diffusent en version française.
    public static func accepte(langueOriginale: String?, exclu: Bool, diffuseSurChaineFrancophone: Bool = false) -> Bool {
        guard !exclu else { return false }
        if diffuseSurChaineFrancophone { return true }
        guard let langue = langueOriginale?.lowercased() else { return false }
        return languesOriginalesAcceptees.contains(langue)
    }
}

public enum QualiteVideo: Int, Sendable, Codable, Comparable, CaseIterable, CustomStringConvertible {
    case sd = 480
    case hd720 = 720
    case hd1080 = 1080
    case uhd4K = 2160

    public static func < (a: QualiteVideo, b: QualiteVideo) -> Bool {
        a.rawValue < b.rawValue
    }

    public var description: String {
        switch self {
        case .sd: "SD"
        case .hd720: "720p"
        case .hd1080: "1080p"
        case .uhd4K: "4K"
        }
    }

    /// Relit le libellé stocké dans le magasin (« 1080p », « 4K »…).
    public init?(description: String) {
        guard let qualite = Self.allCases.first(where: { $0.description == description }) else { return nil }
        self = qualite
    }
}

/// Un film ou un épisode présent sur le NAS.
public struct CopieNAS: Sendable, Hashable {
    public var chemin: String
    public var qualite: QualiteVideo?

    public init(chemin: String, qualite: QualiteVideo?) {
        self.chemin = chemin
        self.qualite = qualite
    }
}

/// Un passage à la télé.
public struct DiffusionPrevue: Sendable, Hashable {
    public var chaine: String
    public var debut: Date
    public var fin: Date

    public init(chaine: String, debut: Date, fin: Date) {
        self.chaine = chaine
        self.debut = debut
        self.fin = fin
    }
}

/// Ce qu'on sait d'un titre pour dire où le regarder.
public struct SourcesTitre: Sendable {
    public var nas: [CopieNAS] = []
    public var offres: OffresRegion?
    /// Plateformes cochées par Patrick (identifiants TMDB).
    public var abonnements: Set<Int> = []
    public var diffusions: [DiffusionPrevue] = []

    public init(nas: [CopieNAS] = [], offres: OffresRegion? = nil, abonnements: Set<Int> = [], diffusions: [DiffusionPrevue] = []) {
        self.nas = nas
        self.offres = offres
        self.abonnements = abonnements
        self.diffusions = diffusions
    }
}

/// L'état affiché en tête du bloc « Où regarder » (EF-73).
public enum EtatDisponibilite: Sendable, Equatable {
    case surNAS(qualite: QualiteVideo?)
    case dansAbonnements([Fournisseur])
    case aLaTeleBientot(DiffusionPrevue)
    case aLouerOuAcheter(location: [Fournisseur], achat: [Fournisseur])
    case introuvable
}

/// Une source légale pour obtenir un titre absent du NAS et des abonnements (EF-77, EF-80).
public enum SourceLegale: Sendable, Equatable {
    case tele(DiffusionPrevue)
    case location(Fournisseur)
    case achat(Fournisseur)
}

/// Le critère « Où l'obtenir » d'Explorer (EF-75).
public enum CritereObtention: String, Sendable, Codable, CaseIterable {
    case tous
    case surNAS
    case pasSurNAS
    case nasOuAbonnements
    case aObtenir

    public func retient(_ etat: EtatDisponibilite) -> Bool {
        switch (self, etat) {
        case (.tous, _): true
        case (.surNAS, .surNAS): true
        case (.surNAS, _): false
        case (.pasSurNAS, .surNAS): false
        case (.pasSurNAS, _): true
        case (.nasOuAbonnements, .surNAS), (.nasOuAbonnements, .dansAbonnements): true
        case (.nasOuAbonnements, _): false
        case (.aObtenir, .aLaTeleBientot), (.aObtenir, .aLouerOuAcheter), (.aObtenir, .introuvable): true
        case (.aObtenir, _): false
        }
    }
}

public enum Disponibilite {
    /// Ordre de priorité : NAS, abonnements (y compris offres gratuites), télé à venir, location ou achat.
    public static func etat(_ sources: SourcesTitre, maintenant: Date) -> EtatDisponibilite {
        if !sources.nas.isEmpty {
            return .surNAS(qualite: sources.nas.compactMap(\.qualite).max())
        }
        let inclus = fournisseursInclus(sources)
        if !inclus.isEmpty {
            return .dansAbonnements(inclus)
        }
        if let diffusion = diffusionsAVenir(sources.diffusions, maintenant: maintenant).first {
            return .aLaTeleBientot(diffusion)
        }
        let location = sources.offres?.location ?? []
        let achat = sources.offres?.achat ?? []
        if !location.isEmpty || !achat.isEmpty {
            return .aLouerOuAcheter(location: location, achat: achat)
        }
        return .introuvable
    }

    /// Sources légales triées : télé (la plus proche d'abord), location, achat (EF-77).
    public static func sourcesAObtenir(_ sources: SourcesTitre, maintenant: Date) -> [SourceLegale] {
        let tele = diffusionsAVenir(sources.diffusions, maintenant: maintenant).map(SourceLegale.tele)
        let location = (sources.offres?.location ?? []).sorted { $0.priorite < $1.priorite }.map(SourceLegale.location)
        let achat = (sources.offres?.achat ?? []).sorted { $0.priorite < $1.priorite }.map(SourceLegale.achat)
        return tele + location + achat
    }

    /// Plateformes cochées qui proposent le titre en abonnement, plus les offres gratuites.
    static func fournisseursInclus(_ sources: SourcesTitre) -> [Fournisseur] {
        guard let offres = sources.offres else { return [] }
        var vus = Set<Int>()
        let abonnes = offres.abonnement.filter { sources.abonnements.contains($0.id) }
        return (abonnes + offres.gratuit + offres.avecPublicite)
            .filter { vus.insert($0.id).inserted }
            .sorted { $0.priorite < $1.priorite }
    }

    /// Une diffusion déjà commencée reste proposée jusqu'à sa fin.
    static func diffusionsAVenir(_ diffusions: [DiffusionPrevue], maintenant: Date) -> [DiffusionPrevue] {
        diffusions.filter { $0.fin > maintenant }.sorted { $0.debut < $1.debut }
    }
}
