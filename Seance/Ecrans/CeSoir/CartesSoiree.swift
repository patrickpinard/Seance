import SeanceDonnees
import SeanceKit
import SwiftUI

// Les cartes de la page Ce soir, dans l'esprit du programme TV : l'image en grand, l'essentiel dessus.

/// Un titre d'une soirée : son image en 16/9 avec ce qui se passe ce soir et où le regarder ; dessous, « Regardé »
/// (ou « Ce soir » pour une soirée à venir), changer de soir, retirer.
struct CarteSoiree: View {
    let titre: SelectionSoir
    let decor: EtatDecors.Decor?
    let rendezVous: String?
    let ou: String?
    /// Pour une série : l'épisode à regarder (cherché sur le NAS) et sa durée.
    var episode: NumeroEpisode?
    var minutesEpisode: Int?
    let peutMarquerVu: Bool
    /// À la place de « Regardé » quand il n'y a rien à cocher : « Aucun nouvel épisode disponible ».
    var note: String?
    /// Pour une soirée à venir : « Ce soir » ramène le titre à la soirée de ce soir, à la place de « Regardé ».
    var ramener: (() -> Void)?
    let vu: () -> Void
    let dater: () -> Void
    let retirer: () -> Void

    /// Le passage TV dit déjà où regarder : pas de doublon.
    private var ouAffiche: String? {
        guard let ou, ou != rendezVous, !(rendezVous?.hasPrefix("Sur ") == true && ou.hasPrefix("Ce soir sur")) else { return nil }
        return ou
    }

    private var duree: String? {
        guard let minutes = titre.reference.type == .serie ? minutesEpisode : decor?.minutes, minutes > 0 else { return nil }
        return HeuresTele.duree(minutes)
    }

    private var detail: String {
        [titre.reference.type == .film ? "film" : "série", duree].compactMap { $0 }.joined(separator: ", ")
    }

    /// Charte 8.0 : la carte des cartes larges, le ▶︎ blanc dessus ; les actions se nomment au glissement vers la gauche
    /// et à l'appui long — plus d'icônes seules sous la carte.
    var body: some View {
        let faits = [titre.reference.type == .film ? "Film" : "Série", duree, peutMarquerVu || ramener != nil ? nil : note].compactMap { $0 }
        GlisserPourAgir(actions: actionsGlissees) {
            NavigationLink(value: titre.reference) {
                Color.clear
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        ImageDistante(url: ImageTMDB.url(decor?.fond, .fond) ?? ImageTMDB.url(titre.cheminAffiche, .fond), coins: 0)
                    }
                    .overlay {
                        LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0), .init(color: .clear, location: 0.35),
                                               .init(color: .black.opacity(0.92), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let origine = rendezVous ?? ouAffiche {
                                Text(origine)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.78))
                                    .lineLimit(1)
                            }
                            Text(titre.titre)
                                .font(.headline)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(faits.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.66))
                                .lineLimit(1)
                        }
                        .padding(12)
                        .padding(.trailing, 54)
                    }
                    .foregroundStyle(.white)
                    .surImage()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([titre.titre, detail, rendezVous, ouAffiche].compactMap { $0 }.joined(separator: ", "))
            .accessibilityAddTraits(.isButton)
            .overlay(alignment: .bottomTrailing) {
                ActionsOuRegarder(reference: titre.reference, titre: titre.titre, episode: episode,
                                  secours: nil, presentation: .rond)
                    .padding(10)
            }
        }
        .contextMenu { menu }
        .accessibilityActions { menu }
    }

    /// Glisser vers la gauche : les deux gestes du soir, nommés, avec leur icône (charte 8.0).
    private var actionsGlissees: [ActionGlissee] {
        [ramener.map { ActionGlissee(nom: "Ce soir", symbole: "moon.stars.fill", destructive: false, faire: $0) }
            ?? ActionGlissee(nom: "Un autre soir", symbole: "calendar.badge.clock", destructive: false, faire: dater),
         ActionGlissee(nom: "Retirer", symbole: "minus.circle.fill", destructive: true, faire: retirer)]
    }

    /// Appui long : les mêmes gestes, dans les mêmes mots, et « Terminé ».
    @ViewBuilder
    private var menu: some View {
        if peutMarquerVu, ramener == nil {
            Button(action: vu) { Label(titre.reference.type == .film ? "Terminé" : "Épisode regardé", systemImage: "checkmark") }
        }
        if let ramener {
            Button(action: ramener) { Label("Ce soir", systemImage: "moon.stars.fill") }
        }
        Button(action: dater) { Label("Un autre soir…", systemImage: "calendar.badge.clock") }
        Button(role: .destructive, action: retirer) { Label("Retirer de la soirée", systemImage: "minus.circle.fill") }
    }
}

