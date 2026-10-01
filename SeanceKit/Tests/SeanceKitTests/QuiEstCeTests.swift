import Foundation
import Testing
@testable import SeanceKit

@Suite("Qui est-ce ? à la pause")
struct QuiEstCeTests {
    private func decoder<T: Decodable>(_ type: T.Type, _ objet: Any) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: objet))
    }

    private func casting() throws -> Casting {
        try decoder(Casting.self, [
            "cast": [
                ["id": 2, "name": "Second rôle", "character": "Le voisin", "order": 1, "profile_path": "/b.jpg"],
                ["id": 1, "name": "Premier rôle", "character": "Ripley", "order": 0, "profile_path": "/a.jpg"],
                ["id": 3, "name": "Sans visage", "character": "Un passant", "order": 2],
            ],
            "crew": [["id": 9, "name": "La réalisatrice", "job": "Director", "profile_path": "/r.jpg"]],
        ])
    }

    @Test func lesPremiersRolesPuisLesInvitesSansRealisateur() throws {
        let invites = try decoder([PersonneCasting].self, [
            ["id": 4, "name": "Invitée", "character": "La juge", "order": 0, "profile_path": "/i.jpg"],
            ["id": 1, "name": "Premier rôle", "character": "Ripley", "order": 5, "profile_path": "/a.jpg"],
        ])
        let visages = QuiEstCe.visages(casting: try casting(), invites: invites)
        // Le visage sans portrait passe en dernier ; le premier rôle, aussi invité, n'apparaît qu'une fois.
        #expect(visages.map(\.id) == [1, 2, 4, 3])
        #expect(!visages.contains { $0.id == 9 })
        #expect(QuiEstCe.visages(casting: try casting(), nombre: 2).map(\.id) == [1, 2])
    }

    @Test func lesInvitesArriventAvecLesEpisodesDeLaSaison() throws {
        var json = try JSONSerialization.jsonObject(with: Fixture.donnees("tv_season")) as! [String: Any]
        var episodes = json["episodes"] as! [[String: Any]]
        episodes[0]["guest_stars"] = [["id": 7, "name": "Invité", "character": "Le facteur", "order": 0, "profile_path": NSNull()]]
        json["episodes"] = episodes
        let saison = try decoder(SaisonDetail.self, json)
        #expect(saison.episodes[0].invites?.map(\.nom) == ["Invité"])
        // Sans `guest_stars` (la fixture d'origine), l'épisode se lit comme avant.
        #expect(saison.episodes.dropFirst().allSatisfy { $0.invites == nil })
    }

    @Test func dejaVuDansTesTitresSaufCeluiQuOnRegarde() throws {
        let filmographie = try decoder(Filmographie.self, try JSONSerialization.jsonObject(with: Fixture.donnees("person_combined_credits")))
        let tous = Set((filmographie.roles + filmographie.realisations).map(\.reference))
        let actuel = ReferenceTitre(type: .film, tmdbID: 13)
        let vus: Set<ReferenceTitre> = [actuel, ReferenceTitre(type: .film, tmdbID: 591), ReferenceTitre(type: .film, tmdbID: 497),
                                        ReferenceTitre(type: .film, tmdbID: 999_999)]
        let deja = QuiEstCe.dejaVu(dans: filmographie, vus: vus, sauf: actuel)
        // Les plus connus d'abord (votes : 497 > 591), sans le film en cours ni ce qui n'est pas dans sa filmographie.
        #expect(deja.map(\.tmdbID) == [497, 591].filter { tous.contains(ReferenceTitre(type: .film, tmdbID: $0)) })
    }

    @Test func leRoleVideNeSAffichePas() {
        #expect(QuiEstCe.role(PersonneCasting(id: 1, nom: "A", personnage: "  ", cheminPortrait: nil)) == nil)
        #expect(QuiEstCe.role(PersonneCasting(id: 1, nom: "A", personnage: "Ripley", cheminPortrait: nil)) == "Ripley")
    }
}
