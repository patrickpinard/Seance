import Foundation

/// Les critères d'Explorer que TMDB ne sait pas appliquer : l'app les applique aux résultats reçus (EF-59).
public struct FiltresLocaux: Sendable, Hashable, Codable {
    public enum DejaVu: String, Sendable, Codable, CaseIterable {
        case tous
        case vus
        case pasVus
    }

    public enum Tele: String, Sendable, Codable, CaseIterable {
        case indifferent
        /// Début entre 20 h et 23 h aujourd'hui (EF-46).
        case ceSoir
        /// Début dans les 7 prochains jours.
        case cetteSemaine
    }

    public var dejaVu: DejaVu = .tous
    public var obtention: CritereObtention = .tous
    public var tele: Tele = .indifferent
    /// Chaînes retenues pour le critère télé ; vide = toutes.
    public var chaines: Set<String> = []
    /// Acteurs exigés pour une série : TMDB ne filtre pas les séries par personne.
    public var acteursSerie: Set<Int> = []
    /// Applique la règle de langue (EF-28).
    public var regleLangue = true

    public init() {}
}

/// Ce que l'app sait d'un résultat pour lui appliquer les filtres locaux.
public struct ContexteResultat: Sendable {
    public var reference: ReferenceTitre
    public var langueOriginale: String?
    public var exclusionLangue: Bool
    public var estVu: Bool
    public var disponibilite: EtatDisponibilite
    public var diffusions: [DiffusionPrevue]
    /// Pour une série : identifiants des acteurs de son casting.
    public var acteurs: Set<Int>

    public init(
        reference: ReferenceTitre, langueOriginale: String?, exclusionLangue: Bool = false, estVu: Bool = false,
        disponibilite: EtatDisponibilite, diffusions: [DiffusionPrevue] = [], acteurs: Set<Int> = []
    ) {
        self.reference = reference
        self.langueOriginale = langueOriginale
        self.exclusionLangue = exclusionLangue
        self.estVu = estVu
        self.disponibilite = disponibilite
        self.diffusions = diffusions
        self.acteurs = acteurs
    }
}

extension FiltresLocaux {
    public func retient(_ resultat: ContexteResultat, maintenant: Date, fuseau: TimeZone = .suisse) -> Bool {
        let diffusionsRetenues = resultat.diffusions.filter { chaines.isEmpty || chaines.contains($0.chaine) }

        if regleLangue, !RegleLangue.accepte(
            langueOriginale: resultat.langueOriginale,
            exclu: resultat.exclusionLangue,
            diffuseSurChaineFrancophone: tele != .indifferent && !diffusionsRetenues.isEmpty
        ) {
            return false
        }

        switch dejaVu {
        case .tous: break
        case .vus: guard resultat.estVu else { return false }
        case .pasVus: guard !resultat.estVu else { return false }
        }

        guard obtention.retient(resultat.disponibilite) else { return false }

        if resultat.reference.type == .serie, !acteursSerie.isSubset(of: resultat.acteurs) {
            return false
        }

        switch tele {
        case .indifferent:
            return true
        case .ceSoir:
            let jour = DateTMDB(maintenant, fuseau: fuseau)
            let debutSoiree = jour.instant(heure: 20, fuseau: fuseau)
            let finSoiree = jour.instant(heure: 23, fuseau: fuseau)
            return diffusionsRetenues.contains { $0.debut >= debutSoiree && $0.debut <= finSoiree && $0.fin > maintenant }
        case .cetteSemaine:
            let limite = maintenant.addingTimeInterval(7 * 24 * 3600)
            return diffusionsRetenues.contains { $0.fin > maintenant && $0.debut <= limite }
        }
    }
}
