import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// « Idées pour ce soir » (EF-22 à EF-27) : des titres regardables sur tes plateformes, classés selon tes goûts, tes
/// notes et ce que tu as écarté. Sans clé Claude, tout se fait sur l'appareil ; avec, Claude lit l'envie précisée.
@MainActor
@Observable
final class IdeesModele {
    var demande = DemandeCeSoir()
    private(set) var resultat: ResultatSuggestions?
    /// Idées traitées (« je regarde », « pas ce soir », « jamais ») : la liste affiche les suivantes à leur place.
    private(set) var retirees: [ReferenceTitre] = []
    /// Où regarder chaque idée, lu sur TMDB après le classement.
    private(set) var ou: [ReferenceTitre: EtatDisponibilite] = [:]
    private(set) var enCours = false
    private(set) var erreur: String?
    private(set) var nombreCandidats = 0
    private(set) var profil = ProfilGouts()
    /// Déjà chargé une fois : revenir sur l'onglet ne relance pas la recherche.
    private(set) var charge = false

    /// Sans envie précisée, le classement reste local : pas d'appel payant à Claude à chaque ouverture.
    func chercher(etat: EtatApp, contexte: ModelContext, precise: Bool = false) async {
        guard let tmdb = etat.tmdb, !enCours else { return }
        enCours = true
        erreur = nil
        defer {
            enCours = false
            charge = true
        }
        let gouts = ServiceGouts(contexte: contexte)
        do {
            profil = try gouts.profil()
            let exclusions = try gouts.contexteCandidats()
            let candidats = try await CollecteurCandidats(client: tmdb).candidats(pour: demande, profil: profil, contexte: exclusions)
            nombreCandidats = candidats.count
            let claude = precise && !demande.envieNettoyee.isEmpty ? etat.claude : nil
            // Douze idées classées, cinq affichées : chaque idée traitée laisse sa place à la suivante.
            let nouveau = await ServiceRecommandation(claude: claude, nombre: 12)
                .suggerer(demande, candidats: candidats, profil: profil, nomsGenres: etat.nomsGenres)
            resultat = nouveau
            retirees = []
            ou = await Self.disponibilites(nouveau.suggestions.map(\.reference), tmdb: tmdb, contexte: contexte)
            if let resultat, claude != nil, resultat.origine == .local, let avertissement = resultat.avertissement {
                etat.journal.noter(.claude, avertissement, conseil: "Les idées viennent du classement local. Vérifie la clé Claude dans Réglages › Claude si cela se répète.")
            }
        } catch is CancellationError {
            return
        } catch {
            resultat = nil
            erreur = Journal.conseil(error) ?? "Impossible de réunir des idées pour l'instant : réessaie dans un moment."
            etat.journal.noter(.tmdb, "« Idées pour ce soir » n'a pas pu réunir de suggestions.", erreur: error)
        }
    }

    /// Une idée traitée quitte la liste ; les autres restent (EF-25).
    func retirer(_ reference: ReferenceTitre) {
        if !retirees.contains(reference) { retirees.append(reference) }
    }

    /// « Annuler » : l'idée reprend sa place.
    func restaurer(_ reference: ReferenceTitre) {
        retirees.removeAll { $0 == reference }
    }

    /// « Sur Netflix », « Sur ton NAS · 4K », « Ce soir sur M6 » : le libellé d'une idée, ou `nil` si rien n'est su.
    func libelleOu(_ reference: ReferenceTitre) -> String? {
        guard let etat = ou[reference], let libelle = RegardableCeSoir.libelle(etat) else { return nil }
        switch etat {
        case .dansAbonnements: return "Sur \(libelle)"
        case .aLaTeleBientot: return "Ce soir sur \(libelle)"
        default: return libelle
        }
    }

    /// Les plateformes de chaque idée, six appels à la fois ; une idée sans réponse reste sans libellé.
    private static func disponibilites(_ references: [ReferenceTitre], tmdb: TMDBClient, contexte: ModelContext) async -> [ReferenceTitre: EtatDisponibilite] {
        let offres = await withTaskGroup(of: (ReferenceTitre, OffresRegion?).self) { groupe in
            var reste = references[...]
            func lancer(_ reference: ReferenceTitre) {
                groupe.addTask { (reference, try? await tmdb.fournisseurs(reference.type, id: reference.tmdbID).offres()) }
            }
            for _ in 0..<6 {
                guard let reference = reste.popFirst() else { break }
                lancer(reference)
            }
            var resultat: [ReferenceTitre: OffresRegion] = [:]
            while let (reference, offre) = await groupe.next() {
                if let offre { resultat[reference] = offre }
                if let suivante = reste.popFirst() { lancer(suivante) }
            }
            return resultat
        }
        let disponibilite = ServiceDisponibilite(contexte: contexte)
        var etats: [ReferenceTitre: EtatDisponibilite] = [:]
        for reference in references {
            if let etat = try? disponibilite.etat(reference, offres: offres[reference]) { etats[reference] = etat }
        }
        return etats
    }
}

