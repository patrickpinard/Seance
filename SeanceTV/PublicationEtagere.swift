import SeanceDonnees
import SeanceKit
import SwiftData
import TVServices

/// Prépare l'étagère du haut à partir du magasin, et prévient tvOS quand elle a changé.
@MainActor
enum PublicationEtagere {
    static func publier(contexte: ModelContext) {
        let ceSoir = ServiceSoiree.soiree()
        let soiree = ((try? contexte.fetch(FetchDescriptor<SelectionSoir>(sortBy: [SortDescriptor(\.ajouteLe)]))) ?? []).filter { $0.soiree == ceSoir }
        let fichiers = (try? contexte.fetch(FetchDescriptor<FichierNAS>(sortBy: [SortDescriptor(\.indexeLe, order: .reverse)]))) ?? []
        let nouveautes = OeuvreTV.regrouper(fichiers).prefix(12)
        let etagere = EtagereDuHaut(sections: [
            .init(titre: "Ce soir", titres: soiree.map { titre($0.reference, $0.titre, $0.cheminAffiche) }),
            .init(titre: "Nouveaux sur ton NAS", titres: nouveautes.map { titre($0.reference, $0.titre, $0.cheminAffiche) }),
        ])
        if etagere.ecrire() { TVTopShelfContentProvider.topShelfContentDidChange() }
    }

    private static func titre(_ reference: ReferenceTitre, _ titre: String, _ cheminAffiche: String?) -> EtagereDuHaut.Titre {
        .init(titre: titre, affiche: ImageTMDB.url(cheminAffiche, .afficheGrande)?.absoluteString,
              lien: "seance://\(reference.type.rawValue)/\(reference.tmdbID)")
    }
}
