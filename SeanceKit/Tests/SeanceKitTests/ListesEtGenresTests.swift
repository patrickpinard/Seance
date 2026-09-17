import Foundation
import Testing
@testable import SeanceKit

@Suite("Mes listes et genres par défaut")
struct ListesEtGenresTests {
    private let heat = ReferenceTitre(type: .film, tmdbID: 949)

    @Test func regardableCeSoir() {
        let maintenant = Date.suisse("2026-09-17 19:00")
        let netflix = Construire.fournisseur(8, "Netflix")
        #expect(RegardableCeSoir.retient(.surNAS(qualite: .uhd4K), maintenant: maintenant))
        #expect(RegardableCeSoir.retient(.dansAbonnements([netflix]), maintenant: maintenant))
        #expect(!RegardableCeSoir.retient(.aLouerOuAcheter(location: [netflix], achat: []), maintenant: maintenant))
        #expect(!RegardableCeSoir.retient(.introuvable, maintenant: maintenant))

        // La télé : ce soir jusqu'à 2 h du matin, pas demain soir.
        let ceSoir = DiffusionPrevue(chaine: "RTS 1", debut: Date.suisse("2026-09-17 20:55"), fin: Date.suisse("2026-09-17 23:00"))
        let tard = DiffusionPrevue(chaine: "M6", debut: Date.suisse("2026-09-18 01:30"), fin: Date.suisse("2026-09-18 03:00"))
        let demain = DiffusionPrevue(chaine: "TF1", debut: Date.suisse("2026-09-18 21:00"), fin: Date.suisse("2026-09-18 23:00"))
        #expect(RegardableCeSoir.retient(.aLaTeleBientot(ceSoir), maintenant: maintenant))
        #expect(RegardableCeSoir.retient(.aLaTeleBientot(tard), maintenant: maintenant))
        #expect(!RegardableCeSoir.retient(.aLaTeleBientot(demain), maintenant: maintenant))
        // À 1 h du matin, la soirée en cours compte encore ; la suivante non.
        #expect(RegardableCeSoir.retient(.aLaTeleBientot(tard), maintenant: Date.suisse("2026-09-18 01:00")))
        #expect(!RegardableCeSoir.retient(.aLaTeleBientot(demain), maintenant: Date.suisse("2026-09-18 01:00")))

        #expect(RegardableCeSoir.libelle(.aLaTeleBientot(ceSoir)) == "RTS 1 à 20:55")
        #expect(RegardableCeSoir.libelle(.surNAS(qualite: .uhd4K)) == "Sur le NAS · 4K")
        #expect(RegardableCeSoir.libelle(.dansAbonnements([netflix])) == "Netflix")
    }

    @Test func triDesListes() {
        func element(_ id: Int, _ titre: String, jour: Int, duree: Int?) -> TriListe.Element {
            TriListe.Element(reference: ReferenceTitre(type: .film, tmdbID: id), titre: titre,
                             ajouteLe: Date.suisse("2026-09-\(10 + jour) 12:00"), dureeMinutes: duree)
        }
        let liste = [
            element(1, "Heat", jour: 1, duree: 170),
            element(2, "Ronin", jour: 3, duree: nil),
            element(3, "Collateral", jour: 2, duree: 120),
            element(4, "Échec et mat", jour: 4, duree: 120),
        ]
        #expect(TriListe.ajout.trier(liste).map(\.titre) == ["Échec et mat", "Ronin", "Collateral", "Heat"])
        // Durée inconnue en dernier ; à durée égale, le plus récent d'abord.
        #expect(TriListe.plusCourt.trier(liste).map(\.titre) == ["Échec et mat", "Collateral", "Heat", "Ronin"])
        #expect(TriListe.titre.trier(liste).map(\.titre) == ["Collateral", "Échec et mat", "Heat", "Ronin"])
    }

    @Test func genresParDefautCouvrentTMDB() throws {
        struct Liste: Decodable { let genres: [Genre] }
        let tmdb = try JSONDecoder().decode(Liste.self, from: Fixture.donnees("genre_movie_list")).genres
        let noms = GenresParDefaut.noms
        #expect(tmdb.allSatisfy { noms[$0.id] != nil })
        #expect(noms[28] == "Action" && noms[10759] == "Action & Aventure")

        // Les noms de TMDB l'emportent, sans perdre un genre qu'il n'aurait pas renvoyé.
        let fusion = GenresParDefaut.fusionner([Genre(id: 28, nom: "Action !")], defaut: GenresParDefaut.films)
        #expect(fusion.first == Genre(id: 28, nom: "Action !"))
        #expect(fusion.count == GenresParDefaut.films.count)
        #expect(GenresParDefaut.fusionner([], defaut: GenresParDefaut.series) == GenresParDefaut.series)
    }
}
