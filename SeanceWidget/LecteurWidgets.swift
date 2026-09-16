import Foundation
import SeanceDonnees
import SeanceKit
import SwiftData
import UIKit

/// Le magasin partagé avec l'app, ouvert une fois par processus du widget.
@MainActor
enum ConteneurPartage {
    static let conteneur: ModelContainer? = try? EntrepotSeance.conteneur(.groupeApp)
}

/// Lit ce que les widgets affichent : la soirée et les échéances dans SwiftData, les prochains
/// épisodes dans la liste préparée par l'app, croisée avec les épisodes cochés depuis.
@MainActor
enum LecteurWidgets {
    static func soiree(maintenant: Date = .now) async -> [TitreWidget] {
        guard let contexte = ConteneurPartage.conteneur?.mainContext else { return [] }
        let jour = ServiceSoiree.soiree(maintenant)
        let selections = (try? contexte.fetch(FetchDescriptor<SelectionSoir>(
            predicate: #Predicate { $0.soiree == jour }, sortBy: [SortDescriptor(\.ajouteLe)]
        ))) ?? []
        let prochains = Dictionary(episodes(contexte: contexte).map { ($0.serie.id, $0.episode) }, uniquingKeysWith: { premier, _ in premier })
        var titres = selections.map { selection in
            let detail: String
            if selection.reference.type == .serie {
                detail = prochains[selection.tmdbID].map { "\(NumeroEpisode(saison: $0.saison, episode: $0.numero)) à regarder" } ?? "Série"
            } else {
                detail = "Film"
            }
            return (TitreWidget(reference: selection.reference, titre: selection.titre, detail: detail), selection.cheminAffiche)
        }
        for index in titres.indices.prefix(5) {
            titres[index].0.affiche = await Vignettes.donnees(titres[index].1)
        }
        return titres.map(\.0)
    }

    static func prochainsEpisodes(limite: Int = 5) async -> [EpisodeWidget] {
        guard let contexte = ConteneurPartage.conteneur?.mainContext else { return [] }
        var resultat = episodes(contexte: contexte).prefix(limite).map { prochain in
            (EpisodeWidget(serieID: prochain.serie.id, nom: prochain.serie.nom, saison: prochain.episode.saison, numero: prochain.episode.numero,
                           titreEpisode: prochain.episode.titre, dureeMinutes: prochain.episode.dureeMinutes), prochain.serie.cheminAffiche)
        }
        for index in resultat.indices {
            resultat[index].0.affiche = await Vignettes.donnees(resultat[index].1)
        }
        return resultat.map(\.0)
    }

    static func aVenir(maintenant: Date = .now, limite: Int = 6) async -> [EcheanceWidget] {
        guard let contexte = ConteneurPartage.conteneur?.mainContext else { return [] }
        var resultat = futures((try? contexte.fetch(FetchDescriptor<Echeance>(sortBy: [SortDescriptor(\.date)]))) ?? [], maintenant: maintenant)
            .prefix(limite)
            .map { echeance in
                (EcheanceWidget(reference: echeance.reference, titre: echeance.titre, libelle: echeance.libelle, date: echeance.date,
                                nature: echeance.nature), echeance.cheminAffiche)
            }
        for index in resultat.indices {
            resultat[index].0.affiche = await Vignettes.donnees(resultat[index].1)
        }
        return resultat.map(\.0)
    }

    /// Ce qui reste à venir à un instant donné : la télé jusqu'à deux heures après son début, le reste jusqu'à la fin du jour.
    static func futures(_ echeances: [Echeance], maintenant: Date) -> [Echeance] {
        let debutJour = Calendar.current.startOfDay(for: maintenant)
        return echeances.filter { echeance in
            echeance.nature == .tele ? echeance.date > maintenant.addingTimeInterval(-2 * 3600) : echeance.date >= debutJour
        }
    }

    private static func episodes(contexte: ModelContext) -> [InstantaneWidgets.Prochain] {
        let instantane = EntrepotSeance.dossierPartage.flatMap { InstantaneWidgets.lire(dossier: $0) }
        return (try? ServiceSoiree(contexte: contexte).prochainsEpisodes(instantane)) ?? []
    }
}

/// Petites affiches gardées dans le conteneur partagé : une seule lecture réseau par image.
enum Vignettes {
    static func donnees(_ chemin: String?) async -> Data? {
        guard let chemin, !chemin.isEmpty, let dossier = EntrepotSeance.dossierPartage?.appending(path: "Vignettes") else { return nil }
        let fichier = dossier.appending(path: chemin.replacingOccurrences(of: "/", with: ""))
        if let donnees = try? Data(contentsOf: fichier) { return donnees }
        guard let url = URL(string: "https://image.tmdb.org/t/p/w154\(chemin)"),
              let (brutes, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: brutes)?.preparingThumbnail(of: CGSize(width: 120, height: 180)),
              let reduite = image.jpegData(compressionQuality: 0.8)
        else { return nil }
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        try? reduite.write(to: fichier, options: .atomic)
        return reduite
    }
}
