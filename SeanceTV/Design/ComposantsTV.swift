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

/// Une grande carte 16/9, image plein cadre et texte dessus : la soirée, un passage TV.
struct CarteLargeTV: View {
    let surtitre: String?
    let titre: String
    let detail: String?
    let cheminImage: String?
    /// Un symbole en coin : sur ton NAS, déjà vu — les mêmes marques que sur l'iPhone.
    var marque: String?
    /// Une carte de grille, plus petite que celle d'une étagère d'accueil.
    var largeur: CGFloat = CarteLargeTV.largeur
    /// Souvenirs (6.2) : pas d'image, un halo orange et ce grand SF Symbol à droite, comme sur l'iPhone.
    var icone: String?
    /// Un ▶︎ en haut à gauche : la carte lance la vidéo.
    var lectureEnCoin = false
    /// Le titre, pour dire où le regarder (6.3) : les logos des plateformes, le NAS, la chaîne.
    var reference: ReferenceTitre?

    @Environment(EtatTV.self) private var etatTV

    static let largeur: CGFloat = 620
    /// Trois par rangée sur un écran de télévision, avec les marges.
    static let largeurGrille: CGFloat = 520

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if let icone {
                    FondSouvenirTV(symbole: icone)
                } else {
                    ImageTV(url: ImageTMDB.url(cheminImage, .fondGrand))
                }
            }
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.25), .black.opacity(0.88)], startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .topLeading) {
                if lectureEnCoin {
                    Image(systemName: "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 56, height: 56)
                        .background(Theme.degradeAccent, in: Circle())
                        .padding(16)
                } else if let reference {
                    BadgeOuTV(reference: reference).padding(16)
                }
            }
            .task(id: reference) {
                guard let reference else { return }
                etatTV.ou.demander(reference, client: etatTV.tmdb)
            }
            .overlay(alignment: .topTrailing) {
                if let marque {
                    Image(systemName: marque)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(marque == "externaldrive.fill" ? Color.green : Theme.accentClair)
                        .padding(12)
                        .background(.black.opacity(0.65), in: Circle())
                        .padding(16)
                }
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
            .frame(width: largeur)
            .accessibilityElement(children: .combine)
    }
}

/// Où regarder, en coin de carte sur la TV (6.3) : le logo de chaque plateforme de tes abonnements, le disque du NAS,
/// l'écran d'une chaîne — les mêmes marques que sur l'iPhone, en plus grand.
struct BadgeOuTV: View {
    let reference: ReferenceTitre

    @Environment(EtatTV.self) private var etat

    var body: some View {
        let badges = etat.ou.badges(reference)
        HStack(spacing: 8) {
            ForEach(badges, id: \.self) { badge in
                switch badge {
                case .nas: pastille("externaldrive.fill")
                case .plateforme(_, _, let logo):
                    ImageTV(url: ImageTMDB.url(logo, .logo), symboleVide: "play.tv")
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1))
                case .tele: pastille("tv.fill")
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func pastille(_ symbole: String) -> some View {
        Image(systemName: symbole)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(Theme.accentClair)
            .frame(width: 44, height: 44)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1))
    }
}

/// Le fond d'une carte de souvenir sur la TV (6.2) : le halo orange et la grande icône de l'iPhone.
struct FondSouvenirTV: View {
    let symbole: String

    var body: some View {
        GeometryReader { cadre in
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.1)
                RadialGradient(colors: [Theme.accentClair.opacity(0.36), Theme.accent.opacity(0.10), .clear],
                               center: UnitPoint(x: 0.78, y: 0.42), startRadius: 0, endRadius: cadre.size.width * 0.55)
                Image(systemName: symbole)
                    .resizable()
                    .scaledToFit()
                    .frame(width: cadre.size.width * 0.3, height: cadre.size.height * 0.46)
                    .foregroundStyle(Theme.accentClair)
                    .position(x: cadre.size.width * 0.78, y: cadre.size.height * 0.37)
            }
        }
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
        // Focalisable : une page qui n'a que ce message doit garder la télécommande en main (touche Retour).
        .focusable()
    }
}

