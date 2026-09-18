import Foundation
import SeanceKit
import SwiftData

/// Export et import de la sauvegarde JSON (EF-70). L'import ajoute ce qui manque et complète les titres déjà là,
/// sans rien supprimer ni effacer. Les réglages (`preferences`) sont lus et appliqués par l'app, qui seule les connaît.
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
                             alertesActives: $0.alertesActives, modeAlertes: $0.modeAlertesBrut, masque: $0.masque ? true : nil,
                             acteursPrincipauxIDs: $0.acteursPrincipauxIDs.isEmpty ? nil : $0.acteursPrincipauxIDs)
        }
        s.visionnages = try contexte.fetch(FetchDescriptor<Visionnage>(sortBy: [SortDescriptor(\.vuLe)])).map { v in
            let episode = v.saison.flatMap { saison in v.episode.map { NumeroEpisode(saison: saison, episode: $0) } }
            return Sauvegarde.Visionnage(reference: ReferenceTitre(type: v.type, tmdbID: v.tmdbID), episode: episode,
                                         dureeMinutes: v.dureeMinutes, note: v.note, vuLe: v.vuLe, anterieur: v.anterieur ? true : nil)
        }
        s.listes = try contexte.fetch(FetchDescriptor<ListePerso>(sortBy: [SortDescriptor(\.creeeLe)])).map {
            Sauvegarde.Liste(nom: $0.nom, creeeLe: $0.creeeLe, titres: $0.titres,
                             apercus: $0.apercus.isEmpty ? nil : $0.apercus.map {
                                 Sauvegarde.Liste.Apercu(reference: $0.reference, titre: $0.titre, cheminAffiche: $0.cheminAffiche)
                             })
        }
        s.filtres = try contexte.fetch(FetchDescriptor<FiltreEnregistre>(sortBy: [SortDescriptor(\.creeLe)])).map {
            Sauvegarde.Filtre(nom: $0.nom, type: TypeTitre(rawValue: $0.typeBrut) ?? .film, criteres: $0.criteres,
                              alerteActive: $0.alerteActive, filtres: $0.filtres)
        }
        s.interets = try contexte.fetch(FetchDescriptor<Interet>()).map {
            Sauvegarde.Interet(libelle: $0.libelle, genreID: $0.genreID, motCleID: $0.motCleID, poids: $0.poids)
        }
        s.abonnements = try contexte.fetch(FetchDescriptor<Abonnement>()).map {
            Sauvegarde.Abonnement(providerID: $0.providerID, nom: $0.nom, actif: $0.actif, cheminLogo: $0.cheminLogo)
        }
        s.chaines = try contexte.fetch(FetchDescriptor<Chaine>()).map {
            Sauvegarde.Chaine(identifiantGuide: $0.identifiantGuide, nom: $0.nom, source: $0.sourceBrut, active: $0.active)
        }
        s.acteursSuivis = try contexte.fetch(FetchDescriptor<ActeurSuivi>(sortBy: [SortDescriptor(\.suiviLe)])).map {
            Sauvegarde.ActeurSuivi(personneID: $0.personneID, nom: $0.nom, cheminPortrait: $0.cheminPortrait, suiviLe: $0.suiviLe,
                                   filmsConnus: $0.filmsConnus.isEmpty ? nil : $0.filmsConnus, verifieLe: $0.verifieLe)
        }
        // Les soirées passées n'intéressent plus personne ; celles de ce soir et d'après voyagent.
        let ceSoir = ServiceSoiree.soiree(date)
        s.soirees = try contexte.fetch(FetchDescriptor<SelectionSoir>(sortBy: [SortDescriptor(\.soiree), SortDescriptor(\.ajouteLe)]))
            .filter { $0.soiree >= ceSoir }
            .map { Sauvegarde.Soiree(reference: $0.reference, titre: $0.titre, cheminAffiche: $0.cheminAffiche, soiree: $0.soiree, ajouteLe: $0.ajouteLe) }
        s.reports = try contexte.fetch(FetchDescriptor<SuggestionReportee>())
            .filter { $0.jusquA > date }
            .map { Sauvegarde.Report(reference: $0.reference, jusquA: $0.jusquA, reporteLe: $0.reporteLe) }
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
            suivi.masque = s.masque ?? false
            suivi.acteursPrincipauxIDs = s.acteursPrincipauxIDs ?? []
            contexte.insert(suivi)
        }
        // Les titres déjà là : rien n'est effacé, le fichier complète seulement (note, avancement, acteurs, genres).
        if !plan.suivisCompletes.isEmpty {
            let presents = Dictionary(try contexte.fetch(FetchDescriptor<Suivi>()).map { ($0.reference, $0) }, uniquingKeysWith: { premier, _ in premier })
            for s in plan.suivisCompletes {
                guard let suivi = presents[s.reference] else { continue }
                suivi.note = s.note
                if let statut = StatutSuivi(rawValue: s.statut), statut != suivi.statut { suivi.statut = statut }
                suivi.acteursPrincipaux = s.acteursPrincipaux
                suivi.acteursPrincipauxIDs = s.acteursPrincipauxIDs ?? suivi.acteursPrincipauxIDs
                suivi.genres = s.genres
                suivi.cheminAffiche = s.cheminAffiche
            }
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
            liste.apercus = (l.apercus ?? []).map { ApercuTitre(reference: $0.reference, titre: $0.titre, cheminAffiche: $0.cheminAffiche) }
            contexte.insert(liste)
        }
        if !plan.titresAjoutesAuxListes.isEmpty {
            for liste in try contexte.fetch(FetchDescriptor<ListePerso>()) {
                let ajoutes = plan.titresAjoutesAuxListes[liste.nom] ?? []
                liste.titres += ajoutes
                let importes = sauvegarde.listes.first { $0.nom == liste.nom }?.apercus ?? []
                liste.apercus += importes.filter { ajoutes.contains($0.reference) }
                    .map { ApercuTitre(reference: $0.reference, titre: $0.titre, cheminAffiche: $0.cheminAffiche) }
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
            let abonnement = Abonnement(providerID: a.providerID, nom: a.nom, cheminLogo: a.cheminLogo)
            abonnement.actif = a.actif
            contexte.insert(abonnement)
        }
        if !plan.logosAbonnements.isEmpty {
            for abonnement in try contexte.fetch(FetchDescriptor<Abonnement>()) where abonnement.cheminLogo == nil {
                abonnement.cheminLogo = plan.logosAbonnements[abonnement.providerID]
            }
        }
        for c in plan.chaines {
            let chaine = Chaine(identifiantGuide: c.identifiantGuide, nom: c.nom, source: SourceGuide(rawValue: c.source) ?? .xmltvfr)
            chaine.active = c.active
            contexte.insert(chaine)
        }
        for a in plan.acteursSuivis {
            let acteur = ActeurSuivi(personneID: a.personneID, nom: a.nom, cheminPortrait: a.cheminPortrait)
            acteur.suiviLe = a.suiviLe
            acteur.filmsConnus = a.filmsConnus ?? []
            acteur.verifieLe = a.verifieLe
            contexte.insert(acteur)
        }
        // Une soirée passée entre l'export et l'import ne revient pas.
        let ceSoir = ServiceSoiree.soiree()
        for soiree in plan.soirees where soiree.soiree >= ceSoir {
            let selection = SelectionSoir(reference: soiree.reference, titre: soiree.titre, cheminAffiche: soiree.cheminAffiche, soiree: soiree.soiree)
            selection.ajouteLe = soiree.ajouteLe
            contexte.insert(selection)
        }
        for report in plan.reports where report.jusquA > .now {
            let reporte = SuggestionReportee(reference: report.reference, jusquA: report.jusquA)
            reporte.reporteLe = report.reporteLe
            contexte.insert(reporte)
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
