import SwiftUI

/// Le choix grille ou liste, le même partout (Mes listes, Explorer, filmographie d'un acteur). Les icônes restent
/// petites, mais chacune se touche sur 44 points : dessinées à leur taille, elles faisaient 15 points de côté.
struct BasculeGrilleListe: View {
    @Binding var enGrille: Bool

    var body: some View {
        HStack(spacing: 0) {
            bouton("Grille", symbole: "square.grid.2x2.fill", choisi: enGrille) { enGrille = true }
            bouton("Liste", symbole: "list.bullet", choisi: !enGrille) { enGrille = false }
        }
    }

    private func bouton(_ nom: String, symbole: String, choisi: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbole)
                .foregroundStyle(choisi ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                .zoneDeToucher(largeur: 38)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(nom)
        .accessibilityAddTraits(choisi ? .isSelected : [])
    }
}

extension View {
    /// Une petite icône ou un lien d'une ligne garde son dessin, mais répond sur 44 points de haut.
    func zoneDeToucher(largeur: CGFloat? = nil) -> some View {
        frame(minWidth: largeur, minHeight: 44)
            .contentShape(Rectangle())
    }
}
