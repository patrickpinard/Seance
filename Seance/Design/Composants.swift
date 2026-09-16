import SeanceKit
import SwiftUI

/// Image distante avec silhouette pendant le chargement (UX-12, UX-13).
struct ImageDistante: View {
    let url: URL?
    var coins: CGFloat = 12

    /// L'image remplit la place proposée sans jamais imposer sa propre taille : une image de fond
    /// large ne doit pas élargir l'écran.
    var body: some View {
        Rectangle().fill(Theme.surface)
            .overlay {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        if url == nil {
                            Image(systemName: "film").foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: coins, style: .continuous))
    }
}

/// Anneau de note TMDB (UX-03, UX-04).
struct AnneauNote: View {
    let pourcentage: Int
    var diametre: CGFloat = 36

    var body: some View {
        let couleur = Theme.couleurNote(pourcentage)
        ZStack {
            Circle().fill(.black.opacity(0.85))
            Circle().stroke(couleur.opacity(0.25), lineWidth: diametre * 0.085)
                .padding(diametre * 0.09)
            Circle().trim(from: 0, to: CGFloat(pourcentage) / 100)
                .stroke(couleur, style: StrokeStyle(lineWidth: diametre * 0.085, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(diametre * 0.09)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(pourcentage)").font(.system(size: diametre * 0.32, weight: .bold))
                Text("%").font(.system(size: diametre * 0.16, weight: .semibold)).baselineOffset(diametre * 0.1)
            }
            .foregroundStyle(.white)
        }
        .frame(width: diametre, height: diametre)
        .accessibilityElement()
        .accessibilityLabel("note \(pourcentage) %")
    }
}

/// Carte d'un titre dans un carrousel ou une grille (UX-03).
struct CarteAffiche: View {
    let titre: TitreResume
    var largeur: CGFloat? = 118

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ImageDistante(url: ImageTMDB.url(titre.cheminAffiche, .affiche))
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay(alignment: .bottomLeading) {
                    if titre.nombreVotes > 0 {
                        AnneauNote(pourcentage: titre.pourcentageNote)
                            .offset(x: 8, y: 16)
                    }
                }
            Text(titre.titre)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.top, 22)
            Text(titre.date.map { String($0.annee) } ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: largeur)
        .accessibilityElement(children: .combine)
    }
}

struct PuceFiltre: View {
    let libelle: String
    var active = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(libelle)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .foregroundStyle(active ? Color.black : Color.primary)
                .background(active ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.surface), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Titre de section avec lien facultatif à droite.
struct TitreSection<Accessoire: View>: View {
    let titre: String
    @ViewBuilder var accessoire: Accessoire

    var body: some View {
        HStack {
            Text(titre).font(.title3.weight(.bold))
            Spacer()
            accessoire
        }
        .padding(.horizontal, 20)
    }
}

extension TitreSection where Accessoire == EmptyView {
    init(_ titre: String) {
        self.titre = titre
        accessoire = EmptyView()
    }
}

/// Invite affichée tant que la clé TMDB manque.
struct InviteCleTMDB: View {
    var body: some View {
        ContentUnavailableView {
            Label("Clé TMDB manquante", systemImage: "key")
        } description: {
            Text("Enregistre ta clé TMDB dans l'onglet Moi, rubrique TMDB.")
        }
    }
}
