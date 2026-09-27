import Foundation
import SeanceKit
import SwiftData

/// Met à jour les programmes TV du magasin : téléchargement, rattachement à TMDB, remplacement (EF-45 à EF-51).
@MainActor
public struct ServiceProgrammesTV {
    public struct Rapport: Equatable, Sendable {
        public var programmesLus = 0
        public var diffusionsEnregistrees = 0
        public var recherchesEnEchec = 0
        public var filmsLus = 0
        public var filmsRattaches = 0
        /// Films du guide introuvables dans TMDB, ou homonymes impossibles à départager.
        public var filmsNonRattaches: [String] = []
    }

    /// XML TV Fr demande au plus une lecture par jour ; deux par jour gardent la soirée à jour
    /// quand l'app est ouverte le matin puis le soir.
    public static let intervalleLecture: TimeInterval = 12 * 3600

    public let contexte: ModelContext
    public let guide: GuideTVClient
    public let rattachement: RattachementGuide

    public init(contexte: ModelContext, guide: GuideTVClient, rattachement: RattachementGuide) {
        self.contexte = contexte
        self.guide = guide
        self.rattachement = rattachement
    }

    /// Premier lancement : la RTS et les grandes chaînes françaises sont cochées d'office,
    /// pour que « Ce soir à la TV » ne reste pas vide faute de réglage.
    @discardableResult
    public static func preparerChaines(_ contexte: ModelContext) throws -> Bool {
        guard try contexte.fetchCount(FetchDescriptor<Chaine>()) == 0 else { return false }
        for chaine in ChaineGuide.parDefaut {
            contexte.insert(Chaine(identifiantGuide: chaine.id, nom: chaine.nom, source: .xmltvfr))
        }
        try contexte.save()
        return true
    }

    public static func chainesActives(_ contexte: ModelContext) throws -> [String] {
        let source = SourceGuide.xmltvfr.rawValue
        return try contexte.fetch(FetchDescriptor<Chaine>(predicate: #Predicate { $0.active && $0.sourceBrut == source }))
            .map(\.identifiantGuide)
            .sorted()
    }

    /// Une nouvelle lecture s'impose après l'intervalle, ou dès que les chaînes cochées ont changé.
    public static func doitActualiser(derniereLecture: Date?, chainesLues: [String]?, chainesActives: [String], maintenant: Date = .now) -> Bool {
        guard let derniereLecture, let chainesLues else { return true }
        return chainesLues != chainesActives || maintenant.timeIntervalSince(derniereLecture) >= intervalleLecture
    }

    /// Seules les diffusions rattachées à TMDB sont gardées : les autres n'apparaissent nulle part.
    @discardableResult
    public func actualiser(maintenant: Date = .now) async throws -> Rapport {
        let source = SourceGuide.xmltvfr.rawValue
        let toutes = try contexte.fetch(FetchDescriptor<Chaine>(predicate: #Predicate { $0.sourceBrut == source }))
        let identifiants = toutes.filter(\.active).map(\.identifiantGuide)
        // Les diffusions d'une chaîne décochée partent aussi.
        let connues = toutes.map(\.identifiantGuide)
        let anciennes = try contexte.fetch(FetchDescriptor<Diffusion>(predicate: #Predicate { connues.contains($0.chaine) }))
        guard !identifiants.isEmpty else {
            anciennes.forEach(contexte.delete)
            try contexte.save()
            return Rapport()
        }

        let guideDuJour = try await guide.programmes(chaines: Set(identifiants))
        let aVenir = guideDuJour.programmes.filter { $0.fin > maintenant }
        let rattaches = try await rattachement.rattacher(aVenir)
        // 8.2.11 : après les attentes réseau, un changement de personne a pu remplacer ce magasin — on n'y écrit plus.
        // Écrire dans l'ancien faisait planter SwiftData (rapport de l'iPhone du 27.09.2026).
        try Task.checkCancellation()

        anciennes.forEach(contexte.delete)
        var rapport = Rapport(programmesLus: aVenir.count, recherchesEnEchec: await rattachement.recherchesEnEchec)
        var nonRattaches = Set<String>()
        for r in rattaches {
            if r.programme.nature == .film {
                rapport.filmsLus += 1
                if r.candidat == nil { nonRattaches.insert(r.programme.titre) } else { rapport.filmsRattaches += 1 }
            }
            guard let candidat = r.candidat else { continue }
            contexte.insert(Diffusion(programme: r.programme, rattachement: candidat))
            rapport.diffusionsEnregistrees += 1
        }
        rapport.filmsNonRattaches = nonRattaches.sorted()
        try contexte.save()
        return rapport
    }
}

/// Réunit ce que le magasin sait d'un titre pour dire où le regarder (EF-73, EF-77).
@MainActor
public struct ServiceDisponibilite {
    public let contexte: ModelContext

    public init(contexte: ModelContext) {
        self.contexte = contexte
    }

    /// - Parameter offres: les offres TMDB du titre en Suisse, obtenues avec sa fiche.
    public func sources(_ reference: ReferenceTitre, offres: OffresRegion?, maintenant: Date = .now) throws -> SourcesTitre {
        let id = reference.tmdbID
        let type = reference.type.rawValue

        let fichiers = try contexte.fetch(FetchDescriptor<FichierNAS>(predicate: #Predicate { $0.tmdbID == id && $0.typeBrut == type }))
        let abonnements = try contexte.fetch(FetchDescriptor<Abonnement>(predicate: #Predicate { $0.actif }))
        let diffusions = try contexte.fetch(FetchDescriptor<Diffusion>(
            predicate: #Predicate { $0.tmdbID == id && $0.typeBrut == type && $0.fin > maintenant },
            sortBy: [SortDescriptor(\.debut)]
        ))
        let nomsDeChaines = Dictionary(
            try contexte.fetch(FetchDescriptor<Chaine>()).map { ($0.identifiantGuide, $0.nom) },
            uniquingKeysWith: { premier, _ in premier }
        )

        return SourcesTitre(
            nas: fichiers.map { CopieNAS(chemin: $0.chemin, qualite: $0.qualite.flatMap(QualiteVideo.init(description:))) },
            offres: offres,
            abonnements: Set(abonnements.map(\.providerID)),
            diffusions: diffusions.map { DiffusionPrevue(chaine: nomsDeChaines[$0.chaine] ?? ChaineGuide.nom($0.chaine) ?? $0.chaine, debut: $0.debut, fin: $0.fin) }
        )
    }

    public func etat(_ reference: ReferenceTitre, offres: OffresRegion?, maintenant: Date = .now) throws -> EtatDisponibilite {
        Disponibilite.etat(try sources(reference, offres: offres, maintenant: maintenant), maintenant: maintenant)
    }
}
