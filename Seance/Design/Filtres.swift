import SwiftUI

/// Dispose des puces en lignes qui reviennent à la ligne, comme dans la maquette des filtres.
struct Flux: Layout {
    var espacement: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let largeurMax = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var hauteurLigne: CGFloat = 0
        var largeur: CGFloat = 0
        for vue in subviews {
            let taille = vue.sizeThatFits(.unspecified)
            if x > 0, x + taille.width > largeurMax {
                y += hauteurLigne + espacement
                x = 0
                hauteurLigne = 0
            }
            x += taille.width + espacement
            largeur = max(largeur, x - espacement)
            hauteurLigne = max(hauteurLigne, taille.height)
        }
        return CGSize(width: min(largeur, largeurMax), height: y + hauteurLigne)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var hauteurLigne: CGFloat = 0
        for vue in subviews {
            let taille = vue.sizeThatFits(.unspecified)
            if x > bounds.minX, x + taille.width > bounds.maxX {
                y += hauteurLigne + espacement
                x = bounds.minX
                hauteurLigne = 0
            }
            vue.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(taille))
            x += taille.width + espacement
            hauteurLigne = max(hauteurLigne, taille.height)
        }
    }
}

/// Puce de critère : neutre, retenue (coche orange) ou exclue (barrée, contour rouge).
struct PuceCritere: View {
    enum Etat { case neutre, retenu, exclu }

    let libelle: String
    var etat: Etat = .neutre
    var action: () -> Void = {}
    var appuiLong: (() -> Void)?

    var body: some View {
        HStack(spacing: 5) {
            if etat == .retenu {
                Image(systemName: "checkmark").font(.caption.weight(.bold))
            }
            Text(libelle)
                .strikethrough(etat == .exclu)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 13)
        .frame(height: 34)
        .foregroundStyle(etat == .retenu ? Color.black : etat == .exclu ? Color(red: 1, green: 0.45, blue: 0.45) : .primary)
        .background {
            switch etat {
            case .retenu: Capsule().fill(Theme.degradeAccent)
            case .exclu: Capsule().fill(Color.red.opacity(0.12)).overlay(Capsule().strokeBorder(Color.red.opacity(0.6)))
            case .neutre: Capsule().fill(Theme.surface)
            }
        }
        .contentShape(Capsule())
        .onTapGesture(perform: action)
        .onLongPressGesture(minimumDuration: 0.4) { appuiLong?() }
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(etat == .retenu ? "retenu" : etat == .exclu ? "exclu" : "")
    }
}

/// Puce d'un filtre actif, avec sa croix (EF-54).
struct PuceActive: View {
    let libelle: String
    var portrait: URL?
    let retirer: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if let portrait {
                ImageDistante(url: portrait, coins: 13)
                    .frame(width: 26, height: 26)
            }
            Text(libelle).font(.subheadline.weight(.semibold)).lineLimit(1)
            Button(action: retirer) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .frame(width: 22, height: 22)
                    .background(Theme.trait, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retirer \(libelle)")
        }
        .padding(.leading, portrait == nil ? 13 : 4)
        .padding(.trailing, 6)
        .frame(height: 36)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.trait))
    }
}

/// Curseur à deux poignées pour une période en années (maquette Explorer).
struct CurseurIntervalle: View {
    @Binding var debut: Int
    @Binding var fin: Int
    let bornes: ClosedRange<Int>

    private let diametre: CGFloat = 28

    var body: some View {
        GeometryReader { geometrie in
            let largeur = geometrie.size.width - diametre
            let xDebut = position(debut, largeur)
            let xFin = position(fin, largeur)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surface).frame(height: 4)
                    .padding(.horizontal, diametre / 2)
                Capsule().fill(Theme.degradeAccent)
                    .frame(width: max(0, xFin - xDebut), height: 4)
                    .offset(x: xDebut + diametre / 2)
                poignee
                    .offset(x: xDebut)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("curseur")).onChanged { geste in
                        debut = min(valeur(geste.location.x - diametre / 2, largeur), fin)
                    })
                    .accessibilityLabel("Début")
                    .accessibilityValue(String(debut))
                    .accessibilityAdjustableAction { sens in
                        debut = sens == .increment ? min(debut + 1, fin) : max(debut - 1, bornes.lowerBound)
                    }
                poignee
                    .offset(x: xFin)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("curseur")).onChanged { geste in
                        fin = max(valeur(geste.location.x - diametre / 2, largeur), debut)
                    })
                    .accessibilityLabel("Fin")
                    .accessibilityValue(String(fin))
                    .accessibilityAdjustableAction { sens in
                        fin = sens == .increment ? min(fin + 1, bornes.upperBound) : max(fin - 1, debut)
                    }
            }
            .frame(maxHeight: .infinity)
            .coordinateSpace(.named("curseur"))
        }
        .frame(height: 36)
    }

    private var poignee: some View {
        Circle().fill(.white)
            .frame(width: diametre, height: diametre)
            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
    }

    private func position(_ annee: Int, _ largeur: CGFloat) -> CGFloat {
        let etendue = CGFloat(bornes.upperBound - bornes.lowerBound)
        return largeur * CGFloat(annee - bornes.lowerBound) / max(etendue, 1)
    }

    private func valeur(_ x: CGFloat, _ largeur: CGFloat) -> Int {
        let rapport = min(max(x / max(largeur, 1), 0), 1)
        return bornes.lowerBound + Int((rapport * CGFloat(bornes.upperBound - bornes.lowerBound)).rounded())
    }
}
