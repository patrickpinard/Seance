import SwiftUI

/// Une action que le glissement d'une carte découvre (8.6) : « Ce soir », « Terminé », « Alertes », « Retirer »…
struct ActionGlissee: Identifiable {
    let libelle: String
    let symbole: String
    let couleur: Color
    /// La dernière action du côté gauche se déclenche d'un grand glissement, comme sur une liste d'iOS.
    var destructive = false
    let action: () -> Void

    var id: String { libelle }
}

/// Glisser une grande carte pour ses actions (8.6, demande de Patrick) — les gestes qu'une liste d'iOS offre à ses
/// lignes, pour les cartes de toutes les pages en grille : vers la gauche, ce qui retire (et les alertes) ; vers la
/// droite, « Ce soir » et « Terminé ». Un petit glissement découvre les boutons ; un grand glissement vers la gauche
/// déclenche la dernière action. L'appui long propose les mêmes actions, dans les mêmes mots.
struct GlissementsCarte: ViewModifier {
    /// Découvertes en glissant vers la droite (à gauche de la carte).
    let debut: [ActionGlissee]
    /// Découvertes en glissant vers la gauche (à droite de la carte) ; la dernière est celle du grand glissement.
    let fin: [ActionGlissee]

    @State private var decalage: CGFloat = 0
    /// La position de repos : 0, ou les boutons découverts d'un côté.
    @State private var repos: CGFloat = 0
    /// Un glissement est en cours, ou vient de finir : le toucher qui l'a fait ne doit pas ouvrir la fiche (8.7, Patrick :
    /// « elle s'ouvre tout de suite sur la page du film »). Seul un toucher franc sur la carte l'ouvre.
    @State private var glisse = false
    private let largeurBouton: CGFloat = 84

    private var ouvertureFin: CGFloat { -CGFloat(fin.count) * (largeurBouton + 6) }
    private var ouvertureDebut: CGFloat { CGFloat(debut.count) * (largeurBouton + 6) }

    func body(content: Content) -> some View {
        ZStack {
            HStack(spacing: 6) {
                ForEach(debut) { bouton($0) }
                Spacer(minLength: 0)
                ForEach(fin) { bouton($0) }
            }
            .opacity(abs(decalage) > 8 ? 1 : 0)
            .accessibilityHidden(true)
            content
                // Pendant le glissement, et tant que les boutons sont découverts, la carte n'ouvre rien.
                .disabled(glisse || repos != 0)
                .overlay {
                    // Boutons découverts : un toucher sur la carte la referme, sans ouvrir la fiche.
                    if repos != 0 {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { fermer() }
                            .accessibilityHidden(true)
                    }
                }
                .offset(x: decalage)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 18)
                        .onChanged { valeur in
                            // Seulement un geste horizontal : le défilement vertical de la page reste libre.
                            guard horizontal(valeur) else { return }
                            glisse = true
                            let voulu = repos + valeur.translation.width
                            decalage = min(debut.isEmpty ? 0 : ouvertureDebut + 40, max(fin.isEmpty ? 0 : -600, voulu))
                        }
                        .onEnded { valeur in
                            relacher()
                            guard horizontal(valeur) else {
                                withAnimation(.snappy) { decalage = repos }
                                return
                            }
                            if let derniere = fin.last, derniere.destructive, decalage < ouvertureFin - 120 {
                                declencher(derniere)
                                return
                            }
                            let cible: CGFloat = decalage < -40 && !fin.isEmpty ? ouvertureFin
                                : decalage > 40 && !debut.isEmpty ? ouvertureDebut : 0
                            repos = cible
                            withAnimation(.snappy) { decalage = cible }
                        }
                )
        }
        .sensoryFeedback(.impact, trigger: repos)
        // VoiceOver et le contrôle vocal : les mêmes actions, nommées.
        .accessibilityActions {
            ForEach(debut + fin) { action in
                Button(action.libelle) { action.action() }
            }
        }
    }

    /// Le toucher qui termine le glissement arrive aussi à la carte : elle reste sourde un court instant.
    private func relacher() {
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            glisse = false
        }
    }

    private func fermer() {
        repos = 0
        withAnimation(.snappy) { decalage = 0 }
    }

    private func horizontal(_ valeur: DragGesture.Value) -> Bool {
        abs(valeur.translation.width) > abs(valeur.translation.height) * 1.3
    }

    private func bouton(_ action: ActionGlissee) -> some View {
        Button { declencher(action) } label: {
            VStack(spacing: 6) {
                Image(systemName: action.symbole).font(.title3.weight(.semibold))
                Text(action.libelle).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(Theme.texte)
            .frame(width: largeurBouton)
            .frame(maxHeight: .infinity)
            .background(action.couleur, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func declencher(_ action: ActionGlissee) {
        if action.destructive {
            withAnimation(.easeIn(duration: 0.2)) { decalage = -600 }
            Task {
                try? await Task.sleep(for: .milliseconds(200))
                action.action()
                repos = 0
                decalage = 0
            }
        } else {
            action.action()
            repos = 0
            withAnimation(.snappy) { decalage = 0 }
        }
    }
}

extension View {
    func glissementsCarte(debut: [ActionGlissee] = [], fin: [ActionGlissee]) -> some View {
        modifier(GlissementsCarte(debut: debut, fin: fin))
    }

    /// Retirer d'un glissement vers la gauche, sans autre action.
    func glisserPourRetirer(_ libelle: String, action: @escaping () -> Void) -> some View {
        glissementsCarte(fin: [ActionGlissee(libelle: libelle, symbole: "trash", couleur: Theme.rouge, destructive: true, action: action)])
    }
}
