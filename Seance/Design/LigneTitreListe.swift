import SeanceKit
import SwiftUI

/// La vue « liste » des pages de titres (8.6, demande de Patrick : généraliser la bascule cartes / liste de Mes listes) :
/// l'affiche, le titre, une ligne de détail, et où le regarder. Commune à Streaming, aux Nouveautés, aux pages « Tout
/// voir » et aux documentaires.
struct LigneTitreListe: View {
    let titre: TitreResume
    var detail: String?

    @Environment(EtatApp.self) private var etat

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ImageDistante(url: ImageTMDB.url(titre.cheminAffiche, .affiche), coins: 8)
                .frame(width: 56, height: 84)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                if let ou = etat.ou.badges(titre.reference).first.map(BadgeOu.libelle) {
                    Text(ou).font(.caption.weight(.semibold)).foregroundStyle(Theme.texte2).lineLimit(1)
                }
                Text(titre.titre).font(.headline).lineLimit(2)
                Text([titre.reference.type == .film ? "Film" : "Série", detail ?? titre.date.map { String($0.annee) }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: titre.reference) { etat.ou.demander(titre.reference, client: etat.tmdb) }
    }
}

/// La même ligne, pour ce qui n'est pas un titre TMDB tout prêt : une œuvre du NAS, par exemple.
struct LigneTitreCompacte: View {
    let cheminAffiche: String?
    var surtitre: String?
    let titre: String
    var detail: String?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ImageDistante(url: ImageTMDB.url(cheminAffiche, .affiche), coins: 8, symboleVide: "film")
                .frame(width: 56, height: 84)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                if let surtitre { Text(surtitre).font(.caption.weight(.semibold)).foregroundStyle(Theme.texte2).lineLimit(1) }
                Text(titre).font(.headline).lineLimit(2)
                if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Le choix cartes / liste des pages de titres (8.6) : un seul pour toutes ces pages, retenu d'une fois à l'autre.
enum VueTitres {
    static let cle = "titres.enListe"
}
