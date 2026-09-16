import SeanceKit
import SwiftUI

/// Identité visuelle de Séance (UX-17) : fond sombre, accent orange braise.
enum Theme {
    static let accent = Color("AccentColor")
    static let accentClair = Color(red: 1, green: 0.635, blue: 0.29)
    static let fond = Color(red: 0.04, green: 0.04, blue: 0.055)
    static let surface = Color.white.opacity(0.08)

    static let degradeAccent = LinearGradient(colors: [accent, accentClair], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// UX-04 : vert dès 70 %, jaune de 40 à 69 %, rouge en dessous.
    static func couleurNote(_ pourcentage: Int) -> Color {
        switch pourcentage {
        case 70...: Color(red: 0.13, green: 0.82, blue: 0.48)
        case 40..<70: Color(red: 0.89, green: 0.76, blue: 0.23)
        default: Color(red: 0.9, green: 0.28, blue: 0.3)
        }
    }
}

/// Adresses des images TMDB.
enum ImageTMDB {
    enum Taille: String {
        case affiche = "w342"
        case afficheGrande = "w500"
        case fond = "w780"
        case fondGrand = "w1280"
        case portrait = "w185"
        case logo = "w92"
    }

    static func url(_ chemin: String?, _ taille: Taille) -> URL? {
        guard let chemin, !chemin.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(taille.rawValue)\(chemin)")
    }
}

extension TitreResume {
    var pourcentageNote: Int { Int((noteMoyenne * 10).rounded()) }
}