struct SectionIdees: View {
    let modele: IdeesModele
    /// Titres déjà montrés plus haut dans « Ce soir » : une idée ne les répète pas.
    let dejaMontres: Set<ReferenceTitre>
    /// « Je regarde » : la soirée apprend où regarder le titre, pour l'afficher sous son nom.
    let jeRegarde: (ReferenceTitre, String?) -> Void

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @State private var precisionOuverte = false

    /// Cinq idées à la fois, parmi celles ni traitées ni déjà montrées plus haut.
    private var idees: [SuggestionClassee] {
        Array((modele.resultat?.suggestions ?? [])
            .filter { !modele.retirees.contains($0.reference) && !dejaMontres.contains($0.reference) }
            .prefix(5))
    }

    var body: some View {
        @Bindable var modele = modele
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Idées pour ce soir", systemImage: "sparkles")
                    .font(.title3.weight(.bold))
                    .labelStyle(EtiquetteSection())
                Spacer()
                Button {
                    Task { await modele.chercher(etat: etat, contexte: contexte, precise: !modele.demande.envieNettoyee.isEmpty) }
                } label: {
                    Label("Autres idées", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .disabled(modele.enCours)
                .help("Chercher d'autres idées")
            }

            if modele.profil.estVide, modele.charge {
                MessageEtat(texte: "Choisis tes goûts dans Profil › Mes goûts, et note ce que tu regardes : les idées seront sur mesure.",
                            symbole: "heart")
                    .padding(.horizontal, -20)
            }

            if let erreur = modele.erreur {
                MessageEtat(texte: erreur, ton: .probleme)
                    .padding(.horizontal, -20)
            } else if modele.enCours, idees.isEmpty {
                MessageEtat(texte: "Séance cherche sur tes plateformes ce qui te ressemble…", ton: .attente)
                    .padding(.horizontal, -20)
            } else if modele.charge, idees.isEmpty {
                MessageEtat(texte: modele.resultat?.avertissement ?? "Rien de nouveau ne correspond pour l'instant. Précise ton envie ou coche d'autres plateformes.",
                            symbole: "sparkles")
                    .padding(.horizontal, -20)
            }

            ForEach(idees) { suggestion in
                CarteIdee(suggestion: suggestion, ou: modele.libelleOu(suggestion.reference)) { action in traiter(action, suggestion) }
            }

            DisclosureGroup(isExpanded: $precisionOuverte) {
                PrecisionEnvie(demande: $modele.demande, enCours: modele.enCours, avecClaude: etat.claude != nil) {
                    Task { await modele.chercher(etat: etat, contexte: contexte, precise: true) }
                }
                .padding(.top, 10)
            } label: {
                Label("Préciser ton envie", systemImage: "text.bubble")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(Theme.accentClair)

            if let resultat = modele.resultat, !idees.isEmpty {
                Text(resultat.origine == .claude
                     ? "Choisies par Claude parmi \(modele.nombreCandidats) titres disponibles sur tes plateformes."
                     : "Classées sur cet appareil selon tes goûts, parmi \(modele.nombreCandidats) titres disponibles sur tes plateformes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: etat.tmdb != nil) {
            if !modele.charge { await modele.chercher(etat: etat, contexte: contexte) }
        }
        .animation(.easeOut(duration: 0.25), value: idees.map(\.id))
    }

    /// Les trois actions du cahier (EF-26), avec annulation.
    private func traiter(_ action: CarteIdee.Action, _ suggestion: SuggestionClassee) {
        let gouts = ServiceGouts(contexte: contexte)
        let reference = suggestion.reference
        let titre = suggestion.candidat.titre
        let avant = try? ServiceSuivi(contexte: contexte).suivi(reference)
        let statutAvant = avant?.statut
        switch action {
        case .jeRegarde:
            _ = try? gouts.jeRegarde(suggestion.candidat)
            try? ServiceSoiree(contexte: contexte).retenir(reference, titre: titre.titre, cheminAffiche: titre.cheminAffiche)
            jeRegarde(reference, modele.libelleOu(reference))
            etat.confirmer("Ajouté à ma soirée", symbole: "moon.stars.fill")
        case .pasCeSoir:
            try? gouts.reporter(reference)
            etat.confirmer("Écarté pour ce soir", symbole: "clock.arrow.circlepath") { [modele, contexte] in
                try? ServiceGouts(contexte: contexte).annulerReport(reference)
                modele.restaurer(reference)
            }
        case .jamais:
            try? gouts.jamais(reference, titre: titre.titre)
            etat.confirmer("Ne te sera plus proposé", symbole: "hand.thumbsdown.fill") { [modele, contexte] in
                AnnulationTitre.restaurer(reference, existait: avant != nil, statut: statutAvant, contexte: contexte)
                modele.restaurer(reference)
            }
        }
        modele.retirer(reference)
    }
}

/// Une idée : affiche, titre, où la regarder, raison en une phrase, et les trois gestes du soir.
private struct CarteIdee: View {
    enum Action { case jeRegarde, pasCeSoir, jamais }

    let suggestion: SuggestionClassee
    let ou: String?
    let action: (Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: suggestion.reference) {
                HStack(alignment: .top, spacing: 14) {
                    ImageDistante(url: ImageTMDB.url(suggestion.candidat.titre.cheminAffiche, .affiche), coins: 10)
                        .frame(width: 72, height: 108)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(suggestion.candidat.titre.titre)
                            .font(.headline)
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            if suggestion.candidat.titre.nombreVotes > 0 {
                                AnneauNote(pourcentage: suggestion.candidat.titre.pourcentageNote, diametre: 30)
                            }
                            if let annee = suggestion.candidat.titre.date?.annee {
                                Text(String(annee))
                            }
                            Text(suggestion.reference.type == .film ? "Film" : "Série")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if let ou {
                            Label(ou, systemImage: ou.hasPrefix("Ce soir") ? "tv" : ou.hasPrefix("Sur le NAS") ? "externaldrive.fill" : "play.tv")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                        Text(suggestion.phrase)
                            .font(.subheadline)
                            .foregroundStyle(.primary.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .actionsRapides(suggestion.candidat.titre)

            // Compact sur l'iPhone : deux icônes rondes (nom à l'appui long) et un seul bouton écrit, sur une ligne.
            HStack(spacing: 10) {
                Spacer()
                BoutonIcone(symbole: "hand.thumbsdown", libelle: "Jamais", taille: 36,
                            explication: "Ne plus jamais proposer ce titre. Séance en tient compte pour tes goûts.") { action(.jamais) }
                BoutonIcone(symbole: "clock.arrow.circlepath", libelle: "Pas ce soir", taille: 36,
                            explication: "L'écarter pour ce soir : il pourra revenir dès demain.") { action(.pasCeSoir) }
                Button { action(.jeRegarde) } label: {
                    Label("Je regarde", systemImage: "moon.stars.fill")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(Theme.degradeAccent, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Ajouter à ma soirée et à Mes listes")
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// L'envie en quelques mots, film ou série, durée maximale.
private struct PrecisionEnvie: View {
    @Binding var demande: DemandeCeSoir
    let enCours: Bool
    let avecClaude: Bool
    let chercher: () -> Void
    @FocusState private var saisieActive: Bool

    private static let durees: [(String, Int?)] = [("Peu importe", nil), ("Moins de 1 h 30", 90), ("Moins de 2 h", 120)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Un truc nerveux, pas trop long…", text: $demande.envie)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Theme.fond.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused($saisieActive)
                .submitLabel(.search)
                .onSubmit(lancer)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    PuceFiltre(libelle: "Film ou série", active: demande.type == nil) { demande.type = nil }
                    PuceFiltre(libelle: "Film", active: demande.type == .film) { demande.type = .film }
                    PuceFiltre(libelle: "Série", active: demande.type == .serie) { demande.type = .serie }
                    ForEach(Self.durees, id: \.0) { libelle, minutes in
                        PuceFiltre(libelle: libelle, active: demande.dureeMaxMinutes == minutes) { demande.dureeMaxMinutes = minutes }
                    }
                }
            }
            Button(action: lancer) {
                HStack {
                    Spacer()
                    if enCours {
                        ProgressView().tint(.black)
                    } else {
                        Label("Trouve-moi ça", systemImage: "sparkles").font(.headline)
                    }
                    Spacer()
                }
                .frame(height: 44)
                .foregroundStyle(.black)
                .background(Theme.degradeAccent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(enCours)
            Text(avecClaude
                 ? "Claude lit ton envie et choisit parmi les titres disponibles (environ 0,07 $ la demande)."
                 : "Classement sur l'appareil. Ajoute une clé Claude dans Réglages pour qu'il lise ton envie.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func lancer() {
        saisieActive = false
        guard !enCours else { return }
        chercher()
    }
}
