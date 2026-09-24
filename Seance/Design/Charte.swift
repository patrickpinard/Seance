import SwiftUI

// Charte 8.0 : les composants communs à toutes les pages, sur l'iPhone, l'iPad et le Mac. Ils ne changent que de
// taille d'un appareil à l'autre ; la TV a les siens, dessinés de la même façon (`SeanceTV/Design`).

/// Choisir ce que la page montre, en pastilles : « Tout · Streaming · TV · NAS », « Films · Séries · Documentaires ».
/// La pastille choisie est blanche, les autres sur la surface ; une rangée trop longue défile.
struct SelecteurPuces<Valeur: Hashable>: View {
    struct Choix: Identifiable {
        let valeur: Valeur
        let nom: String
        var id: String { nom }
    }

    @Binding var selection: Valeur
    let choix: [Choix]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(choix) { choix in
                    let actif = choix.valeur == selection
                    Button {
                        withAnimation(.snappy) { selection = choix.valeur }
                    } label: {
                        PuceCharte(texte: choix.nom, actif: actif)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(actif ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Une pastille : blanche quand elle est choisie, sur la surface sinon. Sa zone de toucher fait 44 points de haut.
struct PuceCharte: View {
    let texte: String
    var actif = false
    var symbole: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbole { Image(systemName: symbole).font(.footnote.weight(.semibold)) }
            Text(texte).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 34)
        .foregroundStyle(actif ? Color.black : Theme.texte)
        .background(actif ? AnyShapeStyle(Theme.texte) : AnyShapeStyle(Theme.surface), in: Capsule())
        .overlay(Capsule().strokeBorder(actif ? Color.clear : Theme.trait))
        .zoneDeToucher()
        .texteContenu()
    }
}

/// Le bouton principal d'un écran — un seul par écran —, qui dit ce qu'il fait : « Regarder sur Prime Video ».
struct StyleBoutonPrincipal: ButtonStyle {
    var pleineLargeur = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.black)
            .padding(.horizontal, 20)
            .frame(maxWidth: pleineLargeur ? .infinity : nil, minHeight: 50)
            .background(Theme.degradeAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Un bouton secondaire : gris, texte blanc ; `destructif` l'écrit en rouge.
struct StyleBoutonSecondaire: ButtonStyle {
    var pleineLargeur = false
    var destructif = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(destructif ? Theme.rouge : Theme.texte)
            .padding(.horizontal, 16)
            .frame(maxWidth: pleineLargeur ? .infinity : nil, minHeight: 44)
            .background(Theme.eleve, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Un rond gris de 44 points, pour une action qui tient dans une icône (⋯, pouces, étoile).
struct StyleBoutonRond: ButtonStyle {
    var choisi = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(choisi ? Color.black : Theme.texte)
            .frame(width: 44, height: 44)
            .background(choisi ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.eleve), in: Circle())
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == StyleBoutonPrincipal {
    static var principal: StyleBoutonPrincipal { StyleBoutonPrincipal() }
}

extension ButtonStyle where Self == StyleBoutonSecondaire {
    static var secondaire: StyleBoutonSecondaire { StyleBoutonSecondaire() }
}

private struct DansRegarderCle: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Vrai pour une page montrée dans Regarder (8.0) : c'est Regarder qui donne son titre à la barre.
    var dansRegarder: Bool {
        get { self[DansRegarderCle.self] }
        set { self[DansRegarderCle.self] = newValue }
    }
}

extension View {
    /// Le titre d'une page, sauf quand elle est montrée dans Regarder : la barre y garde « Regarder ».
    func titrePage(_ titre: String) -> some View {
        modifier(TitrePage(titre: titre))
    }
}

private struct TitrePage: ViewModifier {
    let titre: String
    @Environment(\.dansRegarder) private var dansRegarder

    func body(content: Content) -> some View {
        if dansRegarder { content } else { content.navigationTitle(titre) }
    }
}

/// L'en-tête d'une section : un titre, et « Tout voir » quand la section s'ouvre en grand. Pas de phrase dessous.
struct EnTeteSection<Destination: Hashable>: View {
    let titre: String
    var destination: Destination?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(titre)
                .font(.title3.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let destination {
                NavigationLink(value: destination) {
                    Text("Tout voir").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentClair)
                }
                .buttonStyle(.plain)
                .zoneDeToucher()
            }
        }
    }
}

extension EnTeteSection where Destination == Never {
    init(_ titre: String) {
        self.titre = titre
        self.destination = nil
    }
}
