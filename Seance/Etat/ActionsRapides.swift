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
        case aVoir, vuAujourdhui, dejaVuAvant, soiree, pasInteresse, jAime
    }

    /// `annulationEnPlus` : ce que l'écran appelant veut défaire aussi — remettre l'idée dans la liste, par exemple.
    func executer(_ action: Action, sur titre: TitreResume, annulationEnPlus: (@MainActor () -> Void)? = nil) async {
        do {
            var annulation: (@MainActor () -> Void)?
            let (texte, symbole) = try await effectuer(action, sur: titre, annulation: &annulation)
            if annulation != nil || annulationEnPlus != nil {
                let defaire = annulation
                annulation = {
                    defaire?()
                    annulationEnPlus?()
                }
            }
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
                annulation = { [contexte] in
                    guard let remis = try? ServiceSuivi(contexte: contexte).suivi(reference) else { return }
                    remis.masque = true
                    contexte.sauver()
                }
                return ("Remis dans ce que tu as regardé", "bookmark.fill")
            }
            annulation = { [contexte] in
                guard let ajoute = try? ServiceSuivi(contexte: contexte).suivi(reference) else { return }
                contexte.delete(ajoute)
                contexte.sauver()
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
            let avantVu = try suivi.suivi(reference)
            let statutAvantVu = avantVu?.statut
            let fiche = try await client().film(reference.tmdbID, complements: [.casting])
            try suivi.marquerVu(film: fiche)
            annulation = { [contexte] in
                try? ServiceSuivi(contexte: contexte).marquerNonVu(film: reference)
                AnnulationTitre.restaurer(reference, existait: avantVu != nil, statut: statutAvantVu, contexte: contexte)
            }
            // 8.2 : « Qui regarde avec toi ? », comme au bout d'une lecture.
            VuEnsemble.demander(etat, reference: reference, titre: titre.titre) { try $0.marquerVu(film: fiche) }
            return ("Marqué vu aujourd'hui", "eye.fill")

        case .dejaVuAvant:
            if try suivi.estVu(reference), reference.type == .film { return ("Déjà marqué vu", "eye.fill") }
            switch reference.type {
            case .film:
                let avantDejaVu = try suivi.suivi(reference)
                let statutAvantDejaVu = avantDejaVu?.statut
                try suivi.marquerVu(film: try await client().film(reference.tmdbID, complements: [.casting]), anterieur: true)
                annulation = { [contexte] in
                    try? ServiceSuivi(contexte: contexte).marquerNonVu(film: reference)
                    AnnulationTitre.restaurer(reference, existait: avantDejaVu != nil, statut: statutAvantDejaVu, contexte: contexte)
                }
                return ("Marqué déjà vu avant", "clock.arrow.circlepath")
            case .serie:
                // La même action que sur l'Apple TV (8.2.15) : épisodes diffusés cochés, série rangée dans Terminés.
                try await ActionsCommunes.dejaVuAvant(reference, contexte: contexte, tmdb: try client())
                return ("Série marquée déjà vue avant", "clock.arrow.circlepath")
            }

        case .soiree:
            try ServiceSoiree(contexte: contexte).retenir(reference, titre: titre.titre, cheminAffiche: titre.cheminAffiche)
            annulation = { [contexte] in try? ServiceSoiree(contexte: contexte).retirer(reference) }
            return ("Ajouté à ma soirée", "moon.stars.fill")

        case .jAime:
            let gouts = ServiceGouts(contexte: contexte)
            if try gouts.estAime(reference) { return ("Tu l'aimes déjà", "hand.thumbsup.fill") }
            try gouts.aimer(reference, titre: titre.titre, cheminAffiche: titre.cheminAffiche, genres: titre.genres)
            annulation = { [contexte] in try? ServiceGouts(contexte: contexte).nePlusAimer(reference) }
            return ("Noté : tes suggestions en tiendront compte", "hand.thumbsup.fill")

        case .pasInteresse:
            let avant = try suivi.suivi(reference)
            let statutAvant = avant?.statut
            try ServiceGouts(contexte: contexte).jamais(reference, titre: titre.titre, genres: titre.genres, cheminAffiche: titre.cheminAffiche)
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
    @Environment(\.ouvrirFiche) private var ouvrirFiche

    /// 8.2.15 : la liste commune à l'iPhone, l'iPad, le Mac et l'Apple TV (`ActionTitre`), dans le même ordre et avec
    /// les mêmes mots ; ce que montre le menu dépend de ce que Séance sait déjà du titre.
    private var etatMenu: ActionTitre.Etat {
        let reference = titre.reference
        let suivi = try? ServiceSuivi(contexte: contexte).suivi(reference)
        let ceSoir = ServiceSoiree.soiree()
        let prevu = ((try? contexte.fetch(FetchDescriptor<SelectionSoir>(predicate: #Predicate { $0.soiree == ceSoir }))) ?? [])
            .contains { $0.reference == reference }
        return ActionTitre.Etat(dansMaListe: suivi.map { !$0.masque && $0.statut != .exclu } ?? false,
                                vu: reference.type == .film && ((try? ServiceSuivi(contexte: contexte).estVu(reference)) ?? false),
                                prevuCeSoir: prevu)
    }

    var body: some View {
        MenuJourChoisi(titre: choisi)
        let etatMenu = etatMenu
        let type = titre.reference.type
        ForEach(ActionTitre.menu(type, etat: etatMenu), id: \.self) { action in
            if action.ouvreUnGroupe { Divider() }
            Button(role: action.destructive ? .destructive : nil) { executer(action) } label: {
                Label(action.libelle(type, etat: etatMenu), systemImage: action.symbole)
            }
        }
    }

    /// Chaque action du menu commun : un `switch` sans `default`, pour qu'aucune ne soit oubliée ici.
    private func executer(_ action: ActionTitre) {
        switch action {
        case .regarder: regarder()
        case .voirFiche: voirFiche()
        case .aVoir: lancer(.aVoir)
        case .vuAujourdhui: lancer(.vuAujourdhui)
        case .dejaVuAvant: lancer(.dejaVuAvant)
        case .ceSoir: lancer(.soiree)
        case .autreSoir: etat.titreADater = choisi
        case .pasInteresse:
            // Pas un goût, juste « pas maintenant » : il reviendra dans deux mois (8.2.11).
            let reference = titre.reference
            PasInteresse.ecarter(reference)
            etat.confirmer("« \(titre.titre) » ne sera plus proposé pendant deux mois", symbole: "hand.raised") {
                PasInteresse.reproposer(reference)
            }
        case .jAime: lancer(.jAime)
        case .jeNaimePas: lancer(.pasInteresse)
        }
    }

    private func voirFiche() {
        if let ouvrirFiche { ouvrirFiche(titre.reference) } else { etat.ficheDemandee = titre.reference }
    }

    /// Regarder : le film ou le prochain épisode du NAS, dans le lecteur de Séance ; sinon la fiche, dont le grand
    /// bouton lance la plateforme ou la chaîne.
    private func regarder() {
        #if !targetEnvironment(macCatalyst)
        let reference = titre.reference
        let id: Int? = reference.tmdbID
        let type = reference.type.rawValue
        let fichiers = ((try? contexte.fetch(FetchDescriptor<FichierNAS>(predicate: #Predicate { $0.tmdbID == id && $0.typeBrut == type }))) ?? [])
            .sorted { ($0.saison ?? 0, $0.episode ?? 0) < ($1.saison ?? 0, $1.episode ?? 0) }
        let vus = (try? ServiceSuivi(contexte: contexte).episodesVus(reference)) ?? []
        let aLire = reference.type == .film ? fichiers.first : fichiers.first { fichier in
            guard let saison = fichier.saison, let episode = fichier.episode else { return false }
            return !vus.contains(NumeroEpisode(saison: saison, episode: episode))
        } ?? fichiers.first
        if let aLire, etat.nas.motDePasse != nil {
            etat.nas.noterLecture(aLire)
            return etat.lire(aLire)
        }
        #endif
        voirFiche()
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

extension EnvironmentValues {
    /// Ouvre une fiche dans la pile de la page (8.2.15) : « Voir la fiche » du menu d'un titre. Sans elle, la fiche
    /// s'ouvre dans l'accueil.
    @Entry var ouvrirFiche: ((ReferenceTitre) -> Void)? = nil
}

/// Dans Regarder, un autre jour choisi dans la rangée (25.09.2026) : le titre se prévoit pour ce soir-là d'un geste,
/// sans passer par le calendrier.
struct MenuJourChoisi: View {
    let titre: TitreChoisi

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Environment(\.dansRegarder) private var dansRegarder

    var body: some View {
        if dansRegarder, let jour = etat.jourRegarder {
            Button { PrevoirSoiree.prevoir(titre, le: jour, etat: etat, contexte: contexte) } label: {
                Label("Prévoir pour \(LibelleSoiree.jour(jour).lowercased())", systemImage: "calendar.badge.plus")
            }
            Divider()
        }
    }
}

/// Le menu d'une œuvre sans résumé TMDB (le NAS) : prévoir pour le jour choisi, ce soir, ou une autre soirée.
struct MenuSoireeTitre: View {
    let titre: TitreChoisi

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte

    var body: some View {
        MenuJourChoisi(titre: titre)
        Button { PrevoirSoiree.prevoir(titre, le: .now, etat: etat, contexte: contexte) } label: {
            Label("Ce soir", systemImage: "moon.stars")
        }
        Button { etat.titreADater = titre } label: { Label("Prévoir pour une soirée…", systemImage: "calendar") }
    }
}

extension View {
    /// Appui long sur iPhone, clic droit sur Mac, pour une œuvre du NAS.
    func menuSoiree(_ titre: TitreChoisi) -> some View {
        contextMenu { MenuSoireeTitre(titre: titre) }
    }

    /// Appui long sur iPhone, clic droit sur Mac : À voir, Vu, Déjà vu avant, Ma soirée, Je n'aime pas.
    func actionsRapides(_ titre: TitreResume) -> some View {
        contextMenu { MenuActionsTitre(titre: titre) }
    }

    /// Les glissements d'une carte ou d'une ligne de titre (8.6), sur les pages en grille : vers la droite « Ce soir »
    /// et « Ma liste », vers la gauche « Pas intéressé » — le titre quitte la page pour deux mois, avec « Annuler ».
    /// Pas sur les rangées qui défilent de côté : le geste y fait défiler.
    func glissementsTitre(_ titre: TitreResume) -> some View {
        modifier(GlissementsTitre(titre: titre))
    }
}

private struct GlissementsTitre: ViewModifier {
    let titre: TitreResume
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte

    func body(content: Content) -> some View {
        let actions = ActionsRapides(etat: etat, contexte: contexte)
        let titre = titre
        content.glissementsCarte(
            debut: [
                ActionGlissee(libelle: "Ce soir", symbole: "moon.stars.fill", couleur: Theme.accent) {
                    Task { await actions.executer(.soiree, sur: titre) }
                },
                ActionGlissee(libelle: "Ma liste", symbole: "plus", couleur: Theme.eleve) {
                    Task { await actions.executer(.aVoir, sur: titre) }
                },
            ],
            fin: [
                ActionGlissee(libelle: "Pas intéressé", symbole: "hand.raised", couleur: Theme.rouge, destructive: true) {
                    let reference = titre.reference
                    PasInteresse.ecarter(reference)
                    etat.confirmer("« \(titre.titre) » ne sera plus proposé pendant deux mois", symbole: "hand.raised") {
                        PasInteresse.reproposer(reference)
                    }
                },
            ])
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
