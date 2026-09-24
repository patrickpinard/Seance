import Foundation
import Testing
@testable import SeanceKit

@Suite("Fusion de la synchronisation")
struct FusionSynchroTests {
    private let t0 = Date(timeIntervalSince1970: 1_789_000_000)
    private let heat = ReferenceTitre(type: .film, tmdbID: 949)
    private let ronin = ReferenceTitre(type: .film, tmdbID: 8195)

    private func suivi(_ reference: ReferenceTitre, _ statut: String, note: Int? = nil) -> Sauvegarde.Suivi {
        Sauvegarde.Suivi(reference: reference, statut: statut, note: note, exclusionLangue: false, ajouteLe: t0, titre: "Titre \(reference.tmdbID)",
                         cheminAffiche: nil, acteursPrincipaux: [], genres: [])
    }

    private func etat(_ suivis: [Sauvegarde.Suivi]) -> Sauvegarde {
        var s = Sauvegarde(creeeLe: t0)
        s.suivis = suivis
        return s
    }

    @Test func laPremiereFoisRienNEstDate() {
        let datee = etat([suivi(heat, "aVoir")]).dater(depuis: nil, maintenant: t0)
        #expect(datee.modifications == nil && datee.suppressions == nil)
    }

    @Test func ceQuiChangeEstDateEtCeQuiDisparaitDevientUneSuppression() {
        let avant = etat([suivi(heat, "aVoir"), suivi(ronin, "aVoir")]).dater(depuis: nil, maintenant: t0)
        let apres = etat([suivi(heat, "termine", note: 9)]).dater(depuis: avant, maintenant: t0.addingTimeInterval(3600))
        #expect(apres.modifications == ["suivi:film:949": t0.addingTimeInterval(3600)])
        #expect(apres.suppressions == [Sauvegarde.Suppression(cle: "suivi:film:8195", le: t0.addingTimeInterval(3600))])

        // Rien ne bouge : les dates restent, la suppression aussi.
        let plusTard = etat([suivi(heat, "termine", note: 9)]).dater(depuis: apres, maintenant: t0.addingTimeInterval(7200))
        #expect(plusTard.modifications == apres.modifications)
        #expect(plusTard.suppressions == apres.suppressions)

        // Le titre revient : sa suppression s'efface, et son retour est daté.
        let revenu = etat([suivi(heat, "termine", note: 9), suivi(ronin, "aVoir")]).dater(depuis: plusTard, maintenant: t0.addingTimeInterval(9000))
        #expect(revenu.suppressions == nil)
        #expect(revenu.modifications?["suivi:film:8195"] == t0.addingTimeInterval(9000))
    }

    @Test func uneSoireePasseeNEstPasUneSuppression() {
        var avant = Sauvegarde(creeeLe: t0)
        // Deux jours avant : une soirée va de 6 h à 6 h, « hier » pourrait encore être la soirée en cours.
        let hier = DateTMDB(t0.addingTimeInterval(-2 * 86_400)).description
        avant.soirees = [Sauvegarde.Soiree(reference: heat, titre: "Heat", cheminAffiche: nil, soiree: hier, ajouteLe: t0)]
        let datee = Sauvegarde(creeeLe: t0).dater(depuis: avant.dater(depuis: nil, maintenant: t0), maintenant: t0)
        #expect(datee.suppressions == nil)
    }

    /// L'iPhone retire Ronin ; l'iPad, qui l'a encore, doit le perdre — et ne pas le ramener sur l'iPhone.
    @Test func uneSuppressionSePropageEtNeRevientPas() {
        let depart = etat([suivi(heat, "aVoir"), suivi(ronin, "aVoir")])
        let iphoneAvant = depart.dater(depuis: nil, maintenant: t0)
        let ipad = depart.dater(depuis: nil, maintenant: t0)
        let iphone = etat([suivi(heat, "aVoir")]).dater(depuis: iphoneAvant, maintenant: t0.addingTimeInterval(60))

        let surLIPad = PlanSynchro(recue: iphone, locale: ipad)
        #expect(surLIPad.aSupprimer.map(\.cle) == ["suivi:film:8195"])

        let surLIPhone = PlanSynchro(recue: ipad, locale: iphone)
        #expect(surLIPhone.aSupprimer.isEmpty)
        #expect(surLIPhone.aAjouter.suivis.map(\.reference) == [heat], "Ronin, supprimé ici, ne doit pas revenir de l'iPad")
    }

