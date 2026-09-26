import Foundation
import Testing
@testable import SeanceKit

@Suite("Langue et sous-titres retenus")
struct PreferencesPistesTests {
    let audio = [PreferencesPistes.Piste(id: "a1", nom: "English 5.1", langue: "eng"),
                 PreferencesPistes.Piste(id: "a2", nom: "Français (VF)", langue: "fre")]
    let texte = [PreferencesPistes.Piste(id: "t1", nom: "Anglais", langue: "en"),
                 PreferencesPistes.Piste(id: "t2", nom: "Français forcés", langue: "fra")]

    @Test func laVFEstChoisieSansSousTitres() {
        let choix = PreferencesPistes().choisir(audio: audio, sousTitres: texte, audioActuelle: "a1")
        #expect(choix.audio == "a2")
        #expect(choix.sousTitres == .aucun)
    }

    @Test func sansVFLaVOEstSousTitreeEnFrancais() {
        let vo = [PreferencesPistes.Piste(id: "a1", nom: "English", langue: "eng")]
        let choix = PreferencesPistes().choisir(audio: vo, sousTitres: texte, audioActuelle: "a1")
        #expect(choix.audio == nil)
        #expect(choix.sousTitres == .piste("t2"))
    }

    @Test func versionOriginaleVoulue() {
        let prefs = PreferencesPistes(audio: "", sousTitres: .siLangueEtrangere, langueSousTitres: "fr")
        let choix = prefs.choisir(audio: audio, sousTitres: texte, audioActuelle: "a1")
        #expect(choix.audio == nil)
        #expect(choix.sousTitres == .piste("t2"))
    }

    @Test func jamaisDeSousTitres() {
        let prefs = PreferencesPistes(audio: "en", sousTitres: .jamais)
        let choix = prefs.choisir(audio: audio, sousTitres: texte, audioActuelle: "a2")
        #expect(choix.audio == "a1")
        #expect(choix.sousTitres == .aucun)
    }

    @Test func laLangueSeLitAussiDansLeNom() {
        #expect(PreferencesPistes.Piste(id: "x", nom: "Piste 2 - [Français]", langue: nil).code == "fr")
        #expect(PreferencesPistes.Piste(id: "x", nom: "Commentaires", langue: nil).code == nil)
    }

    @Test func presqueFini() {
        #expect(FinDeLecture.presqueFini(secondes: 91, duree: 100 * 60) == false)
        #expect(FinDeLecture.presqueFini(secondes: 0.91 * 45 * 60, duree: 45 * 60))
        // Le générique d'un long film : quatre minutes avant la fin suffisent.
        #expect(FinDeLecture.presqueFini(secondes: 117 * 60, duree: 120 * 60))
        #expect(FinDeLecture.presqueFini(secondes: 100, duree: 110) == false)
    }

    @Test func uneCleParProfil() {
        #expect(PreferencesPistes.cle(profil: "") == "lecture.pistes")
        #expect(PreferencesPistes.cle(profil: "anne") == "lecture.pistes.anne")
    }
}
