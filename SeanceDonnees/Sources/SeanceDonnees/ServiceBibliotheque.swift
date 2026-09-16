import Foundation
import SeanceKit
import SwiftData

/// Analyse le NAS et remplace la bibliothèque du magasin (EF-72, EF-79). Le client SMB vit dans
/// SeanceNAS ; ce service ne voit qu'un `ExplorateurFichiers`, ce qui le rend testable sur le Mac.
@MainActor
public struct ServiceBibliotheque {
    public struct Rapport: Equatable, Sendable {
        public var videosLues = 0
        public var videosRetenues = 0
        public var doublons = 0
        public var reconnues = 0
        public var recherchesEnEchec = 0
        /// Chemins des vidéos gardées sans titre TMDB, ou dont le nom n'a pas pu être lu.
        public var nonReconnues: [String] = []
        /// Vidéos lues dans chaque dossier déclaré : montre d'un coup d'œil qu'un dossier a bien été parcouru.
        public var videosParDossier: [String: Int] = [:]
        public var seriesReconnues = 0
        public var filmsReconnus = 0
    }

    public let contexte: ModelContext

    public init(contexte: ModelContext) {
        self.contexte = contexte
    }

    /// La bibliothèque n'est remplacée qu'une fois la lecture et le rattachement réussis : un NAS
    /// injoignable ne vide pas ce que Séance connaît déjà.
    @discardableResult
    public func actualiser(
        explorateur: any ExplorateurFichiers, recherche: any RechercheTMDB, dossiers: [String], maintenant: Date = .now
    ) async throws -> Rapport {
        let fichiers = try await explorateur.listerVideos(dossiers: dossiers)
        let index = IndexNAS.construire(fichiers)
        let rattachement = RattachementNAS(recherche: recherche)
        let rattachees = try await rattachement.rattacher(index.entrees)

        var rapport = Rapport(
            videosLues: fichiers.count, videosRetenues: index.entrees.count, doublons: index.doublons,
            recherchesEnEchec: await rattachement.recherchesEnEchec
        )
        for fichier in fichiers {
            let dossier = (fichier.chemin.split(separator: "/").first.map(String.init) ?? "").precomposedStringWithCanonicalMapping
            rapport.videosParDossier[dossier, default: 0] += 1
        }
        rapport.filmsReconnus = Set(rattachees.filter { $0.entree.analyse.type == .film }.compactMap { $0.titre?.reference }).count
        rapport.seriesReconnues = Set(rattachees.filter { $0.entree.analyse.type == .serie }.compactMap { $0.titre?.reference }).count
        try contexte.delete(model: FichierNAS.self)

        for r in rattachees {
            let analyse = r.entree.analyse
            let fichier = FichierNAS(
                chemin: r.entree.fichier.chemin, type: analyse.type, tmdbID: r.titre?.reference.tmdbID,
                qualite: analyse.qualite?.description, tailleOctets: r.entree.fichier.taille
            )
            fichier.indexeLe = maintenant
            fichier.saison = analyse.episode?.saison
            fichier.episode = analyse.episode?.episode
            if let titre = r.titre {
                fichier.titre = titre.titre
                fichier.annee = titre.date?.annee ?? analyse.annee
                fichier.cheminAffiche = titre.cheminAffiche
                fichier.cheminFond = titre.cheminFond
                fichier.noteMoyenne = titre.noteMoyenne
                fichier.nombreVotes = titre.nombreVotes
                rapport.reconnues += 1
            } else {
                fichier.titre = analyse.titre
                fichier.annee = analyse.annee
                rapport.nonReconnues.append(r.entree.fichier.chemin)
            }
            contexte.insert(fichier)
        }
        for illisible in index.illisibles {
            let fichier = FichierNAS(chemin: illisible.chemin, type: .film, tailleOctets: illisible.taille)
            fichier.indexeLe = maintenant
            contexte.insert(fichier)
            rapport.nonReconnues.append(illisible.chemin)
        }
        rapport.nonReconnues.sort()
        try contexte.save()
        return rapport
    }
}
