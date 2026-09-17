import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Les actions d'une fiche, sans l'ouvrir : appui long sur une affiche (iPhone), clic droit (Mac).
/// La fiche TMDB est lue au passage pour que le suivi garde le casting et la durée, comme depuis la fiche.
@MainActor
struct ActionsRapides {
    let etat: EtatApp
    let contexte: ModelContext

    enum Action {
        case aVoir, vuAujourdhui, dejaVuAvant, soiree, pasInteresse
    }

    func executer(_ action: Action, sur titre: TitreResume) async {
        do {
            let (texte, symbole) = try await effectuer(action, sur: titre)
            etat.confirmer(texte, symbole: symbole)
            AccessibilityNotification.Announcement(texte).post()
        } catch {
            etat.confirmer("TMDB ne répond pas : réessaie dans un instant", symbole: "exclamationmark.triangle")
            etat.journal.noter(.tmdb, "Une action rapide sur « \(titre.titre) » n'a pas abouti.", erreur: error)
        }
    }

    private func effectuer(_ action: Action, sur titre: TitreResume) async throws -> (String, String) {
        let suivi = ServiceSuivi(contexte: contexte)
        let reference = titre.reference
        switch action {
        case .aVoir:
            if let existant = try suivi.suivi(reference) {
                guard existant.masque else { return ("Déjà dans Mes listes", "bookmark.fill") }
                existant.masque = false
                try contexte.save()
                return ("Remis dans Terminés", "bookmark.fill")
            }
            switch reference.type {
            case .film: try suivi.suivre(film: try await client().film(reference.tmdbID, complements: [.casting]))
            case .serie: try suivi.suivre(serie: try await client().serie(reference.tmdbID, complements: [.casting]))
            }
            // Comme depuis la fiche : suivre un titre, c'est vouloir être prévenu (EF-81).
            Task {
                await etat.alertes.demanderAutorisation()
                await etat.alertes.planifier(contexte: contexte, tmdb: etat.tmdb)
            }
            return ("Ajouté à À voir", "plus.circle.fill")

        case .vuAujourdhui:
            try suivi.marquerVu(film: try await client().film(reference.tmdbID, complements: [.casting]))
            return ("Marqué vu aujourd'hui", "eye.fill")

        case .dejaVuAvant:
            if try suivi.estVu(reference), reference.type == .film { return ("Déjà marqué vu", "eye.fill") }
            switch reference.type {
            case .film:
                try suivi.marquerVu(film: try await client().film(reference.tmdbID, complements: [.casting]), anterieur: true)
                return ("Marqué déjà vu avant", "clock.arrow.circlepath")
            case .serie:
                let tmdb = try client()
                let serie = try await tmdb.serie(reference.tmdbID, complements: [.casting])
                let aujourdhui = DateTMDB(.now)
                var episodes: [EpisodeTMDB] = []
                for saison in serie.saisons where saison.numero > 0 && saison.nombreEpisodes > 0 {
                    episodes += try await tmdb.saison(saison.numero, serie: serie.id).episodes
                }
                let diffuses = episodes.filter { $0.dateDiffusion.map { $0 <= aujourdhui } ?? false }
                try suivi.cocher(diffuses, serie: serie, anterieur: true)
                return ("Série marquée déjà vue avant", "clock.arrow.circlepath")
            }

        case .soiree:
            try ServiceSoiree(contexte: contexte).retenir(reference, titre: titre.titre, cheminAffiche: titre.cheminAffiche)
            return ("Ajouté à ma soirée", "moon.stars.fill")

        case .pasInteresse:
            try ServiceGouts(contexte: contexte).jamais(reference, titre: titre.titre)
            return ("Ne te sera plus proposé", "hand.thumbsdown.fill")
        }
    }

    private func client() throws -> TMDBClient {
        guard let tmdb = etat.tmdb else { throw ErreurTMDB.identifiantsRefuses }
        return tmdb
    }
}

/// Le menu lui-même, identique partout.
struct MenuActionsTitre: View {
    let titre: TitreResume

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte

    var body: some View {
        Button { lancer(.aVoir) } label: { Label("Ajouter à voir", systemImage: "plus") }
        if titre.reference.type == .film {
            Button { lancer(.vuAujourdhui) } label: { Label("Vu aujourd'hui", systemImage: "eye") }
            Button { lancer(.dejaVuAvant) } label: { Label("Déjà vu avant", systemImage: "clock.arrow.circlepath") }
        } else {
            Button { lancer(.dejaVuAvant) } label: { Label("Toute la série déjà vue avant", systemImage: "clock.arrow.circlepath") }
        }
        Button { lancer(.soiree) } label: { Label("Ajouter à ma soirée", systemImage: "moon.stars") }
        Divider()
        Button(role: .destructive) { lancer(.pasInteresse) } label: { Label("Pas intéressé", systemImage: "hand.thumbsdown") }
    }

    private func lancer(_ action: ActionsRapides.Action) {
        let actions = ActionsRapides(etat: etat, contexte: contexte)
        let titre = titre
        Task { await actions.executer(action, sur: titre) }
    }
}

extension View {
    /// Appui long sur iPhone, clic droit sur Mac : À voir, Vu, Déjà vu avant, Ma soirée, Pas intéressé.
    func actionsRapides(_ titre: TitreResume) -> some View {
        contextMenu { MenuActionsTitre(titre: titre) }
    }
}

/// Le message bref d'une action rapide, en bas de l'écran.
struct BandeauConfirmation: View {
    let confirmation: EtatApp.Confirmation

    var body: some View {
        Label(confirmation.texte, systemImage: confirmation.symbole)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .foregroundStyle(.primary)
            .accessibilityHidden(true)
    }
}