/// Le bouton de Séance sur la TV. Le style par défaut de tvOS 26 ne se dessinait pas du tout sur le fond sombre d'une
/// fiche (ni plateau ni libellé) : celui-ci est toujours visible, et devient blanc à libellé noir quand il a le focus,
/// comme dans les apps d'Apple. `principal` : l'action qu'on est venu faire (lire), en orange.
struct BoutonTV: ButtonStyle {
    var principal = false
    /// `nil` : le bouton prend la hauteur de son contenu (une tuile de jour), au lieu des 76 points d'un bouton d'action.
    var hauteur: CGFloat? = 76

    func makeBody(configuration: Configuration) -> some View {
        Corps(configuration: configuration, principal: principal, hauteur: hauteur)
    }

    private struct Corps: View {
        let configuration: Configuration
        let principal: Bool
        let hauteur: CGFloat?
        @Environment(\.isFocused) private var aLeFocus
        @Environment(\.isEnabled) private var actif

        var body: some View {
            configuration.label
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(aLeFocus || principal ? .black : .white)
                .padding(.horizontal, hauteur == nil ? 0 : 34)
                .frame(height: hauteur)
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

/// Le prénom de qui regarde, en haut à gauche (6.1) : une capsule discrète, orange sur fond sombre ; au focus, blanche
/// et agrandie comme les autres boutons de la TV.
struct PastilleQuiRegardeTV: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Corps(configuration: configuration)
    }

    private struct Corps: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var aLeFocus

        var body: some View {
            configuration.label
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(aLeFocus ? Color.black : Theme.accentClair)
                .padding(.horizontal, 22)
                .frame(height: 56)
                .background(aLeFocus ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.black.opacity(0.45)), in: Capsule())
                .scaleEffect(aLeFocus ? 1.08 : (configuration.isPressed ? 0.97 : 1))
                .animation(.easeOut(duration: 0.15), value: aLeFocus)
        }
    }
}

/// Une page ouverte depuis une autre doit toujours pouvoir se refermer à la télécommande. tvOS n'envoie la touche
/// Retour (Menu) à une page que si un de ses éléments a le focus : une page faite seulement de texte — « À propos » —
/// laissait la touche partir au système, qui quittait l'app. Ici la page la traite elle-même.
private struct PageOuverte: ViewModifier {
    @Environment(\.dismiss) private var fermer

    func body(content: Content) -> some View {
        content.onExitCommand { fermer() }
    }
}

extension View {
    func pageOuverte() -> some View { modifier(PageOuverte()) }
}

/// Le sélecteur de Séance, version télécommande : des cases de même largeur, l'active en orange à texte noir.
/// Le même geste que sur l'iPhone (charte graphique), avec les tailles de la TV.
struct SelecteurTV<Valeur: Hashable>: View {
    @Binding var selection: Valeur
    let cases: [(valeur: Valeur, nom: String)]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                ForEach(cases, id: \.valeur) { element in
                    Button { selection = element.valeur } label: { Text(element.nom) }
                        .buttonStyle(BoutonTV(principal: selection == element.valeur))
                }
            }
            .padding(.horizontal, MargesTV.bord)
            .padding(.vertical, 14)
        }
        .scrollClipDisabled()
        .focusSection()
    }
}

/// Une tuile de jour, comme la rangée de jours de l'iPhone : nom, quantième, et ce qu'il y a ce jour-là.
struct TuileJourTV: View {
    let nom: String
    let numero: Int
    let detail: String

    var body: some View {
        VStack(spacing: 4) {
            Text(nom).font(.system(size: 24, weight: .bold))
            Text("\(numero)").font(.system(size: 46, weight: .heavy))
            Text(detail).font(.system(size: 20)).opacity(0.75)
        }
        .frame(width: 170, height: 150)
    }
}
