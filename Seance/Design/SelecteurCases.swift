import SwiftUI

/// Le sélecteur de Séance : des cases de même largeur, l'active en dégradé orange à texte noir, les autres sur la surface
/// du thème. Né dans Explorer (Toutes, Streaming, NAS, Télé), il sert partout où l'on choisit **ce que la page montre** :
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

    var body: some View {
        let avecSymboles = cases.contains { $0.symbole != nil }
        HStack(spacing: 8) {
            ForEach(cases) { element in
                let active = selection == element.valeur
                Button {
                    withAnimation(.snappy) { selection = element.valeur }
                } label: {
                    VStack(spacing: 3) {
                        if let symbole = element.symbole { Image(systemName: symbole).font(.subheadline.weight(.semibold)) }
                        Text(element.nom).font(.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity)
                    .frame(height: avecSymboles ? 50 : 40)
                    .foregroundStyle(active ? Color.black : Color.primary)
                    .background(active ? AnyShapeStyle(Theme.degradeAccent) : AnyShapeStyle(Theme.surface),
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .texteContenu()
                }
                .buttonStyle(.plain)
                .disabled(!element.disponible)
                .opacity(element.disponible ? 1 : 0.4)
                .help(element.disponible ? "" : (element.aide ?? ""))
                .accessibilityLabel(element.nom)
                .accessibilityHint(element.disponible ? "" : (element.aide ?? ""))
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
    }
}
