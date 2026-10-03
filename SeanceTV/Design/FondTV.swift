import SwiftUI

/// L'image de fond des pages de la TV : une grande image d'un de tes titres — ta soirée d'abord, sinon ton NAS, sinon le
/// programme TV —, floutée et assombrie pour que le texte reste lisible, fondue dans le noir de Séance vers le bas.
/// Elle change chaque jour. Les fiches ont leur propre image ; les pages de réglage restent opaques (charte graphique).
struct FondTV: View {
    @Environment(EtatTV.self) private var etat

    /// Sans image (8.8, Patrick) : les Réglages et les Préférences ont un fond sombre et calme — l'image floutée du
    /// jour, une affiche rouge vif qu'on ne reconnaissait pas, gênait la lecture des réglages.
    var calme = false

    /// 8.10 : l'image du jour est choisie et floutée une seule fois, au lancement (`FondDuJour`, `EtatTV.fond`) ; chaque
    /// onglet relisait le magasin et floutait l'image en direct.
    var body: some View {
        ZStack {
            Theme.fond
            if calme {
                RadialGradient(colors: [Theme.texte.opacity(0.07), .clear], center: .topLeading, startRadius: 0, endRadius: 1600)
            } else if let fond = etat.fond {
                Image(uiImage: fond)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .opacity(0.7)
                    .overlay {
                        LinearGradient(stops: [.init(color: Theme.fond.opacity(0.15), location: 0),
                                               .init(color: Theme.fond.opacity(0.55), location: 0.6),
                                               .init(color: Theme.fond, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.6), value: etat.fond != nil)
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