    /// Supprimé sur l'iPhone, mais modifié ensuite sur l'iPad : l'iPad l'emporte, le titre reste.
    @Test func unChangementPlusRecentBatUneSuppression() {
        let depart = etat([suivi(ronin, "aVoir")])
        let iphone = etat([]).dater(depuis: depart.dater(depuis: nil, maintenant: t0), maintenant: t0.addingTimeInterval(60))
        let ipad = etat([suivi(ronin, "termine", note: 8)]).dater(depuis: depart.dater(depuis: nil, maintenant: t0), maintenant: t0.addingTimeInterval(120))

        #expect(PlanSynchro(recue: iphone, locale: ipad).aSupprimer.isEmpty)
        #expect(PlanSynchro(recue: ipad, locale: iphone).aAjouter.suivis.map(\.reference) == [ronin])
    }

    /// « Marquer comme non vu » sur l'iPhone : l'iPad suit, et ne remet pas le film « terminé » sur l'iPhone.
    @Test func unRetourEnArriereSePropage() {
        let depart = etat([suivi(heat, "termine", note: 9)])
        let iphone = etat([suivi(heat, "aVoir")]).dater(depuis: depart.dater(depuis: nil, maintenant: t0), maintenant: t0.addingTimeInterval(60))
        let ipad = depart.dater(depuis: nil, maintenant: t0)

        let surLIPad = PlanSynchro(recue: iphone, locale: ipad)
        #expect(surLIPad.suivisRemplaces.map(\.statut) == ["aVoir"])
        #expect(surLIPad.datesRecues["suivi:film:949"] == t0.addingTimeInterval(60))

        let surLIPhone = PlanSynchro(recue: ipad, locale: iphone)
        #expect(surLIPhone.suivisRemplaces.isEmpty)
        #expect(surLIPhone.aAjouter.suivis.isEmpty, "La version de l'iPad, plus ancienne, ne doit pas « compléter » celle de l'iPhone")
    }

    @Test func lePrenomSuitLUtilisateurMaisPasLApparence() {
        var avant = Sauvegarde(creeeLe: t0)
        avant.preferences = ["profil.prenom": .texte("Pat"), "apparence": .texte("sombre")]
        var iphone = Sauvegarde(creeeLe: t0)
        iphone.preferences = ["profil.prenom": .texte("Patrick"), "apparence": .texte("clair")]
        iphone = iphone.dater(depuis: avant.dater(depuis: nil, maintenant: t0), maintenant: t0.addingTimeInterval(60))
        let plan = PlanSynchro(recue: iphone, locale: avant.dater(depuis: nil, maintenant: t0))
        #expect(plan.preferencesRemplacees == ["profil.prenom": .texte("Patrick")])
    }

    /// 8.0 : l'e-mail réglé sur l'iPhone (serveur, compte) arrive sur l'iPad, même si l'iPad avait déjà des réglages.
    @Test func lesReglagesDeLEMailSuiventLUtilisateur() {
        var avant = Sauvegarde(creeeLe: t0)
        avant.preferences = ["lettre.reglages": .donnees(Data("vide".utf8))]
        var iphone = Sauvegarde(creeeLe: t0)
        iphone.preferences = ["lettre.reglages": .donnees(Data("smtp.bluewin.ch".utf8))]
        iphone = iphone.dater(depuis: avant.dater(depuis: nil, maintenant: t0), maintenant: t0.addingTimeInterval(60))
        let plan = PlanSynchro(recue: iphone, locale: avant.dater(depuis: nil, maintenant: t0))
        #expect(plan.preferencesRemplacees == ["lettre.reglages": .donnees(Data("smtp.bluewin.ch".utf8))])
    }

    @Test func uneSauvegardeExporteeALaMainNeSupprimeRien() {
        let locale = etat([suivi(heat, "aVoir"), suivi(ronin, "aVoir")]).dater(depuis: nil, maintenant: t0)
        let plan = PlanSynchro(recue: etat([suivi(heat, "termine")]), locale: locale)
        #expect(plan.aSupprimer.isEmpty && plan.suivisRemplaces.isEmpty)
        #expect(plan.aAjouter.suivis.count == 1)
    }
}
