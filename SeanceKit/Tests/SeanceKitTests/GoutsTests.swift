import Foundation
import Testing
@testable import SeanceKit

/// Fabrique les valeurs des tests de recommandation.
enum Goûts {
    static func titre(
        _ id: Int, _ nom: String = "Titre", type: TypeTitre = .film, genres: [Int] = [28],
        note: Double = 7, votes: Int = 500, annee: Int = 2020, langue: String = "en", synopsis: String = ""
    ) -> TitreResume {
        TitreResume(
            reference: ReferenceTitre(type: type, tmdbID: id), titre: nom, titreOriginal: nom,
            langueOriginale: langue, synopsis: synopsis, genres: genres, cheminAffiche: nil, cheminFond: nil,
            noteMoyenne: note, nombreVotes: votes, date: DateTMDB(annee: annee, mois: 6, jour: 1)
        )
    }

    static func candidat(
        _ id: Int, _ nom: String = "Titre", type: TypeTitre = .film, genres: [Int] = [28],
        note: Double = 7, votes: Int = 500, duree: Int? = nil, acteurs: [Int: String] = [:],
        disponibilite: EtatDisponibilite? = nil
    ) -> CandidatSuggestion {
        CandidatSuggestion(
            titre: titre(id, nom, type: type, genres: genres, note: note, votes: votes),
            dureeMinutes: duree, acteurs: Array(acteurs.keys), nomsActeurs: acteurs, disponibilite: disponibilite
        )
    }

    static func note(_ note: Int, genres: [Int], acteurs: [Int: String] = [:], duree: Int? = nil,
                     type: TypeTitre = .film, date: Date? = nil) -> ObservationGout {
        ObservationGout(origine: .note(note), genres: genres, acteurs: Array(acteurs.keys), nomsActeurs: acteurs,
                        type: type, dureeMinutes: duree, date: date)
    }

    static let noms = [28: "Action", 53: "Thriller", 10749: "Romance", 35: "Comédie"]
    static let maintenant = Date.suisse("2026-09-16 20:00")
}

@Suite("Profil de goûts")
struct ProfilGoutsTests {
    /// EF-61, EF-62 : de bonnes notes font un genre favori, une mauvaise note fait un genre évité.
    @Test func genresAimesEtEvites() {
        let profil = ProfilGouts.calculer([
            Goûts.note(9, genres: [28, 53]),
            Goûts.note(8, genres: [28]),
            Goûts.note(2, genres: [10749]),
        ], maintenant: Goûts.maintenant)

        // 9 et 8 sur 10 donnent 0,75 + 0,5 = 1,25, soit tanh(1,25 / 3) ≈ 0,39 : un net favori.
        #expect(profil.affinite(genre: 28) > 0.35)
        #expect(profil.affinite(genre: 10749) < -0.25)
        #expect(profil.genresPreferes.first == 28)
        #expect(profil.genresEvites == [10749])
        #expect(profil.noteMoyenne == 19.0 / 3)
    }

    /// EF-60, EF-62 : les intérêts cochés au premier lancement suffisent à orienter les suggestions.
    @Test func lesInteretsComptentAvantTouteHistoire() {
        let profil = ProfilGouts.calculer([
            ObservationGout(origine: .interetDeclare, genres: [28], poids: 2),
            ObservationGout(origine: .interetDeclare, genres: [53]),
        ], maintenant: Goûts.maintenant)

        #expect(profil.genresPreferes == [28, 53])
        #expect(profil.observations == 2)
        // Un profil de deux signaux ne doit pas peser autant qu'un profil nourri.
        #expect(profil.maturite == 0.1)
    }

    @Test func unGoutAncienPeseMoinsQuUnGoutRecent() {
        let ancien = ProfilGouts.calculer(
            [Goûts.note(9, genres: [28], date: Goûts.maintenant.addingTimeInterval(-3 * 365 * 86_400))],
            maintenant: Goûts.maintenant
        )
        let recent = ProfilGouts.calculer(
            [Goûts.note(9, genres: [28], date: Goûts.maintenant.addingTimeInterval(-7 * 86_400))],
            maintenant: Goûts.maintenant
        )

        #expect(ancien.affinite(genre: 28) < recent.affinite(genre: 28))
        #expect(ancien.affinite(genre: 28) > 0)
    }

    /// La durée habituelle sort des films retenus, pas des séries ni des titres mal notés.
    @Test func dureeHabituelleEtPartDesSeries() {
        let profil = ProfilGouts.calculer([
            ObservationGout(origine: .visionnage, genres: [28], type: .film, dureeMinutes: 100, date: Goûts.maintenant),
            ObservationGout(origine: .visionnage, genres: [28], type: .film, dureeMinutes: 110, date: Goûts.maintenant),
            ObservationGout(origine: .visionnage, genres: [28], type: .film, dureeMinutes: 120, date: Goûts.maintenant),
            ObservationGout(origine: .visionnage, genres: [53], type: .serie, date: Goûts.maintenant),
            Goûts.note(1, genres: [35], duree: 240),
        ], maintenant: Goûts.maintenant)

        #expect(profil.dureeHabituelleMinutes == 110)
        #expect(profil.ecartDureeMinutes == 20)
        #expect(profil.partSeries == 0.25)
    }

