import Foundation
import SeanceKit
import SwiftUI
import UIKit
import WidgetKit

// Partagé entre le widget et l'app : l'app affiche les mêmes vues dans son aperçu de test.

enum CouleursWidget {
    static let accent = Color(red: 1, green: 0x6A / 255, blue: 0x3D / 255)
    static let accentClair = Color(red: 1, green: 0.635, blue: 0.29)
    static let fond = Color(red: 0.075, green: 0.065, blue: 0.085)
    static let degrade = LinearGradient(colors: [accent, accentClair], startPoint: .topLeading, endPoint: .bottomTrailing)
}

enum LiensWidget {
    static let ceSoir = URL(string: "seance://cesoir")!
    static let aVenir = URL(string: "seance://avenir")!

    static func fiche(_ reference: ReferenceTitre) -> URL {
        URL(string: "seance://\(reference.type.rawValue)/\(reference.tmdbID)")!
    }
}

struct TitreWidget: Hashable, Identifiable, Sendable {
    let reference: ReferenceTitre
    let titre: String
    let detail: String
    /// Vignette JPEG réduite : les widgets ne chargent pas d'images eux-mêmes à l'affichage.
    var affiche: Data?

    var id: ReferenceTitre { reference }
}

struct EpisodeWidget: Hashable, Identifiable, Sendable {
    let serieID: Int
    let nom: String
    let saison: Int
    let numero: Int
    let titreEpisode: String?
    let dureeMinutes: Int
    var affiche: Data?

    var id: Int { serieID }
    var reference: ReferenceTitre { ReferenceTitre(type: .serie, tmdbID: serieID) }
    var code: String { NumeroEpisode(saison: saison, episode: numero).description }
}

struct EcheanceWidget: Hashable, Identifiable, Sendable {
    let reference: ReferenceTitre
    let titre: String
    let libelle: String
    let date: Date
    let nature: EcheancePrevue.Nature
    var affiche: Data?

    var id: String { "\(reference.type.rawValue)-\(reference.tmdbID)-\(Int(date.timeIntervalSince1970))" }

    var symbole: String {
        switch nature {
        case .episode: "play.tv"
        case .saison: "sparkles.tv"
        case .sortie: "film"
        case .tele: "tv"
        }
    }

    /// « Aujourd'hui », « Ce soir 20:55 », « Demain », « Dans 3 j ».
    func compteARebours(depuis maintenant: Date) -> String {
        let calendrier = Calendar.current
        let jours = calendrier.dateComponents([.day], from: calendrier.startOfDay(for: maintenant), to: calendrier.startOfDay(for: date)).day ?? 0
        switch jours {
        case ..<1:
            return nature == .tele ? date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_CH"))) : "Aujourd'hui"
        case 1: return "Demain"
        default: return "Dans \(jours) j"
        }
    }
}

struct EntreeSoiree: TimelineEntry {
    let date: Date
    let titres: [TitreWidget]

    static let exemple = EntreeSoiree(date: .now, titres: [
        TitreWidget(reference: .init(type: .serie, tmdbID: 108978), titre: "Reacher", detail: "S02E06 à regarder"),
        TitreWidget(reference: .init(type: .film, tmdbID: 324552), titre: "John Wick : Chapitre 2", detail: "Film · 2 h 02"),
    ])
}

struct EntreeEpisodes: TimelineEntry {
    let date: Date
    let episodes: [EpisodeWidget]

    static let exemple = EntreeEpisodes(date: .now, episodes: [
        EpisodeWidget(serieID: 108978, nom: "Reacher", saison: 2, numero: 6, titreEpisode: "Le Cercle", dureeMinutes: 50),
        EpisodeWidget(serieID: 129552, nom: "The Night Agent", saison: 2, numero: 3, titreEpisode: "Dette", dureeMinutes: 48),
    ])
}

struct EntreeAVenir: TimelineEntry {
    let date: Date
    let echeances: [EcheanceWidget]

    static let exemple = EntreeAVenir(date: .now, echeances: [
        EcheanceWidget(reference: .init(type: .film, tmdbID: 245891), titre: "John Wick", libelle: "À la télé sur RTS 1",
                       date: .now.addingTimeInterval(3 * 3600), nature: .tele),
        EcheanceWidget(reference: .init(type: .serie, tmdbID: 108978), titre: "Reacher", libelle: "Saison 4, épisode 1",
                       date: .now.addingTimeInterval(86_400), nature: .saison),
        EcheanceWidget(reference: .init(type: .film, tmdbID: 1), titre: "Ballerina", libelle: "Sortie au cinéma",
                       date: .now.addingTimeInterval(5 * 86_400), nature: .sortie),
    ])
}
