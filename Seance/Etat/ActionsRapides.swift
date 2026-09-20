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
            var annulation: (@MainActor () -> Void)?
            let (texte, symbole) = try await effectuer(action, sur: titre, annulation: &annulation)
            etat.confirmer(texte, symbole: symbole, annuler: annulation)
            AccessibilityNotification.Announcement(texte).post()
        } catch {
            etat.confirmer("TMDB ne répond pas : réessaie dans un instant", symbole: "exclamationmark.triangle")
            etat.journal.noter(.tmdb, "Une action rapide sur « \(titre.titre) » n'a pas abouti.", erreur: error)
        }
    }

    private func effectuer(
        _ action: Action, sur titre: TitreResume, annulation: inout (@MainActor () -> Void)?
    ) async throws -> (String, String) {
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
            let avant = try suivi.suivi(reference)
            let statutAvant = avant?.statut
            try ServiceGouts(contexte: contexte).jamais(reference, titre: titre.titre)
            annulation = { [contexte] in
                AnnulationTitre.restaurer(reference, existait: avant != nil, statut: statutAvant, contexte: contexte)
            }
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
        Button { etat.titreADater = choisi } label: { Label("Prévoir pour une soirée…", systemImage: "calendar") }
        Button { etat.titrePourListe = choisi } label: { Label("Ajouter à une liste…", systemImage: "list.bullet.rectangle.portrait") }
        Divider()
        Button(role: .destructive) { lancer(.pasInteresse) } label: { Label("Je n'aime pas : ne plus me le proposer", systemImage: "hand.thumbsdown") }
    }

    private var choisi: TitreChoisi {
        TitreChoisi(reference: titre.reference, titre: titre.titre, cheminAffiche: titre.cheminAffiche)
    }

    private func lancer(_ action: ActionsRapides.Action) {
        let actions = ActionsRapides(etat: etat, contexte: contexte)
        let titre = titre
        Task { await actions.executer(action, sur: titre) }
    }
}

extension View {
    /// Appui long sur iPhone, clic droit sur Mac : À voir, Vu, Déjà vu avant, Ma soirée, Je n'aime pas.
    func actionsRapides(_ titre: TitreResume) -> some View {
        contextMenu { MenuActionsTitre(titre: titre) }
    }
}

/// Le message bref d'une action, en bas de l'écran, avec « Annuler » quand l'action se regrette.
struct BandeauConfirmation: View {
    let confirmation: EtatApp.Confirmation
    @Binding var survol: Bool

    @Environment(EtatApp.self) private var etat

    var body: some View {
        HStack(spacing: 14) {
            Label(confirmation.texte, systemImage: confirmation.symbole)
                .font(.subheadline.weight(.semibold))
                .accessibilityHidden(true)
            if confirmation.annuler != nil {
                Button(confirmation.libelleAction) { etat.annulerDerniereAction() }
                    .font(.subheadline.weight(.bold))
                    .tint(Theme.accentClair)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accentClair)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.trait, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .foregroundStyle(.primary)
        // Sur le Mac, un clic sur le bandeau traverserait jusqu'à l'affiche du dessous.
        .onHover { survol = $0 }
        .onDisappear { survol = false }
    }
}

/// Défaire « Pas intéressé » ou « Jamais » : le titre retrouve son état d'avant, ou disparaît s'il n'était suivi nulle part.
enum AnnulationTitre {
    @MainActor
    static func restaurer(_ reference: ReferenceTitre, existait: Bool, statut: StatutSuivi?, contexte: ModelContext) {
        guard let suivi = try? ServiceSuivi(contexte: contexte).suivi(reference) else { return }
        if existait, let statut {
            suivi.statut = statut
        } else {
            contexte.delete(suivi)
        }
        contexte.sauver()
    }
}

/// Tout ce qu'un suivi porte, pour le remettre à l'identique après « Retirer » annulé.
@MainActor
struct InstantaneSuivi {
    let reference: ReferenceTitre
    let titre: String
    let statut: StatutSuivi
    let note: Int?
    let exclusionLangue: Bool
    let ajouteLe: Date
    let cheminAffiche: String?
    let acteurs: [String]
    let acteursIDs: [Int]
    let genres: [Int]
    let alertesActives: Bool
    let modeAlertes: String
    let masque: Bool

    init(_ suivi: Suivi) {
        reference = suivi.reference
        titre = suivi.titre
        statut = suivi.statut
        note = suivi.note
        exclusionLangue = suivi.exclusionLangue
        ajouteLe = suivi.ajouteLe
        cheminAffiche = suivi.cheminAffiche
        acteurs = suivi.acteursPrincipaux
        acteursIDs = suivi.acteursPrincipauxIDs
        genres = suivi.genres
        alertesActives = suivi.alertesActives
        modeAlertes = suivi.modeAlertesBrut
        masque = suivi.masque
    }

    func restaurer(dans contexte: ModelContext) {
        let suivi = Suivi(reference: reference, titre: titre, statut: statut, cheminAffiche: cheminAffiche)
        suivi.note = note
        suivi.exclusionLangue = exclusionLangue
        suivi.ajouteLe = ajouteLe
        suivi.acteursPrincipaux = acteurs
        suivi.acteursPrincipauxIDs = acteursIDs
        suivi.genres = genres
        suivi.alertesActives = alertesActives
        suivi.modeAlertesBrut = modeAlertes
        suivi.masque = masque
        contexte.insert(suivi)
        contexte.sauver()
    }
}
