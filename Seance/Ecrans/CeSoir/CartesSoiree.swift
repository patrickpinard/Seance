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

    var body: some View {
        VStack(spacing: 0) {
            NavigationLink(value: titre.reference) {
                Color.clear
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        ImageDistante(url: ImageTMDB.url(decor?.fond, .fond) ?? ImageTMDB.url(titre.cheminAffiche, .fond), coins: 0)
                    }
                    .overlay {
                        LinearGradient(stops: [.init(color: .black.opacity(0.45), location: 0), .init(color: .clear, location: 0.35),
                                               .init(color: .black.opacity(0.92), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let rendezVous {
                                Text(rendezVous)
                                    .font(.subheadline.weight(.heavy))
                                    .foregroundStyle(Theme.accentClair)
                                    .lineLimit(1)
                            }
                            Text(titre.titre)
                                .font(.title3.weight(.bold))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            // Sur la zone sombre de l'image : la pastille se lit quelle que soit la photo.
                            HStack(spacing: 7) {
                                PastilleType(film: titre.reference.type == .film)
                                if let duree {
                                    Text(duree)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.78))
                                }
                            }
                        }
                        .padding(12)
                    }
                    .foregroundStyle(.white)
                    .surImage()
                    .clipped()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([titre.titre, detail, rendezVous, ouAffiche].compactMap { $0 }.joined(separator: ", "))
            .accessibilityAddTraits(.isButton)

            // Où le regarder, tout de suite : c'est la première chose à savoir d'un titre prévu. Sur une carte
            // de soirée, un seul bouton — Séance choisit la source la plus directe et dit les autres dessous.
            ActionsOuRegarder(reference: titre.reference, titre: titre.titre, episode: episode,
                              secours: ouAffiche.flatMap { Self.secours($0) }, presentation: .boutonUnique)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .background(Theme.surface)

            HStack(spacing: 10) {
                if let ramener {
                    Button(action: ramener) {
                        Label("Ce soir", systemImage: "moon.stars.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.accentClair)
                            .padding(.horizontal, 16)
                            .frame(height: 38)
                            .background(Theme.accent.opacity(0.18), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Ramener ce titre à la soirée de ce soir.")
                    .accessibilityLabel("Regarder ce soir")
                } else if peutMarquerVu {
                    Button(action: vu) {
                        Label(titre.reference.type == .film ? "Terminé" : "Regardé", systemImage: "checkmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16)
                            .frame(height: 38)
                            .background(Theme.degradeAccent, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Terminé : le film rejoint tes Terminés, ou l'épisode est coché, et le titre quitte ta soirée.")
                    .accessibilityHint("Le film rejoint tes Terminés, ou l'épisode est coché, et le titre quitte ta soirée")
                    .accessibilityIdentifier("Regardé")
                } else if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                BoutonIcone(symbole: "calendar", libelle: "Prévoir pour une autre soirée", taille: 38,
                            explication: "Choisir la date à laquelle tu veux le regarder.", action: dater)
                BoutonIcone(symbole: "xmark", libelle: "Retirer de ma soirée", taille: 38,
                            explication: "Retirer ce titre de ta soirée. Il reste dans Mes listes.", action: retirer)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1))
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
                            .foregroundStyle(Theme.accentClair)
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
                    Label("Ce soir", systemImage: "moon.stars.fill")
                        .font(.subheadline.weight(.bold))
                        .fixedSize()
                        .foregroundStyle(Theme.accentClair)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(Theme.accent.opacity(0.18), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pas encore : le regarder ce soir")
                BoutonIcone(symbole: "xmark", libelle: "Pas regardé, l'oublier", taille: 36,
                            explication: "Retirer ce titre de cette soirée passée. Il reste dans Mes listes.", action: retirer)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
    }
}
