import Foundation
import SeanceKit
import SwiftData

/// Fusionne les fichiers des autres appareils dans ce magasin, suppressions et retours en arrière compris, et prépare
/// le fichier à déposer pour eux (voir `FusionSynchro` dans SeanceKit). Sans fichiers ni réseau : l'app s'en charge.
@MainActor
public struct ServiceSynchro {
    public let contexte: ModelContext

    public init(contexte: ModelContext) {
        self.contexte = contexte
    }

    /// Ce qu'un fichier reçu a changé ici.
    public struct Recu {
        public let nom: String
        public let ajouts: PlanImport
        public let supprimes: Int
        public let misAJour: Int

        public var estVide: Bool { ajouts.estVide && supprimes == 0 && misAJour == 0 }
    }

    public struct Resultat {
        /// L'état de cet appareil après fusion, daté : à déposer dans le dossier, et à garder comme point de
        /// comparaison pour la prochaine synchronisation.
        public let aDeposer: Sauvegarde
        public let recus: [Recu]
        /// Réglages modifiés plus récemment ailleurs : l'app, qui seule les connaît, les applique.
        public let preferencesRemplacees: [String: Sauvegarde.Preference]
    }

    /// `precedente` : l'état déposé à la synchronisation précédente de cet appareil (`nil` la première fois).
    /// `preferences` : les réglages actuels de l'app.
    public func fusionner(
        recues: [(nom: String, sauvegarde: Sauvegarde)], precedente: Sauvegarde?,
        preferences: [String: Sauvegarde.Preference], maintenant: Date = .now
    ) throws -> Resultat {
        let sauvegardes = ServiceSauvegarde(contexte: contexte)
        var locale = try sauvegardes.exporter(le: maintenant)
        locale.preferences = preferences
        // 1. Ce qui a changé ici depuis la dernière synchronisation, avant de regarder les autres.
        locale = locale.dater(depuis: precedente, maintenant: maintenant)

        var recus: [Recu] = []
        var preferencesRemplacees: [String: Sauvegarde.Preference] = [:]
        for (nom, recue) in recues {
            let plan = PlanSynchro(recue: recue, locale: locale)
            let supprimes = try supprimer(plan.aSupprimer.map(\.cle))
            let misAJour = try remplacer(plan)
            let ajouts = try sauvegardes.importer(plan.aAjouter)
            recus.append(Recu(nom: nom, ajouts: ajouts, supprimes: supprimes, misAJour: misAJour))
            preferencesRemplacees.merge(plan.preferencesRemplacees) { _, recente in recente }
            // 2. Le fichier suivant se compare à l'état d'après celui-ci. Ce qui vient de l'autre appareil garde sa
            //    date à lui, et ses suppressions la leur : datées d'aujourd'hui, elles battraient à tort un changement
            //    fait entre-temps sur un troisième appareil.
            var suivante = try sauvegardes.exporter(le: maintenant)
            suivante.preferences = preferences.merging(preferencesRemplacees) { _, recente in recente }
            suivante.modifications = (locale.modifications ?? [:]).merging(plan.datesRecues) { max($0, $1) }
            suivante.suppressions = Self.reunir(locale.suppressions ?? [], plan.aSupprimer)
            locale = suivante
        }

        // 3. L'état final : ne garde de date que pour ce qui existe, et de suppression que pour ce qui n'existe plus.
        var finale = locale
        let presentes = finale.signatures()
        let modifications = (finale.modifications ?? [:]).filter { presentes[$0.key] != nil }
        let suppressions = (finale.suppressions ?? []).filter { presentes[$0.cle] == nil }
        finale.modifications = modifications.isEmpty ? nil : modifications
        finale.suppressions = suppressions.isEmpty ? nil : suppressions
        return Resultat(aDeposer: finale, recus: recus, preferencesRemplacees: preferencesRemplacees)
    }

    private static func reunir(_ a: [Sauvegarde.Suppression], _ b: [Sauvegarde.Suppression]) -> [Sauvegarde.Suppression] {
        var parCle: [String: Date] = [:]
        for suppression in a + b { parCle[suppression.cle] = min(parCle[suppression.cle] ?? suppression.le, suppression.le) }
        return parCle.map { Sauvegarde.Suppression(cle: $0.key, le: $0.value) }.sorted { ($0.le, $0.cle) < ($1.le, $1.cle) }
    }

    // MARK: Appliquer

