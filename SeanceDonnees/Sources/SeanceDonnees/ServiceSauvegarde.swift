import Foundation
import SeanceKit
import SwiftData

/// Export et import de la sauvegarde JSON (EF-70). L'import ajoute sans écraser ni supprimer.
@MainActor
public struct ServiceSauvegarde {
    public let contexte: ModelContext

    public init(contexte: ModelContext) {
        self.contexte = contexte
    }

    public func exporter(le date: Date = .now) throws -> Sauvegarde {
        var s = Sauvegarde(creeeLe: date)
        s.suivis = try contexte.fetch(FetchDescriptor<Suivi>(sortBy: [SortDescriptor(\.ajouteLe)])).map {
            Sauvegarde.Suivi(reference: $0.reference, statut: $0.statutBrut, note: $0.note, exclusionLangue: $0.exclusionLangue,
                             ajouteLe: $0.ajouteLe, titre: $0.titre, cheminAffiche: $0.cheminAffiche,
                             acteursPrincipaux: $0.acteursPrincipaux, genres: $0.genres,
                             alertesActives: $0.alertesActives, modeAlertes: $0.modeAlertesBrut)
        }
        s.visionnages = try contexte.fetch(FetchDescriptor<Visionnage>(sortBy: [SortDescriptor(\.vuLe)])).map { v in
            let episode = v.saison.flatMap { saison in v.episode.map { NumeroEpisode(saison: saison, episode: $0) } }
            return Sauvegarde.Visionnage(reference: ReferenceTitre(type: v.type, tmdbID: v.tmdbID), episode: episode,
                                         dureeMinutes: v.dureeMinutes, note: v.note, vuLe: v.vuLe, anterieur: v.anterieur ? true : nil)
        }
        s.listes = try contexte.fetch(FetchDescriptor<ListePerso>(sortBy: [SortDescriptor(\.creeeLe)])).map {
            Sauvegarde.Liste(nom: $0.nom, creeeLe: $0.creeeLe, titres: $0.titres)
        }
        s.filtres = try contexte.fetch(FetchDescriptor<FiltreEnregistre>(sortBy: [SortDescriptor(\.creeLe)])).map {
            Sauvegarde.Filtre(nom: $0.nom, type: TypeTitre(rawValue: $0.typeBrut) ?? .film, criteres: $0.criteres,
                              alerteActive: $0.alerteActive, filtres: $0.filtres)
        }
        s.interets = try contexte.fetch(FetchDescriptor<Interet>()).map {
            Sauvegarde.Interet(libelle: $0.libelle, genreID: $0.genreID, motCleID: $0.motCleID, poids: $0.poids)
        }
        s.abonnements = try contexte.fetch(FetchDescriptor<Abonnement>()).map {
            Sauvegarde.Abonnement(providerID: $0.providerID, nom: $0.nom, actif: $0.actif)
        }
        s.chaines = try contexte.fetch(FetchDescriptor<Chaine>()).map {
            Sauvegarde.Chaine(identifiantGuide: $0.identifiantGuide, nom: $0.nom, source: $0.sourceBrut, active: $0.active)
        }
        s.acteursSuivis = try contexte.fetch(FetchDescriptor<ActeurSuivi>(sortBy: [SortDescriptor(\.suiviLe)])).map {
            Sauvegarde.ActeurSuivi(personneID: $0.personneID, nom: $0.nom, cheminPortrait: $0.cheminPortrait, suiviLe: $0.suiviLe)
        }
        return s
    }

    /// Applique une sauvegarde et renvoie ce qui a été ajouté.
    @discardableResult
    public func importer(_ sauvegarde: Sauvegarde) throws -> PlanImport {
        let plan = PlanImport(importee: sauvegarde, existante: try exporter())

        for s in plan.suivis {
            let suivi = Suivi(reference: s.reference, titre: s.titre, statut: StatutSuivi(rawValue: s.statut) ?? .aVoir, cheminAffiche: s.cheminAffiche)
            suivi.note = s.note
            suivi.exclusionLangue = s.exclusionLangue
            suivi.ajouteLe = s.ajouteLe
            suivi.acteursPrincipaux = s.acteursPrincipaux
            suivi.genres = s.genres
            suivi.alertesActives = s.alertesActives ?? true
            if let mode = s.modeAlertes { suivi.modeAlertesBrut = mode }
            contexte.insert(suivi)
        }
        for v in plan.visionnages {
            let visionnage = Visionnage(reference: v.reference, saison: v.episode?.saison, episode: v.episode?.episode,
                                        dureeMinutes: v.dureeMinutes, vuLe: v.vuLe, anterieur: v.anterieur ?? false)
            visionnage.note = v.note
            contexte.insert(visionnage)
        }
        for l in plan.listes {
            let liste = ListePerso(nom: l.nom)
            liste.creeeLe = l.creeeLe
            liste.titres = l.titres
            contexte.insert(liste)
        }
        if !plan.titresAjoutesAuxListes.isEmpty {
            for liste in try contexte.fetch(FetchDescriptor<ListePerso>()) {
                liste.titres += plan.titresAjoutesAuxListes[liste.nom] ?? []
            }
        }
        for f in plan.filtres {
            let filtre = FiltreEnregistre(nom: f.nom, type: f.type, criteres: f.criteres)
            filtre.filtres = f.filtres
            filtre.alerteActive = f.alerteActive
            contexte.insert(filtre)
        }
        for i in plan.interets {
            contexte.insert(Interet(libelle: i.libelle, genreID: i.genreID, motCleID: i.motCleID, poids: i.poids))
        }
        for a in plan.abonnements {
            let abonnement = Abonnement(providerID: a.providerID, nom: a.nom)
            abonnement.actif = a.actif
            contexte.insert(abonnement)
        }
        for c in plan.chaines {
            let chaine = Chaine(identifiantGuide: c.identifiantGuide, nom: c.nom, source: SourceGuide(rawValue: c.source) ?? .xmltvfr)
            chaine.active = c.active
            contexte.insert(chaine)
        }
        for a in plan.acteursSuivis {
            let acteur = ActeurSuivi(personneID: a.personneID, nom: a.nom, cheminPortrait: a.cheminPortrait)
            acteur.suiviLe = a.suiviLe
            contexte.insert(acteur)
        }
        try contexte.save()
        return plan
    }
}

/// Entretien du cache (ENF-07) : aucune donnée TMDB gardée plus de 6 mois, aucun programme TV passé.
@MainActor
public struct EntretienCache {
    public let contexte: ModelContext

    public init(contexte: ModelContext) {
        self.contexte = contexte
    }

    public struct Rapport: Equatable, Sendable {
        public var fichesSupprimees = 0
        public var diffusionsSupprimees = 0
    }

    @discardableResult
    public func purger(maintenant: Date = .now) throws -> Rapport {
        let limite = Calendar(identifier: .gregorian).date(byAdding: .month, value: -6, to: maintenant)!
        let fiches = try contexte.fetch(FetchDescriptor<TitreCache>(predicate: #Predicate { $0.majLe < limite }))
        let diffusions = try contexte.fetch(FetchDescriptor<Diffusion>(predicate: #Predicate { $0.fin < maintenant }))
        fiches.forEach(contexte.delete)
        diffusions.forEach(contexte.delete)
        try contexte.save()
        return Rapport(fichesSupprimees: fiches.count, diffusionsSupprimees: diffusions.count)
    }
}
