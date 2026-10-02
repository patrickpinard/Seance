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
        /// Chaque film ou épisode présent en plusieurs copies : la copie gardée et les autres.
        public var copiesEnDouble: [DoublonNAS] = []
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
        explorateur: any ExplorateurFichiers, recherche: any RechercheTMDB, dossiers: [String], maintenant: Date = .now,
        identifications: IdentificationsTMDB = .lues()
    ) async throws -> Rapport {
        let fichiers = try await explorateur.listerVideos(dossiers: dossiers)
        let index = IndexNAS.construire(fichiers)
        let rattachement = RattachementNAS(recherche: recherche, identifications: identifications)
        let rattachees = try await rattachement.rattacher(index.entrees)

        // Ce qui ne tient pas dans le magasin (6.4) : la date du fichier sur le NAS et les genres du titre, gardés
        // à côté pour ranger la bibliothèque par ajouts et par genre.
        var details = DetailsNAS()
        var rapport = Rapport(
            videosLues: fichiers.count, videosRetenues: index.entrees.count, doublons: index.doublons, copiesEnDouble: index.copiesEnDouble,
            recherchesEnEchec: await rattachement.recherchesEnEchec
        )
        for fichier in fichiers {
            let dossier = (fichier.chemin.split(separator: "/").first.map(String.init) ?? "").precomposedStringWithCanonicalMapping
            rapport.videosParDossier[dossier, default: 0] += 1
        }
        rapport.filmsReconnus = Set(rattachees.filter { $0.entree.analyse.type == .film }.compactMap { $0.titre?.reference }).count
        rapport.seriesReconnues = Set(rattachees.filter { $0.entree.analyse.type == .serie }.compactMap { $0.titre?.reference }).count
        // 8.2.11 : après les attentes réseau, un changement de personne a pu remplacer ce magasin — on n'y écrit plus.
        // Écrire dans l'ancien faisait planter SwiftData (rapport de l'iPhone du 27.09.2026).
        try Task.checkCancellation()
        // 8.9 (bilan de l'Apple TV) : la bibliothèque se met à jour au lieu d'être effacée puis recréée — chaque passage
        // faisait relire et recalculer toutes les pages qui montrent le NAS. Une vidéo connue garde sa fiche (et sa date
        // d'arrivée), une nouvelle s'ajoute, une disparue s'en va ; rien n'est écrit si rien n'a changé.
        var connus: [String: FichierNAS] = [:]
        for fichier in try contexte.fetch(FetchDescriptor<FichierNAS>()) {
            if connus[fichier.chemin] == nil { connus[fichier.chemin] = fichier } else { contexte.delete(fichier) }
        }
        func fiche(_ chemin: String, type: TypeTitre, tmdbID: Int?, qualite: String?, taille: Int64) -> FichierNAS {
            if let connu = connus.removeValue(forKey: chemin) {
                connu.poser(\.typeBrut, type.rawValue)
                connu.poser(\.tmdbID, tmdbID)
                connu.poser(\.qualite, qualite)
                connu.poser(\.tailleOctets, taille)
                return connu
            }
            let nouveau = FichierNAS(chemin: chemin, type: type, tmdbID: tmdbID, qualite: qualite, tailleOctets: taille)
            nouveau.indexeLe = maintenant
            contexte.insert(nouveau)
            return nouveau
        }

        for r in rattachees {
            let analyse = r.entree.analyse
            // Le type du titre choisi à la main l'emporte (8.4) : un nom lu comme un film peut être une série.
            let fichier = fiche(r.entree.fichier.chemin, type: r.titre?.reference.type ?? analyse.type, tmdbID: r.titre?.reference.tmdbID,
                                qualite: analyse.qualite?.description, taille: r.entree.fichier.taille)
            if let date = r.entree.fichier.modifieLe { details.ajouts[r.entree.fichier.chemin] = date }
            fichier.poser(\.saison, analyse.episode?.saison)
            fichier.poser(\.episode, analyse.episode?.episode)
            if let titre = r.titre {
                if !titre.genres.isEmpty { details.genres[titre.reference.tmdbID] = titre.genres }
                fichier.recopier(titre, anneeLue: analyse.annee)
                rapport.reconnues += 1
            } else {
                fichier.poser(\.titre, analyse.titre)
                fichier.poser(\.annee, analyse.annee)
                fichier.poser(\.cheminAffiche, nil)
                fichier.poser(\.cheminFond, nil)
                rapport.nonReconnues.append(r.entree.fichier.chemin)
            }
        }
        for illisible in index.illisibles {
            // Un nom illisible reconnu à la main (8.4) se retient par son chemin.
            let choisi = identifications.titreNAS(chemin: illisible.chemin)
            let fichier = fiche(illisible.chemin, type: choisi?.reference.type ?? .film, tmdbID: choisi?.reference.tmdbID,
                                qualite: nil, taille: illisible.taille)
            if let date = illisible.modifieLe { details.ajouts[illisible.chemin] = date }
            if let choisi {
                if !choisi.genres.isEmpty { details.genres[choisi.reference.tmdbID] = choisi.genres }
                fichier.recopier(choisi, anneeLue: nil)
                rapport.reconnues += 1
            } else {
                rapport.nonReconnues.append(illisible.chemin)
            }
        }
        // Ce qui n'est plus sur le NAS, fiche par fiche (8.2.16) : en bloc, les listes affichées gardaient des fiches
        // disparues et SwiftData s'arrêtait.
        for disparu in connus.values { contexte.delete(disparu) }
        rapport.nonReconnues.sort()
        if contexte.hasChanges { try contexte.save() }
        if let donnees = try? details.encoder() {
            UserDefaults.standard.set(donnees, forKey: DetailsNAS.cle)
        }
        return rapport
    }

    /// Le titre choisi à la main pour une vidéo du NAS (8.4), parmi ce que TMDB propose : retenu pour l'œuvre (tous les
    /// épisodes d'une série, toutes ses copies) et appliqué tout de suite à la bibliothèque, sans relire le NAS.
    /// Sans titre : revient à ce que Séance reconnaît seule, à la prochaine analyse.
    /// Renvoie le nombre de vidéos concernées.
    @discardableResult
    public func identifier(chemin: String, titre: TitreResume?, defauts: UserDefaults = .standard, maintenant: Date = .now) throws -> Int {
        var identifications = IdentificationsTMDB.lues(defauts)
        let cle = IdentificationsTMDB.cleNAS(chemin: chemin)
        guard let titre else {
            identifications.oublier(cle, le: maintenant)
            identifications.enregistrer(defauts)
            return try oublier(cle)
        }
        identifications.choisir(titre, pour: cle, nom: chemin, le: maintenant)
        identifications.enregistrer(defauts)
        return try appliquer(identifications, defauts: defauts)
    }

    /// Les vidéos de cette œuvre redeviennent non reconnues, avec le titre lu dans leur nom ; la prochaine analyse les
    /// cherche de nouveau dans TMDB.
    private func oublier(_ cle: String) throws -> Int {
        var modifies = 0
        for fichier in try contexte.fetch(FetchDescriptor<FichierNAS>()) where IdentificationsTMDB.cleNAS(chemin: fichier.chemin) == cle {
            let analyse = AnalyseNomFichier.analyser(chemin: "/" + fichier.chemin)
            fichier.tmdbID = nil
            fichier.typeBrut = (analyse?.type ?? .film).rawValue
            fichier.titre = analyse?.titre ?? (fichier.chemin as NSString).lastPathComponent
            fichier.annee = analyse?.annee
            fichier.cheminAffiche = nil
            fichier.cheminFond = nil
            fichier.noteMoyenne = 0
            fichier.nombreVotes = 0
            modifies += 1
        }
        if modifies > 0 { try contexte.save() }
        return modifies
    }

    /// Pose les titres choisis à la main sur les vidéos déjà connues (au choix, ou reçus d'un autre appareil).
    /// Renvoie le nombre de vidéos modifiées.
    @discardableResult
    public func appliquer(_ identifications: IdentificationsTMDB, defauts: UserDefaults = .standard) throws -> Int {
        var details = defauts.data(forKey: DetailsNAS.cle).flatMap(DetailsNAS.decoder) ?? DetailsNAS()
        var modifies = 0
        for fichier in try contexte.fetch(FetchDescriptor<FichierNAS>()) {
            guard let choisi = identifications.titreNAS(chemin: fichier.chemin), fichier.reference != choisi.reference else { continue }
            let analyse = AnalyseNomFichier.analyser(chemin: "/" + fichier.chemin)
            fichier.typeBrut = choisi.reference.type.rawValue
            fichier.tmdbID = choisi.reference.tmdbID
            fichier.recopier(choisi, anneeLue: analyse?.annee)
            if !choisi.genres.isEmpty { details.genres[choisi.reference.tmdbID] = choisi.genres }
            modifies += 1
        }
        guard modifies > 0 else { return 0 }
        try contexte.save()
        if let donnees = try? details.encoder() { defauts.set(donnees, forKey: DetailsNAS.cle) }
        return modifies
    }
}

extension FichierNAS {
    /// Ce que la bibliothèque garde du titre TMDB d'une vidéo.
    func recopier(_ titre: TitreResume, anneeLue: Int?) {
        poser(\.titre, titre.titre)
        poser(\.annee, titre.date?.annee ?? anneeLue)
        poser(\.cheminAffiche, titre.cheminAffiche)
        poser(\.cheminFond, titre.cheminFond)
        poser(\.noteMoyenne, titre.noteMoyenne)
        poser(\.nombreVotes, titre.nombreVotes)
    }

    /// Change une valeur seulement si elle diffère : une fiche inchangée ne se marque pas modifiée (8.9).
    func poser<Valeur: Equatable>(_ chemin: ReferenceWritableKeyPath<FichierNAS, Valeur>, _ valeur: Valeur) {
        if self[keyPath: chemin] != valeur { self[keyPath: chemin] = valeur }
    }
}
