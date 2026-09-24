import AppIntents
import SeanceKit
import SwiftUI
import UIKit
import WidgetKit

// MARK: - Éléments communs

/// Vignette d'affiche, ou silhouette quand l'image n'a pas pu être chargée.
struct AfficheWidget: View {
    let donnees: Data?
    var largeur: CGFloat
    var coins: CGFloat = 6

    var body: some View {
        Group {
            if let donnees, let image = UIImage(data: donnees) {
                Image(uiImage: image).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFill()
            } else {
                Rectangle().fill(.white.opacity(0.1))
                    .overlay(Image(systemName: "film").font(.system(size: largeur * 0.35)).foregroundStyle(.white.opacity(0.4)))
            }
        }
        .frame(width: largeur, height: largeur * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: coins, style: .continuous))
    }
}

struct EnteteWidget: View {
    let titre: String
    let symbole: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbole).foregroundStyle(CouleursWidget.accent)
            Text(titre).foregroundStyle(.white)
        }
        .font(.footnote.weight(.bold))
        .lineLimit(1)
        .widgetAccentable()
    }
}

struct VideWidget: View {
    let titre: String
    let texte: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            Text(texte).font(.caption).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Fond sombre de Séance, avec une lueur orange dans un coin.
struct FondWidget: View {
    var body: some View {
        ZStack {
            CouleursWidget.fond
            RadialGradient(colors: [CouleursWidget.accent.opacity(0.28), .clear], center: .topTrailing, startRadius: 4, endRadius: 190)
        }
    }
}

// MARK: - Ma soirée

struct VueSoiree: View {
    let entree: EntreeSoiree
    let famille: WidgetFamily

    var body: some View {
        switch famille {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "moon.stars.fill").font(.headline)
                    Text("\(entree.titres.count)").font(.system(.headline, design: .rounded).weight(.bold))
                }
            }
            .accessibilityLabel("Ma soirée : \(entree.titres.count) titres")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Ma soirée", systemImage: "moon.stars.fill").font(.headline).widgetAccentable()
                if entree.titres.isEmpty {
                    Text("Rien de prévu").font(.caption)
                } else {
                    ForEach(entree.titres.prefix(2)) { titre in
                        Text(titre.titre).font(.caption).lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Label(entree.titres.isEmpty ? "Rien de prévu ce soir" : entree.titres.map(\.titre).joined(separator: ", "),
                  systemImage: "moon.stars.fill")
        default:
            ecran
        }
    }

