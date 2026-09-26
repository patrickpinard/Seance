import SwiftUI

/// Des sections qu'on ouvre et qu'on ferme (8.2.8, demande de Patrick) : par genre, par année, par ajout, la liste des
/// sections se parcourt d'un coup d'œil, et l'on n'ouvre que celles qu'on cherche.
struct SectionsRepliables {
    /// Ouvertes au départ, ou fermées (par genre : une liste de genres à ouvrir).
    var ouvertesParDefaut = true
    /// Les sections dont on a changé l'état, par rapport au départ.
    var basculees: Set<String> = []

    func ouverte(_ titre: String) -> Bool {
        basculees.contains(titre) ? !ouvertesParDefaut : ouvertesParDefaut
    }

    mutating func basculer(_ titre: String) {
        if basculees.contains(titre) { basculees.remove(titre) } else { basculees.insert(titre) }
    }

    /// Tout ouvrir ou tout fermer.
    mutating func toutes(ouvertes: Bool, titres: [String]) {
        basculees = ouvertes == ouvertesParDefaut ? [] : Set(titres)
    }

    func toutesOuvertes(_ titres: [String]) -> Bool {
        titres.allSatisfy(ouverte)
    }
}

/// L'en-tête d'une section repliable : son nom, son nombre de titres, le chevron qui tourne.
struct EnTeteRepliable: View {
    let titre: String
    let detail: String
    let ouverte: Bool
    let basculer: () -> Void

    var body: some View {
        Button {
            withAnimation(.snappy) { basculer() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .rotationEffect(.degrees(ouverte ? 90 : 0))
                Text(titre).font(.title3.weight(.bold)).foregroundStyle(Theme.texte)
                Spacer()
                Text(detail).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(titre), \(detail)")
        .accessibilityValue(ouverte ? "ouverte" : "fermée")
        .accessibilityHint(ouverte ? "Ferme la section" : "Ouvre la section")
        .accessibilityAddTraits(.isHeader)
    }
}