    /// Supprime, objet par objet (une suppression en lot ne prévient pas les écrans), ce que désignent ces clés.
    private func supprimer(_ cles: [String]) throws -> Int {
        guard !cles.isEmpty else { return 0 }
        let voulues = Set(cles)
        var nombre = 0
        for suivi in try contexte.fetch(FetchDescriptor<Suivi>()) where voulues.contains("suivi:\(suivi.reference)") {
            contexte.delete(suivi); nombre += 1
        }
        for v in try contexte.fetch(FetchDescriptor<Visionnage>()) {
            let episode = v.saison.flatMap { saison in v.episode.map { NumeroEpisode(saison: saison, episode: $0) } }
            let cle = "visionnage:\(ReferenceTitre(type: v.type, tmdbID: v.tmdbID))|\(episode?.description ?? "-")|\(Int(v.vuLe.timeIntervalSince1970 / 60))"
            if voulues.contains(cle) { contexte.delete(v); nombre += 1 }
        }
        for soiree in try contexte.fetch(FetchDescriptor<SelectionSoir>()) where voulues.contains("soiree:\(soiree.reference)|\(soiree.soiree)") {
            contexte.delete(soiree); nombre += 1
        }
        for aime in try contexte.fetch(FetchDescriptor<TitreAime>()) where voulues.contains("aime:\(aime.reference)") {
            contexte.delete(aime); nombre += 1
        }
        for favori in try contexte.fetch(FetchDescriptor<Favori>()) where voulues.contains("favori:\(favori.reference)") {
            contexte.delete(favori); nombre += 1
        }
        for acteur in try contexte.fetch(FetchDescriptor<ActeurSuivi>()) where voulues.contains("acteur:\(acteur.personneID)") {
            contexte.delete(acteur); nombre += 1
        }
        for filtre in try contexte.fetch(FetchDescriptor<FiltreEnregistre>()) where voulues.contains("filtre:\(filtre.nom)") {
            contexte.delete(filtre); nombre += 1
        }
        for interet in try contexte.fetch(FetchDescriptor<Interet>()) {
            let cle = "interet:\(interet.genreID.map(String.init) ?? "-")|\(interet.motCleID.map(String.init) ?? "-")"
            if voulues.contains(cle) { contexte.delete(interet); nombre += 1 }
        }
        for liste in try contexte.fetch(FetchDescriptor<ListePerso>()) {
            if voulues.contains("liste:\(liste.nom)") {
                contexte.delete(liste); nombre += 1
                continue
            }
            let retires = liste.titres.filter { voulues.contains("listeTitre:\(liste.nom)|\($0)") }
            guard !retires.isEmpty else { continue }
            liste.titres.removeAll { retires.contains($0) }
            liste.apercus.removeAll { retires.contains($0.reference) }
            nombre += retires.count
        }
        try contexte.save()
        return nombre
    }

    /// Le plus récent gagne : l'état d'un titre (vu, non vu, note, cloche), une plateforme ou une chaîne cochée.
    private func remplacer(_ plan: PlanSynchro) throws -> Int {
        var nombre = 0
        if !plan.suivisRemplaces.isEmpty {
            let presents = Dictionary(try contexte.fetch(FetchDescriptor<Suivi>()).map { ($0.reference, $0) }, uniquingKeysWith: { premier, _ in premier })
            for recu in plan.suivisRemplaces {
                guard let suivi = presents[recu.reference] else { continue }
                if let statut = StatutSuivi(rawValue: recu.statut), statut != suivi.statut { suivi.statut = statut }
                suivi.note = recu.note
                suivi.masque = recu.masque ?? false
                suivi.alertesActives = recu.alertesActives ?? suivi.alertesActives
                if let mode = recu.modeAlertes { suivi.modeAlertesBrut = mode }
                suivi.exclusionLangue = recu.exclusionLangue
                nombre += 1
            }
        }
        if !plan.abonnementsActifs.isEmpty {
            for abonnement in try contexte.fetch(FetchDescriptor<Abonnement>()) {
                if let actif = plan.abonnementsActifs[abonnement.providerID], actif != abonnement.actif { abonnement.actif = actif; nombre += 1 }
            }
        }
        if !plan.chainesActives.isEmpty {
            for chaine in try contexte.fetch(FetchDescriptor<Chaine>()) {
                if let active = plan.chainesActives[chaine.identifiantGuide], active != chaine.active { chaine.active = active; nombre += 1 }
            }
        }
        try contexte.save()
        return nombre
    }
}
