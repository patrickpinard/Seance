import SeanceKit
import SwiftUI
import UIKit

/// Identité visuelle de Séance (UX-17) : accent orange braise, sur fond sombre ou clair au choix (Réglages › Apparence).
/// Les couleurs de page suivent l'apparence ; les grandes cartes-images restent sombres (`.surImage()`), pour que
/// leur texte blanc et leur orange vif se lisent sur la photo quelle que soit l'apparence.
enum Theme {
    static let accent = Color("AccentColor")
    /// L'orange des textes et des icônes : vif sur fond sombre, plus soutenu sur fond clair, où il garde un contraste de
    /// 5,3:1 sur le fond et 4,6:1 sur une carte (le seuil de lisibilité est 4,5:1).
    static let accentClair = dynamique(sombre: UIColor(red: 1, green: 0.635, blue: 0.29, alpha: 1),
                                       clair: UIColor(red: 0.68, green: 0.27, blue: 0.02, alpha: 1))
    static let fond = dynamique(sombre: UIColor(red: 0.04, green: 0.04, blue: 0.055, alpha: 1),
                                clair: UIColor(red: 0.965, green: 0.96, blue: 0.955, alpha: 1))
    /// Le fond des cartes et des puces : translucide, pour s'empiler (une puce dans une carte reste visible).
    static let surface = dynamique(sombre: UIColor.white.withAlphaComponent(0.08), clair: UIColor.black.withAlphaComponent(0.06))
    /// Filets, contours et séparateurs posés sur le fond de la page.
    static let trait = dynamique(sombre: UIColor.white.withAlphaComponent(0.12), clair: UIColor.black.withAlphaComponent(0.12))

    /// Le dégradé des boutons principaux, toujours le même : le texte posé dessus est noir.
    static let degradeAccent = LinearGradient(colors: [accent, Color(red: 1, green: 0.635, blue: 0.29)], startPoint: .topLeading, endPoint: .bottomTrailing)

    private static func dynamique(sombre: UIColor, clair: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? sombre : clair })
    }

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
        /// Image d'un épisode.
        case vignette = "w300"
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

/// Sombre (d'origine), clair, ou comme le système : Réglages › Apparence.
enum Apparence: String, CaseIterable, Identifiable {
    case sombre, clair, systeme

    static let cle = "apparence"

    var id: String { rawValue }

    var nom: String {
        switch self {
        case .sombre: "Sombre"
        case .clair: "Clair"
        case .systeme: "Automatique"
        }
    }

    var symbole: String {
        switch self {
        case .sombre: "moon.fill"
        case .clair: "sun.max.fill"
        case .systeme: "circle.lefthalf.filled"
        }
    }

    /// `nil` : l'app suit le réglage de l'appareil.
    var schema: ColorScheme? {
        switch self {
        case .sombre: .dark
        case .clair: .light
        case .systeme: nil
        }
    }

    static func lire(_ brut: String) -> Apparence {
        Apparence(rawValue: brut) ?? .sombre
    }
}

extension View {
    /// Pour une carte dont le fond est une photo assombrie : ses couleurs restent celles du mode sombre, et son texte
    /// suit la taille choisie dans iOS jusqu'à un plafond — au-delà, une image 16/9 ne peut plus tout loger.
    func surImage() -> some View {
        environment(\.colorScheme, .dark)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// Pour une tuile ou une puce de largeur comptée (jours, sources) : même plafond.
    func texteContenu() -> some View {
        dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}
