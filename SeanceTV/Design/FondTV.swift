import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// L'image de fond des pages de la TV : une grande image d'un de tes titres — ta soirée d'abord, sinon ton NAS, sinon le
/// programme TV —, floutée et assombrie pour que le texte reste lisible, fondue dans le noir de Séance vers le bas.
/// Elle change chaque jour. Les fiches ont leur propre image ; les pages de réglage restent opaques (charte graphique).
struct FondTV: View {
    @Query private var fichiers: [FichierNAS]
    @Query(sort: \Diffusion.debut) private var diffusions: [Diffusion]
    @Query private var soirees: [SelectionSoir]
    @Query private var suivis: [Suivi]

    /// Une grande image si on en connaît une ; sinon une affiche, que le flou rend aussi belle en fond.
    private var image: URL? {
        let jour = Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0
        func duJour(_ chemins: [String]) -> String? {
            let uniques = Array(Set(chemins)).sorted()
            return uniques.isEmpty ? nil : uniques[jour % uniques.count]
        }
        if let fond = duJour(fichiers.compactMap(\.cheminFond) + diffusions.compactMap(\.cheminFond)) { return ImageTMDB.url(fond, .fondGrand) }
        let affiches = soirees.compactMap(\.cheminAffiche) + fichiers.compactMap(\.cheminAffiche) + suivis.compactMap(\.cheminAffiche)
        return duJour(affiches).flatMap { ImageTMDB.url($0, .afficheGrande) }
    }

    /// Sans image (8.8, Patrick) : les Réglages et les Préférences ont un fond sombre et calme — l'image floutée du
    /// jour, une affiche rouge vif qu'on ne reconnaissait pas, gênait la lecture des réglages.
    var calme = false

    var body: some View {
        ZStack {
            Theme.fond
            if calme {
                RadialGradient(colors: [Theme.texte.opacity(0.07), .clear], center: .topLeading, startRadius: 0, endRadius: 1600)
            } else if let image {
                ImageTV(url: image, symboleVide: "")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .blur(radius: 34)
                    .saturation(1.35)
                    .opacity(0.7)
                    .overlay {
                        LinearGradient(stops: [.init(color: Theme.fond.opacity(0.15), location: 0),
                                               .init(color: Theme.fond.opacity(0.55), location: 0.6),
                                               .init(color: Theme.fond, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    /// `focusSection()` seulement quand la section contient de quoi recevoir le focus : vide, elle arrête la télécommande.
    @ViewBuilder
    func sectionDeFocus(si active: Bool) -> some View {
        if active { focusSection() } else { self }
    }
}
