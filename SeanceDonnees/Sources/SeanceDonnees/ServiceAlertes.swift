import Foundation
import SeanceKit
import SwiftData

/// Calcule les alertes des titres surveillés (EF-17 à EF-20, EF-49, EF-81 à EF-85) : annonces de saison
/// ou de sortie, veille et jour des épisodes et des sorties, arrivées sur les plateformes et en location,
/// passages à la TV. Enregistre aussi les échéances de l'écran « À venir ».
/// L'app confie ensuite les notifications obtenues au centre de notifications d'iOS.
@MainActor
public struct ServiceAlertes {
    public let contexte: ModelContext

    public init(contexte: ModelContext) {
        self.contexte = contexte
    }

    /// La fiche TMDB d'un titre surveillé, lue en parallèle avant le calcul.
    private struct Fiche: Sendable {
        var reference: ReferenceTitre
        var film: FicheFilm?
        var serie: SerieDetail?
    }

    /// Titres surveillés : cloche active, quel que soit le statut, sauf les titres écartés.
    public func surveilles() throws -> [Suivi] {
        let exclu = StatutSuivi.exclu.rawValue
        return try contexte.fetch(FetchDescriptor<Suivi>(predicate: #Predicate { $0.alertesActives && $0.statutBrut != exclu }))
    }

    /// Les notifications à programmer. Les alertes déjà passées ne reviennent jamais ; les alertes
    /// futures sont recalculées à chaque appel, et la liste mémorisée est remplacée.
    public func calculer(
        source: any SourceAlertes, reglages: ReglagesAlertes, maintenant: Date = .now
    ) async throws -> [NotificationPrevue] {
        let suivis = try surveilles()
        let abonnements = Set(try contexte.fetch(FetchDescriptor<Abonnement>(predicate: #Predicate { $0.actif })).map(\.providerID))
        let fiches = await lire(suivis.map(\.reference), source: source)
        try Task.checkCancellation()
        let aujourdhui = DateTMDB(maintenant, fuseau: reglages.fuseau)

        var alertes: [AlertePrevue] = []
        var echeances: [(EcheancePrevue, String?)] = []
        for suivi in suivis {
            let reference = suivi.reference
            let diffusions = try ServiceDisponibilite(contexte: contexte).sources(reference, offres: nil, maintenant: maintenant).diffusions
            alertes += PlanificateurAlertes.diffusions(reference, titre: suivi.titre, diffusions: diffusions, maintenant: maintenant, reglages: reglages)
            echeances += diffusions
                .filter { $0.debut <= maintenant.addingTimeInterval(reglages.horizonTele) }
                .map { (EcheancePrevue(reference: reference, titre: suivi.titre, date: $0.debut,
                                       libelle: "Sur \($0.chaine) à \($0.debut.formatted(date: .omitted, time: .shortened))", nature: .tele),
                        suivi.cheminAffiche) }

            guard let fiche = fiches[reference] else { continue }
            let etat = try etatConnu(reference, maintenant: maintenant)
            let premiereFois = etat.annonce == nil

            if let film = fiche.film {
                let offres = film.fournisseurs?.offres()
                if !premiereFois {
                    alertes += PlanificateurAlertes.arriveesSurPlateformes(reference, titre: suivi.titre, avant: Set(etat.fournisseurs), apres: offres,
                                                                           abonnements: abonnements, maintenant: maintenant, reglages: reglages)
                    alertes += PlanificateurAlertes.arriveesEnLocation(reference, titre: suivi.titre, avant: Set(etat.locationAchat), apres: offres,
                                                                       maintenant: maintenant, reglages: reglages)
                }
                memoriser(offres, dans: etat)
                alertes += PlanificateurAlertes.sortiesFilm(reference, titre: suivi.titre, dates: film.datesDeSortie, dateMondiale: film.dateSortie,
                                                            maintenant: maintenant, reglages: reglages)
                let annonce = PlanificateurAlertes.annonceFilm(dates: film.datesDeSortie, dateMondiale: film.dateSortie, aujourdhui: aujourdhui)
                if let annonce {
                    alertes += PlanificateurAlertes.annonce(reference, titre: suivi.titre, avant: etat.annonce, apres: annonce.cle,
                                                            motif: .annonceSortie(date: annonce.date), maintenant: maintenant, reglages: reglages)
                }
                etat.annonce = annonce?.cle ?? PlanificateurAlertes.aucuneAnnonce
                echeances += sorties(film, reference: reference, titre: suivi.titre, aujourdhui: aujourdhui, reglages: reglages)
                    .map { ($0, suivi.cheminAffiche) }
            }

            if let serie = fiche.serie {
                // 6.1 : finie chez TMDB et vue jusqu'au bout, elle se range dans Terminés.
                try? ServiceSuivi(contexte: contexte).rangerSiTerminee(serie)
                let offres = serie.fournisseurs?.offres()
                if !premiereFois {
                    alertes += PlanificateurAlertes.arriveesSurPlateformes(reference, titre: suivi.titre, avant: Set(etat.fournisseurs), apres: offres,
                                                                           abonnements: abonnements, maintenant: maintenant, reglages: reglages)
                }
                memoriser(offres, dans: etat)
                alertes += PlanificateurAlertes.episodes(serie, mode: suivi.modeAlertes, maintenant: maintenant, reglages: reglages)
                let annonce = PlanificateurAlertes.annonceSerie(serie)
                if let annonce {
                    alertes += PlanificateurAlertes.annonce(reference, titre: suivi.titre, avant: etat.annonce, apres: annonce.cle,
                                                            motif: .annonceSaison(saison: annonce.saison, date: annonce.date),
                                                            maintenant: maintenant, reglages: reglages)
                }
                etat.annonce = annonce?.cle ?? PlanificateurAlertes.aucuneAnnonce
                if let prochain = serie.prochainEpisode, let jour = prochain.dateDiffusion, jour >= aujourdhui {
                    echeances.append((EcheancePrevue(
                        reference: reference, titre: suivi.titre, date: jour.instant(heure: 0, fuseau: reglages.fuseau),
                        libelle: prochain.numero == 1 ? "Saison \(prochain.saison)" : "Épisode \(prochain.numeroEpisode)",
                        nature: prochain.numero == 1 ? .saison : .episode
                    ), suivi.cheminAffiche))
                }
            }
            etat.verifieLe = maintenant
        }

        alertes += await nouveauxFilmsDesActeursSuivis(source: source, reglages: reglages, maintenant: maintenant)

        // Alertes datées : recalculées à chaque passage. Alertes ponctuelles : gardées jusqu'à leur envoi.
        let passees = try contexte.fetch(FetchDescriptor<AlertePlanifiee>(predicate: #Predicate { $0.date <= maintenant }))
        let enAttente = try contexte.fetch(FetchDescriptor<AlertePlanifiee>(predicate: #Predicate { $0.date > maintenant && $0.ponctuelle }))
        let envoyees = Set(passees.map(\.motif))
        let dejaProgrammees = envoyees.union(enAttente.map(\.motif))

        let datees = PlanificateurAlertes.notifications(alertes.filter { !$0.motif.ponctuelle }, dejaEnvoyees: envoyees, reglages: reglages)
        // Fiche par fiche, et non « en bloc » (8.2.16) : une suppression en bloc laissait aux listes affichées (la cloche,
        // les échéances) des fiches disparues, et SwiftData s'arrêtait net en les prévenant — au changement de personne
        // surtout, puisque ces tables sont dans le cache commun à la famille (rapports de l'iPhone du 27.09.2026).
        for ancienne in try contexte.fetch(FetchDescriptor<AlertePlanifiee>(predicate: #Predicate { $0.date > maintenant && !$0.ponctuelle })) {
            contexte.delete(ancienne)
        }
        for notification in datees {
            for alerte in notification.alertes {
                contexte.insert(AlertePlanifiee(reference: alerte.reference, motif: alerte.cle, date: alerte.date))
            }
        }
        var ponctuelles = enAttente
        for alerte in alertes where alerte.motif.ponctuelle && !dejaProgrammees.contains(alerte.cle) {
            let planifiee = AlertePlanifiee(reference: alerte.reference, motif: alerte.cle, date: alerte.date)
            planifiee.ponctuelle = true
            planifiee.titre = alerte.titre
            planifiee.corps = PlanificateurAlertes.texte(alerte.motif, fuseau: reglages.fuseau)
            contexte.insert(planifiee)
            ponctuelles.append(planifiee)
        }
        let notifications = (datees + ponctuelles.map { alerte in
            NotificationPrevue(date: alerte.date, titre: alerte.titre, corps: alerte.corps, alertes: [], identifiant: alerte.motif,
                               reference: ReferenceTitre(type: TypeTitre(rawValue: alerte.typeBrut) ?? .film, tmdbID: alerte.tmdbID))
        }).sorted { $0.date < $1.date }

        // 8.2.11 : après les attentes réseau, un changement de personne a pu remplacer ce magasin — on n'y écrit plus.
        // Écrire dans l'ancien faisait planter SwiftData (rapport de l'iPhone du 27.09.2026).
        try Task.checkCancellation()
        for ancienne in try contexte.fetch(FetchDescriptor<Echeance>()) {
            contexte.delete(ancienne)
        }
        for (echeance, affiche) in echeances {
            contexte.insert(Echeance(echeance, cheminAffiche: affiche))
        }
        try contexte.save()
        return notifications
    }

    /// « Suivre un acteur » : sa filmographie est relue, et chaque film apparu depuis la dernière fois est signalé.
    /// Un acteur dont TMDB ne répond pas est simplement revu au passage suivant.
    private func nouveauxFilmsDesActeursSuivis(source: any SourceAlertes, reglages: ReglagesAlertes, maintenant: Date) async -> [AlertePrevue] {
        guard let acteurs = try? contexte.fetch(FetchDescriptor<ActeurSuivi>()), !acteurs.isEmpty else { return [] }
        let ids = acteurs.map(\.personneID)
        let filmographies = await withTaskGroup(of: (Int, Filmographie?).self) { groupe in
            for id in ids {
                groupe.addTask { (id, try? await source.filmographie(personne: id)) }
            }
            var resultat: [Int: Filmographie] = [:]
            for await (id, filmographie) in groupe {
                if let filmographie { resultat[id] = filmographie }
            }
            return resultat
        }
        // Après l'attente réseau, le magasin a pu être remplacé (changement de personne, 8.2.11) : on s'arrête là.
        guard !Task.isCancelled else { return [] }
        var alertes: [AlertePrevue] = []
        for acteur in acteurs {
            guard let filmographie = filmographies[acteur.personneID] else { continue }
            let (nouvelles, connus) = PlanificateurAlertes.nouveauxFilms(
                acteur: acteur.nom, connus: acteur.verifieLe == nil ? nil : Set(acteur.filmsConnus),
                filmographie: filmographie, maintenant: maintenant, reglages: reglages
            )
            alertes += nouvelles
            acteur.filmsConnus = connus.sorted()
            acteur.verifieLe = maintenant
        }
        return alertes
    }

    /// Ce que Séance savait déjà du titre ; créé vide à la première vérification.
    private func etatConnu(_ reference: ReferenceTitre, maintenant: Date) throws -> EtatPlateformes {
        let id = reference.tmdbID
        let type = reference.type.rawValue
        if let etat = try contexte.fetch(FetchDescriptor<EtatPlateformes>(predicate: #Predicate { $0.tmdbID == id && $0.typeBrut == type })).first {
            return etat
        }
        let etat = EtatPlateformes(reference: reference, fournisseurs: [], verifieLe: maintenant)
        contexte.insert(etat)
        return etat
    }

    private func memoriser(_ offres: OffresRegion?, dans etat: EtatPlateformes) {
        guard let offres else { return }
        etat.fournisseurs = Array(Set((offres.abonnement + offres.gratuit + offres.avecPublicite).map(\.id))).sorted()
        etat.locationAchat = Array(Set((offres.location + offres.achat).map(\.id))).sorted()
    }

    /// Prochaines sorties d'un film : salle et numérique là où elles sont connues, sinon sortie mondiale.
    private func sorties(_ film: FicheFilm, reference: ReferenceTitre, titre: String, aujourdhui: DateTMDB,
                         reglages: ReglagesAlertes) -> [EcheancePrevue] {
        var jours: [(String, DateTMDB)] = []
        if let (salles, numerique) = PlanificateurAlertes.joursDeSortie(film.datesDeSortie) {
            if let salles { jours.append(("Au cinéma", salles)) }
            if let numerique { jours.append(("En numérique", numerique)) }
        } else if let mondiale = film.dateSortie {
            jours.append(("Sortie", mondiale))
        }
        return jours.filter { $0.1 >= aujourdhui }.map { libelle, jour in
            EcheancePrevue(reference: reference, titre: titre, date: jour.instant(heure: 0, fuseau: reglages.fuseau), libelle: libelle, nature: .sortie)
        }
    }

    /// Six titres à la fois ; un titre dont TMDB ne répond pas est simplement ignoré cette fois.
    private func lire(_ references: [ReferenceTitre], source: any SourceAlertes) async -> [ReferenceTitre: Fiche] {
        await withTaskGroup(of: Fiche.self) { groupe in
            var reste = references[...]
            func lancer(_ reference: ReferenceTitre) {
                groupe.addTask {
                    var fiche = Fiche(reference: reference)
                    switch reference.type {
                    case .film: fiche.film = try? await source.film(reference.tmdbID, complements: [.datesDeSortie, .fournisseurs])
                    case .serie: fiche.serie = try? await source.serie(reference.tmdbID, complements: [.fournisseurs])
                    }
                    return fiche
                }
            }
            for _ in 0..<6 {
                guard let reference = reste.popFirst() else { break }
                lancer(reference)
            }
            var resultat: [ReferenceTitre: Fiche] = [:]
            while let fiche = await groupe.next() {
                if fiche.film != nil || fiche.serie != nil { resultat[fiche.reference] = fiche }
                if let suivante = reste.popFirst() { lancer(suivante) }
            }
            return resultat
        }
    }
}
