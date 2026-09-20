import SeanceKit
import SwiftUI
import UIKit

/// Image distante, gardée en mémoire : sur la TV, on revient sans cesse sur les mêmes étagères.
struct ImageTV: View {
    let url: URL?
    var symboleVide = "film"

    @State private var image: UIImage?

    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 300
        return cache
    }()

    var body: some View {
        Rectangle().fill(Theme.surface)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if !symboleVide.isEmpty {
                    Image(systemName: symboleVide).font(.system(size: 44)).foregroundStyle(.tertiary)
                }
            }
            .clipped()
            .task(id: url) { await charger() }
    }

    private func charger() async {
        guard let url else { image = nil; return }
        if let connue = Self.cache.object(forKey: url as NSURL) { image = connue; return }
        image = nil
        for tentative in 0..<3 {
            if let (donnees, _) = try? await URLSession.shared.data(from: url), let lue = UIImage(data: donnees) {
                Self.cache.setObject(lue, forKey: url as NSURL)
                image = lue
                return
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(600 * (tentative + 1)))
        }
    }
}

/// Une affiche 2:3 qui se choisit à la télécommande : elle grandit quand elle a le focus, et son titre s'allume.
struct AfficheTV: View {
    let titre: String
    let sousTitre: String?
    let cheminAffiche: String?
    var marque: String?

    static let largeur: CGFloat = 250

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ImageTV(url: ImageTMDB.url(cheminAffiche, .afficheGrande))
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    if let marque {
                        Image(systemName: marque)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.accentClair)
                            .padding(10)
                            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .padding(10)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(titre).font(.system(size: 26, weight: .semibold)).lineLimit(2, reservesSpace: true)
                if let sousTitre {
                    Text(sousTitre).font(.system(size: 22)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: Self.largeur)
    }
}

/// Une grande carte 16/9, image plein cadre et texte dessus : la soirée, un passage télé.
struct CarteLargeTV: View {
    let surtitre: String?
    let titre: String
    let detail: String?
    let cheminImage: String?

    static let largeur: CGFloat = 620

    var body: some View {
        ImageTV(url: ImageTMDB.url(cheminImage, .fondGrand))
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.25), .black.opacity(0.88)], startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    if let surtitre {
                        Text(surtitre).font(.system(size: 24, weight: .heavy)).foregroundStyle(Theme.accentClair)
                    }
                    Text(titre).font(.system(size: 36, weight: .bold)).lineLimit(2)
                    if let detail {
                        Text(detail).font(.system(size: 24)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                    }
                }
                .foregroundStyle(.white)
                .padding(24)
            }
            .frame(width: Self.largeur)
    }
}

/// Une étagère : un titre, et une rangée qu'on parcourt de gauche à droite.
struct EtagereTV<Contenu: View>: View {
    let titre: String
    var sousTitre: String?
    @ViewBuilder let contenu: Contenu

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(titre).font(.system(size: 38, weight: .bold))
                if let sousTitre {
                    Text(sousTitre).font(.system(size: 24)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, MargesTV.bord)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 40) { contenu }
                    .padding(.horizontal, MargesTV.bord)
                    .padding(.vertical, 30)   // la place de l'affiche qui grandit au focus
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

enum MargesTV {
    /// tvOS demande de laisser libre le bord de l'écran, que certains téléviseurs rognent.
    static let bord: CGFloat = 80
}

/// Un écran sans contenu dit ce qu'il montrera et d'où cela viendra (EF-139).
struct VideTV: View {
    let symbole: String
    let titre: String
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbole).font(.system(size: 80)).foregroundStyle(Theme.degradeAccent)
            Text(titre).font(.system(size: 42, weight: .bold))
            Text(message).font(.system(size: 28)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 1100)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 120)
    }
}

/// Le bouton de Séance sur la TV. Le style par défaut de tvOS 26 ne se dessinait pas du tout sur le fond sombre d'une
/// fiche (ni plateau ni libellé) : celui-ci est toujours visible, et devient blanc à libellé noir quand il a le focus,
/// comme dans les apps d'Apple. `principal` : l'action qu'on est venu faire (lire), en orange.
struct BoutonTV: ButtonStyle {
    var principal = false

    func makeBody(configuration: Configuration) -> some View {
        Corps(configuration: configuration, principal: principal)
    }

    private struct Corps: View {
        let configuration: Configuration
        let principal: Bool
        @Environment(\.isFocused) private var aLeFocus
        @Environment(\.isEnabled) private var actif

        var body: some View {
            configuration.label
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(aLeFocus ? .black : .white)
                .padding(.horizontal, 34)
                .frame(height: 76)
                .background {
                    let forme = RoundedRectangle(cornerRadius: 20, style: .continuous)
                    if aLeFocus {
                        forme.fill(.white)
                    } else if principal {
                        forme.fill(Theme.degradeAccent)
                    } else {
                        forme.fill(Color.white.opacity(0.14)).overlay(forme.strokeBorder(Color.white.opacity(0.22), lineWidth: 2))
                    }
                }
                .scaleEffect(aLeFocus ? 1.08 : (configuration.isPressed ? 0.97 : 1))
                .opacity(actif ? 1 : 0.4)
                .animation(.easeOut(duration: 0.15), value: aLeFocus)
        }
    }
}
