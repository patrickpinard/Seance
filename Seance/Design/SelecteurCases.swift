import SwiftUI

/// Le sélecteur de Séance : des cases de même largeur ; charte 8.0 : l'active en blanc à texte noir, comme toute pastille
/// choisie, les autres sur la surface du thème. Né dans Explorer (Toutes, Streaming, NAS, TV), il sert partout où l'on choisit **ce que la page montre** :
/// onglets de Mes listes, rayons du NAS, Films / Séries. Le contrôle segmenté d'iOS reste réservé aux formulaires de
/// réglage. Voir `Documentation/Charte graphique.md`.
struct SelecteurCases<Valeur: Hashable>: View {
    struct Case: Identifiable {
        let valeur: Valeur
        let nom: String
        /// Avec symbole : l'icône au-dessus du nom, case de 50 points. Sans : le nom seul, 40 points.
        var symbole: String?
        var disponible = true
        /// Dit pourquoi la case est grisée.
        var aide: String?

        var id: Valeur { valeur }
    }

    @Binding var selection: Valeur
    let cases: [Case]

    /// 8.4 (bilan du 28.09.2026) : un seul sélecteur dans toute l'app — des pastilles (`PuceCharte`), la choisie en
    /// blanc ; celles qui ne tiennent pas défilent. Les cases à icônes de Mes listes, d'Explorer et du NAS en étaient
    /// une troisième forme.
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(cases) { element in
                    let active = selection == element.valeur
                    Button {
                        withAnimation(.snappy) { selection = element.valeur }
                    } label: {
                        PuceCharte(texte: element.nom, actif: active, symbole: element.symbole)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: active)
                    .disabled(!element.disponible)
                    .opacity(element.disponible ? 1 : 0.4)
                    .help(element.disponible ? "" : (element.aide ?? ""))
                    .accessibilityLabel(element.nom)
                    .accessibilityHint(element.disponible ? "" : (element.aide ?? ""))
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
        }
        .scrollClipDisabled()
    }
}
