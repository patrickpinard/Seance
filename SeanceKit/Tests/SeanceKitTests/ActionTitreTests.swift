import Foundation
import Testing
@testable import SeanceKit

@Suite("Le menu d'un titre, le même partout")
struct ActionTitreTests {
    @Test func unFilmPasEncoreVu() {
        let menu = ActionTitre.menu(.film, etat: .init())
        #expect(menu.map { $0.libelle(.film) } == [
            "Regarder", "Voir la fiche", "Ajouter à Ma liste", "Vu aujourd'hui", "Déjà vu avant", "Ce soir", "Un autre soir…",
            "Pas intéressé pour l'instant", "J'aime", "Je n'aime pas",
        ])
    }

    @Test func uneSerieDejaDansMaListeEtPrevueCeSoir() {
        let etat = ActionTitre.Etat(dansMaListe: true, prevuCeSoir: true)
        let menu = ActionTitre.menu(.serie, etat: etat)
        #expect(!menu.contains(.aVoir) && !menu.contains(.vuAujourdhui) && !menu.contains(.ceSoir))
        #expect(ActionTitre.dejaVuAvant.libelle(.serie) == "Toute la série déjà vue avant")
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

/// Même règle pour ce que montrent les pages (bilan du 30.09.2026) : chaque commande d'une page de l'iPhone et de l'iPad
/// existe aussi sur l'Apple TV. Le test lit les sources des deux interfaces et y cherche chaque commande, par ses mots
/// ou par l'état commun qu'elle règle.
@Suite("Les pages de l'iPhone et celles de la TV")
struct PariteDesPagesTests {
    struct Commande: CustomTestStringConvertible, Sendable {
        let nom: String
        /// Ce qui la trahit dans les sources de l'iPhone, puis dans celles de la TV.
        let iphone: String
        let tv: String
        var testDescription: String { nom }
    }

    static let commandes: [Commande] = [
        .init(nom: "Accueil : Lecture et Plus d'infos", iphone: "\"Plus d'infos\"", tv: "\"Plus d'infos\""),
        .init(nom: "Accueil : Pas ce soir", iphone: "PasCeSoir.ecarter", tv: "PasCeSoir.ecarter"),
        .init(nom: "Accueil : Pas ce genre", iphone: "\"Pas ce genre\"", tv: "\"Pas ce genre\""),
        .init(nom: "Accueil : images et logo du titre", iphone: "visuels.charger", tv: "visuels.charger"),
        .init(nom: "Accueil : nombre de propositions", iphone: "NombrePropositions.cle", tv: "NombrePropositions.cle"),
        .init(nom: "Regarder : Autre date", iphone: "\"Autre date\"", tv: "\"Autre date\""),
        .init(nom: "Regarder : Filtres", iphone: "\"Filtres\"", tv: "\"Filtres\""),
        .init(nom: "Regarder : Films et Séries", iphone: "typesRegarder", tv: "typesRegarder"),
        .init(nom: "Mes listes : Regardable ce soir", iphone: "\"Regardable ce soir\"", tv: "\"Regardable ce soir\""),
        .init(nom: "Mes listes : tri", iphone: "TriListe", tv: "TriListe"),
        .init(nom: "Mes listes : cartes ou liste", iphone: "\"titres.enListe\"", tv: "\"titres.enListe\""),
        .init(nom: "Statistiques : ce que tu as regardé", iphone: "\"Ce que tu as regardé\"", tv: "\"Ce que tu as regardé\""),
        .init(nom: "NAS : non reconnus", iphone: "non reconnu", tv: "non reconnu"),
        .init(nom: "NAS : rangements", iphone: "\"A→Z\"", tv: "\"A→Z\""),
        .init(nom: "Réglages : à compléter", iphone: "à compléter", tv: "à compléter"),
        .init(nom: "Préférences : genres écartés", iphone: "Genres que tu as écartés", tv: "Genres que tu as écartés"),
    ]

    static func sources(_ dossier: String) throws -> String {
        let racine = PariteMenusTests.racine.appending(path: dossier)
        let fichiers = FileManager.default.enumerator(at: racine, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        return try fichiers.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }

    @Test(arguments: commandes)
    func laCommandeExisteDesDeuxCotes(_ commande: Commande) throws {
        let iphone = try Self.sources("Seance")
        let tv = try Self.sources("SeanceTV")
        #expect(iphone.contains(commande.iphone), "« \(commande.nom) » manque sur l'iPhone")
        #expect(tv.contains(commande.tv), "« \(commande.nom) » manque sur l'Apple TV")
    }
}
