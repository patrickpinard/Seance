import SeanceKit
import SwiftUI
import UIKit

/// Identité visuelle de Séance (UX-17, charte 8.0) : sombre seulement, un orange réservé à ce qui se touche.
/// Toutes les couleurs de l'app viennent d'ici — aucune en dur dans les vues (`CharteTests` y veille).
enum Theme {
    /// L'orange de ce qui réagit au toucher : bouton principal, liens, onglet choisi, interrupteurs.
    static let accent = Color("AccentColor")
    /// Le même orange pour un texte ou une icône qui se touche (lien, « Tout voir ») : un peu plus clair, lisible sur le fond.
    static let accentClair = Color(red: 1, green: 0.635, blue: 0.29)
    /// Derrière tout.
    static let fond = Color(red: 0.043, green: 0.043, blue: 0.063)
    /// Le fond des cartes, des lignes et des puces : translucide, pour s'empiler.
    static let surface = Color.white.opacity(0.08)
    /// Les boutons secondaires, posés sur le fond ou sur une surface.
    static let eleve = Color(red: 0.137, green: 0.137, blue: 0.169)
    /// Filets, contours et séparateurs.
    static let trait = Color.white.opacity(0.10)
    /// Texte : titres et contenu, puis faits et légendes, puis ce qui est désactivé.
    static let texte = Color.white
    static let texte2 = Color(red: 0.63, green: 0.63, blue: 0.67)
    static let texte3 = Color(red: 0.42, green: 0.42, blue: 0.46)
    /// « Vu », « en ordre ».
    static let vert = Color(red: 0.204, green: 0.78, blue: 0.349)
    /// « Retirer », « en direct ».
    static let rouge = Color(red: 1, green: 0.271, blue: 0.227)
    /// À surveiller (un réglage à compléter).
    static let attention = Color(red: 1, green: 0.624, blue: 0.039)

    /// Le fond du bouton principal, toujours le même : le texte posé dessus est noir.
    static let degradeAccent = LinearGradient(colors: [accent, accentClair], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Les ronds de « Qui regarde ce soir ? » (maquette 8.0, n° 1) : une couleur par personne après la première, orange.
    static let profils: [Color] = [Color(red: 0.36, green: 0.55, blue: 1), Color(red: 0.3, green: 0.78, blue: 0.55), Color(red: 0.72, green: 0.5, blue: 1)]

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

extension View {
    /// Pour une carte dont le fond est une photo assombrie : son texte suit la taille choisie dans iOS jusqu'à un
    /// plafond — au-delà, une image 16/9 ne peut plus tout loger.
    func surImage() -> some View {
        dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// Pour une tuile ou une puce de largeur comptée (jours, sources) : même plafond.
    func texteContenu() -> some View {
        dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}
