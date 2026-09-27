import Foundation
import Testing
@testable import SeanceKit

@Suite("Le menu d'un titre, le même partout")
struct ActionTitreTests {
    @Test func unFilmPasEncoreVu() {
        let menu = ActionTitre.menu(.film, etat: .init())
        #expect(menu.map { $0.libelle(.film) } == [
            "Regarder", "Voir la fiche", "Ajouter à Ma liste", "Vu aujourd'hui", "Déjà vu avant", "Ce soir", "Un autre soir…",
            "Ajouter à une liste…", "Ajouter à mes favoris", "Pas intéressé pour l'instant", "J'aime", "Je n'aime pas",
        ])
    }

    @Test func uneSerieDejaDansMaListeEtPrevueCeSoir() {
        let etat = ActionTitre.Etat(dansMaListe: true, prevuCeSoir: true, favori: true)
        let menu = ActionTitre.menu(.serie, etat: etat)
        #expect(!menu.contains(.aVoir) && !menu.contains(.vuAujourdhui) && !menu.contains(.ceSoir))
        #expect(ActionTitre.dejaVuAvant.libelle(.serie) == "Toute la série déjà vue avant")
        #expect(ActionTitre.favori.libelle(.serie, etat: etat) == "Retirer de mes favoris")
    }

    @Test func leVocabulaireDeLaCharte() {
        // « Je n'aime pas », jamais « Pas pour moi » ; « Ma liste », jamais « À voir ».
        let libelles = ActionTitre.allCases.map { $0.libelle(.film) }
        #expect(libelles.contains("Je n'aime pas"))
        #expect(!libelles.contains { $0.contains("Pas pour moi") || $0.contains("À voir") })
    }
}

/// La règle de la 8.2.15 : le menu d'un titre est le même sur l'iPhone, l'iPad, le Mac et l'Apple TV. Les deux menus
/// se construisent sur `ActionTitre.menu`, et chacun traite chaque action — ce test lit leurs sources.
@Suite("Le menu de l'iPhone et celui de la TV")
struct PariteMenusTests {
    static let racine = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static let menus = [
        "Seance/Etat/ActionsRapides.swift",       // iPhone, iPad, Mac
        "SeanceTV/Design/ComposantsTV.swift",     // Apple TV
    ]

    @Test(arguments: menus)
    func chaqueMenuSuitLaListeCommune(_ chemin: String) throws {
        let source = try String(contentsOf: Self.racine.appending(path: chemin), encoding: .utf8)
        #expect(source.contains("ActionTitre.menu("), "\(chemin) ne construit pas son menu sur ActionTitre.menu")
        for action in ActionTitre.allCases {
            #expect(source.contains("case .\(action.rawValue):"), "\(chemin) ne traite pas l'action « \(action.libelle(.film)) »")
        }
    }
}
