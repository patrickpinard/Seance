import SwiftUI

/// Un écran sans contenu dit ce qu'il montrera et comment le remplir : une icône, un titre, une phrase, et l'action
/// qui y mène quand il y en a une. Jamais une page noire avec une ligne grise en haut.
struct EtatVide: View {
    let symbole: String
    let titre: String
    let message: String
    var libelleAction: String?
    var symboleAction = "sparkle.magnifyingglass"
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbole)
                .font(.largeTitle).imageScale(.large)
                .foregroundStyle(Theme.degradeAccent)
                .accessibilityHidden(true)
            Text(titre)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let libelleAction, let action {
                Button(action: action) {
                    Label(libelleAction, systemImage: symboleAction)
                        .font(.headline)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 46)
                        .background(Theme.degradeAccent, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
