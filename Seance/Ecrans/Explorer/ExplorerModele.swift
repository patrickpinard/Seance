import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Résultats d'Explorer par critères (EF-53 à EF-59) : pages TMDB chargées au fil du défilement,
/// puis filtrées par l'app pour le NAS, la télé et le déjà-vu.
@MainActor
@Observable
final class ExplorerModele {
    /// À l'ouverture : en français ou en anglais, sur les plateformes cochées (puces retirables).
    var filtres = FiltresExplorer.parDefaut(avecPlateformes: true)
    private(set) var resultats: [TitreResume] = []
    /// Nombre annoncé par TMDB, avant les filtres de l'app.
    private(set) var total: Int?
    private(set) var enCours = false
    private(set) var termine = false
    private(set) var erreur: String?
    /// Erreur d'origine, pour le journal.
    private(set) var erreurDetaillee: (any Error)?

    private var page = 0
    private var nombrePages = 1
    /// Change à chaque nouveau jeu de filtres : une réponse en retard ne remplace pas la plus récente.
    private var generation = 0
    /// Les filtres de l'app peuvent vider une page entière : au plus ce nombre de pages par chargement.
    private static let pagesParChargement = 5
    /// Fiches déjà lues pour les listes locales (NAS, télé, vus) : changer un filtre ne relit rien.
    private var profils: [ReferenceTitre: ProfilTitre] = [:]

    func recharger(client: TMDBClient, contexte: ModelContext, abonnements: [Int]) async {
        generation += 1
        resultats = []
        total = nil
        page = 0
        nombrePages = 1
        termine = false
        erreur = nil
        // Un chargement des anciens filtres a pu rester en cours : il sera ignoré à son retour.
        enCours = false
        await chargerSuite(client: client, contexte: contexte, abonnements: abonnements)
    }

    func chargerSuite(client: TMDBClient, contexte: ModelContext, abonnements: [Int]) async {
        guard !enCours, !termine else { return }
        let generationDemandee = generation
        let filtresDemandes = filtres
        enCours = true
        defer { if generation == generationDemandee { enCours = false } }

        do {
            if filtresDemandes.partDUneListeLocale {
                let titres = try await titresLocaux(filtresDemandes, client: client, contexte: contexte, abonnements: abonnements)
                guard generation == generationDemandee else { return }
                resultats = titres
                total = titres.count
                termine = true
                return
            }
            if filtresDemandes.personnesParFilmographie {
                let titres = try await seriesParFilmographie(filtresDemandes, client: client)
                guard generation == generationDemandee else { return }
                total = titres.count
                resultats = retenir(titres, filtres: filtresDemandes, contexte: contexte)
                termine = true
                return
            }

            var ajoutes: [TitreResume] = []
            var pagesLues = 0
            while page < nombrePages, pagesLues < Self.pagesParChargement, ajoutes.count < 12 {
                let criteres = filtresDemandes.criteres(abonnements: abonnements, page: page + 1)
                let titres: [TitreResume]
                switch filtresDemandes.type {
                case .film:
                    let reponse = try await client.decouvrirFilms(criteres)
                    nombrePages = min(reponse.nombrePages, 500)
                    total = reponse.nombreResultats
                    titres = reponse.resultats.map(\.titreResume)
                case .serie:
                    let reponse = try await client.decouvrirSeries(criteres)
                    nombrePages = min(reponse.nombrePages, 500)
                    total = reponse.nombreResultats
                    titres = reponse.resultats.map(\.titreResume)
                }
                guard generation == generationDemandee else { return }
                page += 1
                pagesLues += 1
                let dejaLa = Set(resultats.map(\.reference) + ajoutes.map(\.reference))
                ajoutes += retenir(titres, filtres: filtresDemandes, contexte: contexte).filter { !dejaLa.contains($0.reference) }
                if !filtresDemandes.filtresAppActifs { break }
            }
            resultats += ajoutes
            termine = page >= nombrePages
        } catch is CancellationError {
            return
        } catch {
            guard generation == generationDemandee else { return }
            erreur = Journal.conseil(error) ?? "Les résultats n'ont pas pu être chargés."
            erreurDetaillee = error
            termine = true
        }
    }

    /// Nombre de résultats pour un réglage en cours (EF-55) : exact pour une liste locale, annoncé par
    /// TMDB sinon (plafonné à 20 001).
    func compter(_ filtres: FiltresExplorer, client: TMDBClient, contexte: ModelContext, abonnements: [Int]) async -> Int? {
        if filtres.partDUneListeLocale {
            return try? await titresLocaux(filtres, client: client, contexte: contexte, abonnements: abonnements).count
        }
        if filtres.personnesParFilmographie {
            return try? await seriesParFilmographie(filtres, client: client).count
        }
        let criteres = filtres.criteres(abonnements: abonnements)
        switch filtres.type {
        case .film: return try? await client.decouvrirFilms(criteres).nombreResultats
        case .serie: return try? await client.decouvrirSeries(criteres).nombreResultats
        }
    }

