import SeanceDonnees
import SeanceKit
import SwiftUI

// Les cartes de la page Ce soir, dans l'esprit du programme télé : l'image en grand, l'essentiel dessus.

/// « Sur Netflix », « Sur le NAS », « Ce soir sur TF1 » : en vert, lisible sur une image.
private struct PastilleOu: View {
    let ou: String

    var body: some View {
        Label(ou, systemImage: ou.hasPrefix("Ce soir") ? "tv" : ou.hasPrefix("Sur le NAS") || ou.hasPrefix("Sur ton NAS") ? "externaldrive.fill" : "play.tv")
            .font(.caption2.weight(.bold))
            .lineLimit(1)
            .foregroundStyle(.green)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.black.opacity(0.65), in: Capsule())
    }
}

/// Un titre d'une soirée : son image en 16/9 avec ce qui se passe ce soir et où le regarder ; dessous, « Regardé »
/// (ou « Ce soir » pour une soirée à venir), changer de soir, retirer.
struct CarteSoiree: View {
    let titre: SelectionSoir
    let decor: EtatDecors.Decor?
    let rendezVous: String?
    let ou: String?
    let peutMarquerVu: Bool
    /// À la place de « Regardé » quand il n'y a rien à cocher : « Aucun nouvel épisode disponible ».
    var note: String?
    /// Pour une soirée à venir : « Ce soir » ramène le titre à la soirée de ce soir, à la place de « Regardé ».
    var ramener: (() -> Void)?
    let vu: () -> Void
    let dater: () -> Void
    let retirer: () -> Void

    /// Le passage télé dit déjà où regarder : pas de doublon.
    private var ouAffiche: String? {
        guard let ou, ou != rendezVous, !(rendezVous?.hasPrefix("Sur ") == true && ou.hasPrefix("Ce soir sur")) else { return nil }
        return ou
    }

    private var duree: String? {
        guard let minutes = decor?.minutes, minutes > 0 else { return nil }
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
                    .overlay(alignment: .topLeading) {
                        if let ouAffiche {
                            PastilleOu(ou: ouAffiche).padding(12)
                        }
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
                        Label("Regardé", systemImage: "checkmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16)
                            .frame(height: 38)
                            .background(Theme.degradeAccent, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Marquer comme regardé : le film est vu, ou l'épisode coché, et le titre quitte ta soirée.")
                    .accessibilityHint("Le film est marqué vu, ou l'épisode coché, et le titre quitte ta soirée")
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
