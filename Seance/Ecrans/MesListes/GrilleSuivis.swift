import SeanceDonnees
import SeanceKit
import SwiftUI

/// Un titre de Mes listes en affiche, pour la vue en grille : où le regarder en coin, la cloche s'il est surveillé,
/// et sous le titre ce qui compte le plus — son prochain rendez-vous, sinon ta note, sinon où tu en es.
struct AfficheSuivi: View {
    let suivi: Suivi
    /// « S02E09 · dans 3 j » : le prochain rendez-vous du titre.
    let rendezVous: String?
    let episodesVus: Int

    @Environment(EtatApp.self) private var etat

    private var sousTitre: (texte: String, enAvant: Bool) {
        if let rendezVous { return (rendezVous, true) }
        if let note = suivi.note { return ("★ \(note)/10", true) }
        if suivi.type == .serie, episodesVus > 0 { return (Format.pluriel(episodesVus, "épisode vu", "épisodes vus"), false) }
        return (suivi.type == .film ? "Film" : "Série", false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ImageDistante(url: ImageTMDB.url(suivi.cheminAffiche, .affiche))
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    BadgeOu(reference: suivi.reference).padding(5)
                }
                .overlay(alignment: .topTrailing) {
                    if suivi.alertesActives {
                        Image(systemName: "bell.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.accentClair)
                            .padding(5)
                            .background(.black.opacity(0.65), in: Circle())
                            .padding(5)
                            .accessibilityHidden(true)
                    }
                }
                .task(id: suivi.reference) { etat.ou.demander(suivi.reference, client: etat.tmdb) }
            Text(suivi.titre)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(sousTitre.texte)
                .font(.caption)
                .foregroundStyle(sousTitre.enAvant ? AnyShapeStyle(Theme.accentClair) : AnyShapeStyle(.secondary))
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([suivi.titre, sousTitre.texte, suivi.alertesActives ? "alertes activées" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }
}