    /// EF-26 : « Jamais » n'écarte pas seulement le titre, il apprend au profil.
    @Test func leRejetTireLeGenreVersLeBas() {
        let sansRejet = ProfilGouts.calculer([Goûts.note(7, genres: [35])], maintenant: Goûts.maintenant)
        let avecRejet = ProfilGouts.calculer([
            Goûts.note(7, genres: [35]),
            ObservationGout(origine: .rejet, genres: [35], type: .film, date: Goûts.maintenant),
        ], maintenant: Goûts.maintenant)

        #expect(avecRejet.affinite(genre: 35) < sansRejet.affinite(genre: 35))
    }

    @Test func profilVideQuandRienNEstConnu() {
        let profil = ProfilGouts.calculer([], maintenant: Goûts.maintenant)
        #expect(profil.estVide)
        #expect(profil.maturite == 0)
        #expect(profil.affinite(genre: 28) == 0)
    }
}

@Suite("Classement local")
struct ClassementLocalTests {
    private var profil: ProfilGouts {
        ProfilGouts.calculer(
            (1...10).map { _ in Goûts.note(9, genres: [28], acteurs: [6384: "Keanu Reeves"]) }
                + [Goûts.note(2, genres: [10749])],
            maintenant: Goûts.maintenant
        )
    }

    /// EF-27 : sans Claude, le genre aimé et l'acteur suivi remontent, le genre évité descend.
    @Test func ordreParAffinite() {
        let classement = ClassementLocal.classer([
            Goûts.candidat(1, "Romance", genres: [10749]),
            Goûts.candidat(2, "Action", genres: [28]),
            Goûts.candidat(3, "Action avec Keanu", genres: [28], acteurs: [6384: "Keanu Reeves"]),
        ], profil: profil)

        #expect(classement.map(\.reference.tmdbID) == [3, 2, 1])
        #expect(classement[0].score.valeur > classement[2].score.valeur)
    }

    /// Deux titres identiques gardent le même ordre d'un appel à l'autre.
    @Test func ordreStableAScoreEgal() {
        let candidats = [Goûts.candidat(77, genres: [28]), Goûts.candidat(12, genres: [28])]
        #expect(ClassementLocal.classer(candidats, profil: profil).map(\.reference.tmdbID) == [12, 77])
        #expect(ClassementLocal.classer(candidats.reversed(), profil: profil).map(\.reference.tmdbID) == [12, 77])
    }

    /// EF-22 : les deux précisions de la demande écartent des candidats avant tout classement.
    @Test func laDemandeEcarteLeTypeEtLesTropLongs() {
        let candidats = [
            Goûts.candidat(1, type: .film, duree: 180),
            Goûts.candidat(2, type: .film, duree: 95),
            Goûts.candidat(3, type: .serie),
            Goûts.candidat(4, type: .film),
        ]
        let demande = DemandeCeSoir(envie: "court", type: .film, dureeMaxMinutes: 120)

        // La durée inconnue (4) reste : TMDB ne la donne pas dans ses listes.
        #expect(Set(ClassementLocal.classer(candidats, profil: profil, demande: demande).map(\.reference.tmdbID)) == [2, 4])
    }

    @Test func unTitreIntrouvableNeSeProposePas() {
        let candidats = [Goûts.candidat(1, disponibilite: .introuvable), Goûts.candidat(2)]
        #expect(ClassementLocal.classer(candidats, profil: profil).map(\.reference.tmdbID) == [2])
    }

    /// La phrase locale dit d'où vient le classement, sans jamais inventer.
    @Test func laPhraseCiteLeGenreEtLActeur() {
        let candidat = Goûts.candidat(3, genres: [28], note: 8.2, acteurs: [6384: "Keanu Reeves"],
                                      disponibilite: .surNAS(qualite: .hd1080))
        let phrase = ClassementLocal.classer([candidat], profil: profil, nomsGenres: Goûts.noms)[0].phrase

        #expect(phrase.contains("Action, un genre que tu aimes"))
        #expect(phrase.contains("avec Keanu Reeves"))
        #expect(phrase.contains("82 % sur TMDB"))
        #expect(phrase.contains("déjà chez toi"))
        #expect(phrase.hasSuffix("."))
    }

    /// « Pas ce genre » (8.7) : un intérêt au poids négatif rejette le genre, même après deux films vus du même genre.
    @Test func unGenreEcarteEstEvite() {
        let profil = ProfilGouts.calculer([
            ObservationGout(origine: .interetDeclare, genres: [27], poids: -3),
            ObservationGout(origine: .visionnage, genres: [27], date: Goûts.maintenant),
            ObservationGout(origine: .visionnage, genres: [27], date: Goûts.maintenant),
        ], maintenant: Goûts.maintenant)
        #expect(profil.genresEvites.contains(27))
    }

    /// Un genre écarté n'a pas la clé de synchronisation du même genre aimé : l'un se supprime, l'autre s'ajoute.
    @Test func unGenreEcarteALaSienneCleDeSynchro() {
        let aime = Sauvegarde.Interet(libelle: "Horreur", genreID: 27, motCleID: nil, poids: 1)
        let ecarte = Sauvegarde.Interet(libelle: "Horreur", genreID: 27, motCleID: nil, poids: -3)
        #expect(aime.cle == "27|-")
        #expect(ecarte.cle == "27|-|non")
    }

    @Test func sansGoutConnuLaPhraseLeDit() {
        let phrase = ClassementLocal.classer([Goûts.candidat(1, votes: 0)],
                                             profil: ProfilGouts(), nomsGenres: Goûts.noms)[0].phrase
        #expect(phrase.contains("tes goûts ne disent encore rien"))
    }
}