    /// Titres du NAS, des programmes TV ou de l'historique, filtrés sur leur fiche TMDB.
    private func titresLocaux(_ filtres: FiltresExplorer, client: TMDBClient, contexte: ModelContext, abonnements: [Int]) async throws -> [TitreResume] {
        let references = try referencesLocales(filtres, contexte: contexte)
        try await chargerProfils(references.filter { profils[$0] == nil }, client: client)
        let titres = references.compactMap { profils[$0] }
            .filter { filtres.retient($0, abonnements: abonnements) }
            .map(\.resume)
        return retenir(filtres.trier(titres), filtres: filtres, contexte: contexte)
    }

    /// Point de départ local : l'intersection des listes demandées, pour le type choisi.
    private func referencesLocales(_ filtres: FiltresExplorer, contexte: ModelContext) throws -> [ReferenceTitre] {
        let type = filtres.type.rawValue
        var ensembles: [Set<ReferenceTitre>] = []
        if filtres.locaux.obtention == .surNAS {
            let fichiers = try contexte.fetch(FetchDescriptor<FichierNAS>(predicate: #Predicate { $0.tmdbID != nil && $0.typeBrut == type }))
            ensembles.append(Set(fichiers.compactMap(\.reference)))
        }
        if filtres.locaux.tele != .indifferent {
            let maintenant = Date.now
            let diffusions = try contexte.fetch(FetchDescriptor<Diffusion>(predicate: #Predicate { $0.typeBrut == type && $0.fin > maintenant }))
            ensembles.append(Set(diffusions.compactMap { d in d.tmdbID.map { ReferenceTitre(type: filtres.type, tmdbID: $0) } }))
        }
        if filtres.locaux.dejaVu == .vus {
            let vus = try contexte.fetch(FetchDescriptor<Visionnage>(predicate: #Predicate { $0.typeBrut == type }))
            ensembles.append(Set(vus.map { ReferenceTitre(type: filtres.type, tmdbID: $0.tmdbID) }))
        }
        guard var resultat = ensembles.first else { return [] }
        for autre in ensembles.dropFirst() { resultat.formIntersection(autre) }
        return Array(resultat)
    }

    /// Lit les fiches manquantes, six à la fois ; une fiche introuvable est simplement écartée.
    private func chargerProfils(_ references: [ReferenceTitre], client: TMDBClient) async throws {
        try await withThrowingTaskGroup(of: ProfilTitre?.self) { groupe in
            var reste = references[...]
            func lancer(_ reference: ReferenceTitre) {
                groupe.addTask {
                    switch reference.type {
                    case .film:
                        let fiche = try? await client.film(reference.tmdbID, complements: [.casting, .datesDeSortie, .fournisseurs, .motsCles])
                        return fiche.map { ProfilTitre(film: $0) }
                    case .serie:
                        let fiche = try? await client.serie(reference.tmdbID, complements: [.casting, .fournisseurs, .motsCles])
                        return fiche.map { ProfilTitre(serie: $0) }
                    }
                }
            }
            for _ in 0..<6 {
                guard let reference = reste.popFirst() else { break }
                lancer(reference)
            }
            while let profil = try await groupe.next() {
                if let profil { profils[profil.resume.reference] = profil }
                if let suivante = reste.popFirst() { lancer(suivante) }
            }
        }
    }

    /// Séries où jouent les personnes choisies, toutes ensemble ou au moins une (EF-59).
    private func seriesParFilmographie(_ filtres: FiltresExplorer, client: TMDBClient) async throws -> [TitreResume] {
        var parPersonne: [[CreditPersonne]] = []
        for personne in filtres.personnes {
            parPersonne.append(try await client.filmographie(personne: personne.id).roles.filter(filtres.retient))
        }
        guard var retenus = parPersonne.first else { return [] }
        for autres in parPersonne.dropFirst() {
            let ids = Set(autres.map(\.tmdbID))
            if filtres.personnesEnsemble {
                retenus = retenus.filter { ids.contains($0.tmdbID) }
            } else {
                let connus = Set(retenus.map(\.tmdbID))
                retenus += autres.filter { !connus.contains($0.tmdbID) }
            }
        }
        return filtres.trier(retenus.map(\.titreResume))
    }

    /// Applique les critères que TMDB ignore, avec ce que l'iPhone sait : NAS, télé, historique.
    private func retenir(_ titres: [TitreResume], filtres: FiltresExplorer, contexte: ModelContext) -> [TitreResume] {
        let locaux = filtres.locaux
        guard locaux.obtention != .tous || locaux.tele != .indifferent || locaux.dejaVu != .tous || locaux.regleLangue else {
            return titres
        }
        let suivi = ServiceSuivi(contexte: contexte)
        let disponibilite = ServiceDisponibilite(contexte: contexte)
        let maintenant = Date.now
        return titres.filter { titre in
            guard let sources = try? disponibilite.sources(titre.reference, offres: nil, maintenant: maintenant) else { return false }
            var etat = Disponibilite.etat(sources, maintenant: maintenant)
            // Les offres ne sont pas chargées pour chaque résultat : « sur mes plateformes » les garantit.
            if filtres.mesPlateformes, sources.nas.isEmpty {
                etat = .dansAbonnements([])
            }
            let contexteResultat = ContexteResultat(
                reference: titre.reference, langueOriginale: titre.langueOriginale,
                estVu: (try? suivi.estVu(titre.reference)) ?? false,
                disponibilite: etat, diffusions: sources.diffusions
            )
            return locaux.retient(contexteResultat, maintenant: maintenant)
        }
    }
}