/// Glisser une carte vers la gauche découvre ses actions, comme dans une liste d'iOS — mais sur une carte, dans une
/// grille (charte 8.0). Un toucher sur une action la fait et referme ; toucher ailleurs ou glisser vers la droite referme.
struct ActionGlissee {
    let nom: String
    let symbole: String
    let destructive: Bool
    let faire: () -> Void
}

struct GlisserPourAgir<Contenu: View>: View {
    let actions: [ActionGlissee]
    @ViewBuilder let contenu: Contenu

    @State private var decalage: CGFloat = 0
    @State private var ouvert = false
    private static var largeurAction: CGFloat { 84 }
    private var largeur: CGFloat { Self.largeurAction * CGFloat(actions.count) }

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    Button {
                        refermer()
                        action.faire()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: action.symbole).font(.title3.weight(.semibold))
                            Text(action.nom).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.white)
                        .frame(width: Self.largeurAction)
                        .frame(maxHeight: .infinity)
                        .background(action.destructive ? Theme.rouge : Theme.texte3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(decalage < 0 ? 1 : 0)
            .accessibilityHidden(true)
            contenu
                .offset(x: decalage)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 24)
                        .onChanged { geste in
                            // Seulement un glissement surtout horizontal : le défilement vertical reste à la page.
                            guard abs(geste.translation.width) > abs(geste.translation.height) * 1.5 else { return }
                            decalage = min(0, max(-largeur - 30, (ouvert ? -largeur : 0) + geste.translation.width))
                        }
                        .onEnded { geste in
                            guard abs(geste.translation.width) > abs(geste.translation.height) * 1.5 else { return }
                            withAnimation(.snappy) {
                                ouvert = decalage < -largeur / 2
                                decalage = ouvert ? -largeur : 0
                            }
                        }
                )
                .onTapGesture { if ouvert { refermer() } }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: ouvert)
    }

    private func refermer() {
        withAnimation(.snappy) {
            ouvert = false
            decalage = 0
        }
    }
}

extension CarteSoiree {
    /// Ce que la soirée sait quand aucune pastille ne s'applique. « Sur Netflix » ou « Sur ton NAS » ont leur pastille :
    /// seul ce qui n'est pas chez toi (« À louer ou acheter », « Introuvable ») se dit en toutes lettres.
    static func secours(_ ou: String) -> String? {
        ou.hasPrefix("Sur ") || ou.hasPrefix("Ce soir sur") ? nil : ou
    }
}

/// Une soirée passée qui n'a pas été tranchée : « Hier soir · Heat — regardé ? ». Trois réponses : oui, ce soir, non.
struct CarteSoireePassee: View {
    let titre: SelectionSoir
    let decor: EtatDecors.Decor?
    let regarde: () -> Void
    let ceSoir: () -> Void
    let retirer: () -> Void
    /// « Pas maintenant » (8.2.11) : la question revient un autre jour ; « Oublier » la retire pour de bon.
    var plusTard: () -> Void = {}

    /// « Hier soir », « Mardi soir ».
    private var quand: String {
        guard let jour = ServiceSoiree.jour(titre.soiree) else { return "L'autre soir" }
        if titre.soiree == ServiceSoiree.soiree(Date.now.addingTimeInterval(-86_400)) { return "Hier soir" }
        let nom = jour.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "fr_CH")))
        return nom.prefix(1).uppercased() + nom.dropFirst() + " soir"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: titre.reference) {
                HStack(spacing: 12) {
                    ImageDistante(url: ImageTMDB.url(decor?.fond, .fond) ?? ImageTMDB.url(titre.cheminAffiche, .fond), coins: 9)
                        .frame(width: 96, height: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(quand) · regardé ?")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Theme.texte2)
                        Text(titre.titre)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(quand), \(titre.titre). L'as-tu regardé ?")

            // En texte agrandi, les trois réponses passent à la ligne plutôt que de se tronquer.
            Flux(espacement: 10) {
                Button(action: regarde) {
                    Label(titre.reference.type == .film ? "Terminé" : "Regardé", systemImage: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .fixedSize()
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 36)
                        .background(Theme.degradeAccent, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                Button(action: ceSoir) {
                    Label("Ce soir", systemImage: "moon.stars.fill").fixedSize()
                }
                .buttonStyle(.secondaire)
                .accessibilityLabel("Pas encore : le regarder ce soir")
                Button(action: plusTard) {
                    Label("Pas maintenant", systemImage: "clock").fixedSize()
                }
                .buttonStyle(.secondaire)
                .accessibilityHint("La question reviendra demain")
                // Un nom plutôt qu'une croix seule (charte 8.0).
                Button(action: retirer) {
                    Label("Oublier", systemImage: "minus.circle.fill").fixedSize()
                }
                .buttonStyle(StyleBoutonSecondaire(destructif: true))
                .help("Pas regardé : retirer ce titre de cette soirée passée. Il reste dans Mes listes.")
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.trait, lineWidth: 1))
    }
}