    @ViewBuilder
    private var ecran: some View {
        VStack(alignment: .leading, spacing: 8) {
            EnteteWidget(titre: "Ma soirée", symbole: "moon.stars.fill")
            if entree.titres.isEmpty {
                VideWidget(titre: "Rien de prévu", texte: "Touche « Ce soir » sur un titre dans Séance pour le garder pour ce soir.")
            } else if famille == .systemMedium {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(entree.titres.prefix(3)) { titre in
                        Link(destination: LiensWidget.fiche(titre.reference)) {
                            VStack(alignment: .leading, spacing: 3) {
                                AfficheWidget(donnees: titre.affiche, largeur: 50)
                                Text(titre.titre).font(.caption2.weight(.semibold)).lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(width: 92, alignment: .leading)
                        }
                    }
                    if entree.titres.count > 3 {
                        Text("+\(entree.titres.count - 3)")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(CouleursWidget.texte2)
                            .frame(maxHeight: 87)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
            } else {
                let limite = famille == .systemSmall ? 2 : 5
                VStack(alignment: .leading, spacing: famille == .systemSmall ? 6 : 9) {
                    ForEach(entree.titres.prefix(limite)) { titre in
                        Link(destination: LiensWidget.fiche(titre.reference)) {
                            ligne(titre)
                        }
                    }
                    if entree.titres.count > limite {
                        Text("+ \(entree.titres.count - limite) autre\(entree.titres.count - limite > 1 ? "s" : "")")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(CouleursWidget.texte2)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func ligne(_ titre: TitreWidget) -> some View {
        let petit = famille == .systemSmall
        return HStack(spacing: 8) {
            AfficheWidget(donnees: titre.affiche, largeur: petit ? 28 : 40, coins: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(titre.titre).font((petit ? Font.footnote : .subheadline).weight(.semibold)).lineLimit(petit ? 2 : 1)
                if !petit {
                    Text(titre.detail).font(.caption).foregroundStyle(CouleursWidget.texte2).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }
}

// MARK: - Prochains épisodes

struct VueEpisodes: View {
    let entree: EntreeEpisodes
    let famille: WidgetFamily

    var body: some View {
        switch famille {
        case .accessoryRectangular:
            if let premier = entree.episodes.first {
                VStack(alignment: .leading, spacing: 1) {
                    Text(premier.nom).font(.headline).lineLimit(1).widgetAccentable()
                    Text("\(premier.code) · \(premier.dureeMinutes) min").font(.caption)
                    if let titre = premier.titreEpisode {
                        Text(titre).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading) {
                    Label("Épisodes", systemImage: "play.tv").font(.headline)
                    Text("Tout est vu").font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .accessoryInline:
            if let premier = entree.episodes.first {
                Label("\(premier.nom) \(premier.code)", systemImage: "play.tv")
            } else {
                Label("Aucun épisode en attente", systemImage: "play.tv")
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "play.tv.fill").font(.subheadline)
                    Text("\(entree.episodes.count)").font(.system(.headline, design: .rounded).weight(.bold))
                }
            }
        case .systemSmall:
            petit
        default:
            liste
        }
    }

    @ViewBuilder
    private var petit: some View {
        if let premier = entree.episodes.first {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    AfficheWidget(donnees: premier.affiche, largeur: 38, coins: 5)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(premier.nom).font(.subheadline.weight(.bold)).lineLimit(2)
                        Text(premier.code)
                            .font(.system(.footnote, design: .rounded).weight(.heavy))
                            .foregroundStyle(CouleursWidget.texte2)
                    }
                }
                Spacer(minLength: 4)
                Text(premier.titreEpisode ?? "\(premier.dureeMinutes) min")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                Button(intent: CocherEpisodeIntent(premier)) {
                    Label("Vu", systemImage: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundStyle(.black)
                        .background(CouleursWidget.degrade, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                .accessibilityLabel("Marquer \(premier.nom) \(premier.code) comme vu")
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(LiensWidget.fiche(premier.reference))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                EnteteWidget(titre: "Épisodes", symbole: "play.tv.fill")
                VideWidget(titre: "Tout est vu", texte: "Coche un épisode sur la fiche d'une série pour la suivre ici.")
            }
        }
    }

    private var liste: some View {
        let limite = famille == .systemLarge ? 5 : 2
        return VStack(alignment: .leading, spacing: 8) {
            EnteteWidget(titre: "Prochains épisodes", symbole: "play.tv.fill")
            if entree.episodes.isEmpty {
                VideWidget(titre: "Tout est vu", texte: "Coche un épisode sur la fiche d'une série pour la suivre ici.")
            }
            ForEach(entree.episodes.prefix(limite)) { episode in
                HStack(spacing: 10) {
                    Link(destination: LiensWidget.fiche(episode.reference)) {
                        HStack(spacing: 10) {
                            AfficheWidget(donnees: episode.affiche, largeur: 34, coins: 4)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(episode.nom).font(.subheadline.weight(.bold)).lineLimit(1)
                                Text([episode.code, episode.titreEpisode].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(CouleursWidget.texte2)
                                    .lineLimit(1)
                                Text("\(episode.dureeMinutes) min").font(.caption2).foregroundStyle(.white.opacity(0.55))
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    Button(intent: CocherEpisodeIntent(episode)) {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.black)
                            .frame(width: 34, height: 34)
                            .background(CouleursWidget.degrade, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Marquer \(episode.nom) \(episode.code) comme vu")
                }
                .foregroundStyle(.white)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - À venir

struct VueAVenir: View {
    let entree: EntreeAVenir
    let famille: WidgetFamily

    var body: some View {
        switch famille {
        case .accessoryRectangular:
            if let premier = entree.echeances.first {
                VStack(alignment: .leading, spacing: 1) {
                    Text(premier.compteARebours(depuis: entree.date)).font(.headline).widgetAccentable()
                    Text(premier.titre).font(.caption.weight(.semibold)).lineLimit(1)
                    Text(premier.libelle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading) {
                    Label("À venir", systemImage: "bell").font(.headline)
                    Text("Rien d'annoncé").font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .accessoryInline:
            if let premier = entree.echeances.first {
                Label("\(premier.compteARebours(depuis: entree.date)) : \(premier.titre)", systemImage: premier.symbole)
            } else {
                Label("Rien d'annoncé", systemImage: "bell")
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "bell.fill").font(.subheadline)
                    Text("\(entree.echeances.count)").font(.system(.headline, design: .rounded).weight(.bold))
                }
            }
        case .systemSmall:
            petit
        default:
            liste
        }
    }

    @ViewBuilder
    private var petit: some View {
        VStack(alignment: .leading, spacing: 4) {
            EnteteWidget(titre: "À venir", symbole: "bell.fill")
            if let premier = entree.echeances.first {
                Spacer(minLength: 0)
                Text(premier.compteARebours(depuis: entree.date))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(CouleursWidget.degrade)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(premier.titre).font(.subheadline.weight(.bold)).foregroundStyle(.white).lineLimit(2)
                Label(premier.libelle, systemImage: premier.symbole)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                if entree.echeances.count > 1 {
                    Text("+ \(entree.echeances.count - 1) ensuite")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(CouleursWidget.texte2)
                }
            } else {
                VideWidget(titre: "Rien d'annoncé", texte: "Touche la cloche sur une fiche pour suivre ses sorties.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(entree.echeances.first.map { LiensWidget.fiche($0.reference) } ?? LiensWidget.aVenir)
    }

    private var liste: some View {
        let limite = famille == .systemLarge ? 6 : 3
        return VStack(alignment: .leading, spacing: famille == .systemLarge ? 10 : 6) {
            EnteteWidget(titre: "À venir", symbole: "bell.fill")
            if entree.echeances.isEmpty {
                VideWidget(titre: "Rien d'annoncé", texte: "Touche la cloche sur une fiche pour suivre ses prochains épisodes, ses sorties et ses passages à la TV.")
            }
            ForEach(entree.echeances.prefix(limite)) { echeance in
                Link(destination: LiensWidget.fiche(echeance.reference)) {
                    HStack(spacing: 10) {
                        if famille == .systemLarge {
                            AfficheWidget(donnees: echeance.affiche, largeur: 30, coins: 4)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(echeance.titre).font(.subheadline.weight(.bold)).lineLimit(1)
                            Label(echeance.libelle, systemImage: echeance.symbole)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(echeance.compteARebours(depuis: entree.date))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(CouleursWidget.texte2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.1), in: Capsule())
                    }
                    .foregroundStyle(.white)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(LiensWidget.aVenir)
    }
}
