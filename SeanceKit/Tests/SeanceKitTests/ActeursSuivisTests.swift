import Foundation
import Testing
@testable import SeanceKit

@Suite("Acteurs suivis")
struct ActeursSuivisTests {
    private let reglages = ReglagesAlertes()

    private func filmographie(_ roles: String) throws -> Filmographie {
        try JSONDecoder().decode(Filmographie.self, from: Data(#"{"cast": [\#(roles)], "crew": []}"#.utf8))
    }

    private func role(_ id: Int, _ titre: String, date: String?, personnage: String = "John", type: String = "movie") -> String {
        let cleDate = type == "movie" ? "release_date" : "first_air_date"
        let cleTitre = type == "movie" ? "title" : "name"
        return #"{"id": \#(id), "media_type": "\#(type)", "\#(cleTitre)": "\#(titre)", "character": "\#(personnage)", "genre_ids": [28], "\#(cleDate)": \#(date.map { "\"\($0)\"" } ?? "null")}"#
    }

    @Test func nouveauFilmDUnActeurSuivi() throws {
        let maintenant = Date.suisse("2026-09-17 10:00")
        let avant = try filmographie(role(245_891, "John Wick", date: "2014-10-24"))

        // Première vérification : la filmographie est mémorisée, rien n'est signalé.
        let premiere = PlanificateurAlertes.nouveauxFilms(acteur: "Keanu Reeves", connus: nil, filmographie: avant,
                                                          maintenant: maintenant, reglages: reglages)
        #expect(premiere.alertes.isEmpty)
        #expect(premiere.connus == [245_891])

        let apres = try filmographie([
            role(245_891, "John Wick", date: "2014-10-24"),
            role(1, "Ballerina 2", date: "2027-06-04"),
            role(2, "Projet sans date", date: nil),
            role(3, "Vieux film retrouvé", date: "1999-01-01"),
            role(4, "Documentaire", date: "2027-01-01", personnage: "Himself"),
            role(5, "Une série", date: "2027-01-01", type: "tv"),
        ].joined(separator: ","))
        let suivante = PlanificateurAlertes.nouveauxFilms(acteur: "Keanu Reeves", connus: premiere.connus, filmographie: apres,
                                                          maintenant: maintenant, reglages: reglages)
        // Seuls les films à venir ou sans date, où il joue un rôle.
        #expect(suivante.alertes.map(\.reference.tmdbID) == [1, 2])
        #expect(suivante.alertes.allSatisfy { $0.date == Date.suisse("2026-09-17 18:00") && $0.motif.ponctuelle })
        #expect(suivante.connus == [245_891, 1, 2, 3, 4])
        #expect(PlanificateurAlertes.texte(suivante.alertes[0].motif, fuseau: .suisse) == "Nouveau film avec Keanu Reeves, sortie prévue le 4 juin 2027")
        #expect(PlanificateurAlertes.texte(suivante.alertes[1].motif, fuseau: .suisse) == "Nouveau film annoncé avec Keanu Reeves")

        // Les sorties de films désactivées : rien, mais la filmographie reste mémorisée.
        var sansSorties = reglages
        sansSorties.typesActifs.remove(.sortieFilm)
        let coupee = PlanificateurAlertes.nouveauxFilms(acteur: "Keanu Reeves", connus: premiere.connus, filmographie: apres,
                                                        maintenant: maintenant, reglages: sansSorties)
        #expect(coupee.alertes.isEmpty && coupee.connus.contains(1))
    }

    @Test func sauvegardeDesActeursSuivis() throws {
        let date = Date.suisse("2026-09-17 21:00")
        var existante = Sauvegarde(creeeLe: date)
        existante.acteursSuivis = [Sauvegarde.ActeurSuivi(personneID: 6384, nom: "Keanu Reeves", cheminPortrait: nil, suiviLe: date)]
        var importee = Sauvegarde(creeeLe: date)
        importee.acteursSuivis = [
            Sauvegarde.ActeurSuivi(personneID: 6384, nom: "Keanu Reeves", cheminPortrait: "/k.jpg", suiviLe: date),
            Sauvegarde.ActeurSuivi(personneID: 976, nom: "Jason Statham", cheminPortrait: nil, suiviLe: date),
        ]
        #expect(PlanImport(importee: importee, existante: existante).acteursSuivis.map(\.personneID) == [976])
        #expect(try Sauvegarde.decoder(try importee.encoder()) == importee)

        // Un fichier d'une version précédente, sans la clé, se lit toujours.
        var ancienne = try JSONSerialization.jsonObject(with: try Sauvegarde(creeeLe: date).encoder()) as! [String: Any]
        ancienne.removeValue(forKey: "acteursSuivis")
        let relue = try Sauvegarde.decoder(try JSONSerialization.data(withJSONObject: ancienne))
        #expect(relue.acteursSuivis == nil)
    }
}
