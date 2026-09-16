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
    }

    public let contexte: ModelContext
    public let guide: GuideTVClient
    public let rattachement: RattachementGuide

    public init(contexte: ModelContext, guide: GuideTVClient, rattachement: RattachementGuide) {
        self.contexte = contexte
        self.guide = guide
        self.rattachement = rattachement
    }

    /// Seules les diffusions rattachées à TMDB sont gardées : les autres n'apparaissent nulle part.
    @discardableResult
    public func actualiser(maintenant: Date = .now) async throws -> Rapport {
        let source = SourceGuide.xmltvfr.rawValue
        let chaines = try contexte.fetch(FetchDescriptor<Chaine>(predicate: #Predicate { $0.active && $0.sourceBrut == source }))
        let identifiants = chaines.map(\.identifiantGuide)
        guard !identifiants.isEmpty else { return Rapport() }

        let guideDuJour = try await guide.programmes(chaines: Set(identifiants))
        let aVenir = guideDuJour.programmes.filter { $0.fin > maintenant }
        let rattaches = try await rattachement.rattacher(aVenir)

        let anciennes = try contexte.fetch(FetchDescriptor<Diffusion>(predicate: #Predicate { identifiants.contains($0.chaine) }))
        anciennes.forEach(contexte.delete)
        var rapport = Rapport(programmesLus: aVenir.count, recherchesEnEchec: await rattachement.recherchesEnEchec)
        for r in rattaches {
            guard let candidat = r.candidat else { continue }
            contexte.insert(Diffusion(programme: r.programme, rattachement: candidat))
            rapport.diffusionsEnregistrees += 1
        }
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
            diffusions: diffusions.map { DiffusionPrevue(chaine: nomsDeChaines[$0.chaine] ?? $0.chaine, debut: $0.debut, fin: $0.fin) }
        )
    }

    public func etat(_ reference: ReferenceTitre, offres: OffresRegion?, maintenant: Date = .now) throws -> EtatDisponibilite {
        Disponibilite.etat(try sources(reference, offres: offres, maintenant: maintenant), maintenant: maintenant)
    }
}
