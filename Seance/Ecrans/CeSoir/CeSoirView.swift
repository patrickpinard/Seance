import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// « Qu'est-ce que je regarde ce soir ? » (EF-22 à EF-27) : l'app réunit les candidats,
/// Claude les classe et les explique, l'app revérifie tout ce qu'il renvoie.
@MainActor
@Observable
final class CeSoirModele {
    var demande = DemandeCeSoir()
    var resultat: ResultatSuggestions?
    var enCours = false
    var erreur: String?
    private(set) var nombreCandidats = 0
    private(set) var profil = ProfilGouts()

    func chercher(etat: EtatApp, gouts: ServiceGouts, forcerLocal: Bool = false) async {
        guard let tmdb = etat.tmdb, !enCours else { return }
        enCours = true
        erreur = nil
        defer { enCours = false }
        do {
            profil = try gouts.profil()
            let contexte = try gouts.contexteCandidats()
            let candidats = try await CollecteurCandidats(client: tmdb)
                .candidats(pour: demande, profil: profil, contexte: contexte)
            nombreCandidats = candidats.count
            resultat = await ServiceRecommandation(claude: etat.claude).suggerer(
                demande, candidats: candidats, profil: profil,
                nomsGenres: etat.nomsGenres, forcerLocal: forcerLocal
            )
            // Claude configuré mais indisponible : le classement local a pris le relais.
            if let resultat, etat.claude != nil, !forcerLocal, resultat.origine == .local, let avertissement = resultat.avertissement {
                etat.journal.noter(.claude, avertissement, conseil: "Les idées viennent du classement local. Vérifie la clé Claude dans Moi › Claude si cela se répète.")
            }
        } catch is CancellationError {
            return
        } catch {
            resultat = nil
            erreur = Journal.conseil(error) ?? "Impossible de réunir des idées pour l'instant : réessaie dans un moment."
            etat.journal.noter(.tmdb, "« Ce soir » n'a pas pu réunir de suggestions.", erreur: error)
        }
    }

    /// Une suggestion traitée quitte la liste : les autres restent, rien n'est remplacé (EF-25).
    func retirer(_ reference: ReferenceTitre) {
        resultat?.suggestions.removeAll { $0.reference == reference }
        resultat?.repliLocal.removeAll { $0.reference == reference }
    }
}

struct CeSoirView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @State private var modele = CeSoirModele()
    @State private var soiree = SoireeModele()

    private var gouts: ServiceGouts { ServiceGouts(contexte: contexte) }

    var body: some View {
        NavigationStack {
            Group {
                if etat.tmdb == nil {
                    InviteCleTMDB()
                } else {
                    contenu
                }
            }
            .background(Theme.fond)
            .navigationTitle("Ce soir")
            .destinationsTitres()
            .task(id: etat.tmdb != nil) { await soiree.charger(etat: etat, contexte: contexte) }
        }
    }

    private var contenu: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionsSoiree(modele: soiree)

                Label("Une idée pour ce soir ?", systemImage: "sparkles")
                    .font(.title3.weight(.bold))
                    .labelStyle(EtiquetteSection())
                    .padding(.top, 8)

                Demande(demande: $modele.demande, enCours: modele.enCours) {
                    Task { await modele.chercher(etat: etat, gouts: gouts) }
                }

                if let erreur = modele.erreur {
                    MessageEtat(texte: erreur, ton: .probleme)
                        .padding(.horizontal, -20)
                } else if modele.resultat == nil {
                    MessageEtat(
                        texte: modele.enCours
                            ? "Séance réunit les titres disponibles sur tes plateformes…"
                            : "Décris ton envie, choisis film ou série, puis touche « Trouve-moi ça ». Seuls des titres disponibles sur tes plateformes, en français ou sous-titrés, sont proposés.",
                        symbole: "sparkles",
                        ton: modele.enCours ? .attente : .information
                    )
                    .padding(.horizontal, -20)
                }

                if let resultat = modele.resultat {
                    if resultat.suggestions.isEmpty {
                        Vide(resultat: resultat, candidats: modele.nombreCandidats) {
                            Task { await modele.chercher(etat: etat, gouts: gouts, forcerLocal: true) }
                        }
                    } else {
                        ForEach(resultat.suggestions) { suggestion in
                            CarteSuggestion(suggestion: suggestion) { action in
                                traiter(action, suggestion)
                            }
                        }
                        Bandeau(resultat: resultat, profil: modele.profil, candidats: modele.nombreCandidats)
                    }
                }
            }
            .padding(20)
            .animation(.easeOut(duration: 0.25), value: modele.resultat?.suggestions.map(\.id) ?? [])
        }
        // Faire défiler les suggestions range le clavier et rend la barre d'onglets.
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await soiree.charger(etat: etat, contexte: contexte) }
    }

    /// Les trois actions du cahier (EF-26).
    private func traiter(_ action: CarteSuggestion.Action, _ suggestion: SuggestionClassee) {
        switch action {
        case .jeRegarde:
            _ = try? gouts.jeRegarde(suggestion.candidat)
            // « Je regarde » : le titre rejoint la soirée.
            try? ServiceSoiree(contexte: contexte).retenir(suggestion.reference, titre: suggestion.candidat.titre.titre,
                                                           cheminAffiche: suggestion.candidat.titre.cheminAffiche)
        case .pasCeSoir: try? gouts.reporter(suggestion.reference)
        case .jamais: try? gouts.jamais(suggestion.reference, titre: suggestion.candidat.titre.titre)
        }
        modele.retirer(suggestion.reference)
    }
}

// MARK: - Morceaux d'écran

private struct Demande: View {
    @Binding var demande: DemandeCeSoir
    let enCours: Bool
    let chercher: () -> Void
    @FocusState private var saisieActive: Bool

    private static let durees: [(String, Int?)] = [("Peu importe", nil), ("Moins de 1 h 30", 90), ("Moins de 2 h", 120)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("De quoi as-tu envie ?")
                .font(.headline)
            // Le micro du clavier suffit à dicter son envie (EF-22).
            TextField("Un truc nerveux, pas trop long…", text: $demande.envie, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.plain)
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .submitLabel(.search)
                .focused($saisieActive)
                // Champ sur plusieurs lignes : la touche Retour y insère un saut de ligne au lieu de
                // valider. Il est retiré aussitôt, le clavier se range et la recherche part.
                .onChange(of: demande.envie) { _, texte in
                    guard texte.contains("\n") else { return }
                    demande.envie = texte.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                    lancer()
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("OK") { saisieActive = false }
                    }
                }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    PuceFiltre(libelle: "Film ou série", active: demande.type == nil) { demande.type = nil }
                    PuceFiltre(libelle: "Film", active: demande.type == .film) { demande.type = .film }
                    PuceFiltre(libelle: "Série", active: demande.type == .serie) { demande.type = .serie }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.durees, id: \.0) { libelle, minutes in
                        PuceFiltre(libelle: libelle, active: demande.dureeMaxMinutes == minutes) {
                            demande.dureeMaxMinutes = minutes
                        }
                    }
                }
            }

            Button(action: lancer) {
                HStack {
                    Spacer()
                    if enCours {
                        ProgressView().tint(.black)
                    } else {
                        Label("Trouve-moi ça", systemImage: "sparkles")
                            .font(.headline)
                    }
                    Spacer()
                }
                .frame(height: 50)
                .foregroundStyle(.black)
                .background(Theme.degradeAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(enCours)
        }
    }

    private func lancer() {
        saisieActive = false
        guard !enCours else { return }
        chercher()
    }
}

private struct CarteSuggestion: View {
    enum Action { case jeRegarde, pasCeSoir, jamais }

    let suggestion: SuggestionClassee
    let action: (Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: suggestion.reference) {
                HStack(alignment: .top, spacing: 14) {
                    ImageDistante(url: ImageTMDB.url(suggestion.candidat.titre.cheminAffiche, .affiche), coins: 10)
                        .frame(width: 86, height: 129)
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
                        Text(suggestion.phrase)
                            .font(.subheadline)
                            .foregroundStyle(.primary.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                Spacer()
                BoutonIcone(symbole: "hand.thumbsdown", libelle: "Jamais", taille: 40,
                            explication: "Ne plus jamais proposer ce titre. Séance en tient compte pour tes goûts.") { action(.jamais) }
                BoutonIcone(symbole: "clock.arrow.circlepath", libelle: "Pas ce soir", taille: 40,
                            explication: "Écarter ce titre pour ce soir : il pourra revenir dès demain.") { action(.pasCeSoir) }
                BoutonIcone(symbole: "moon.stars.fill", libelle: "Je regarde ce soir", principal: true, taille: 40,
                            explication: "Ajouter ce titre à « Ma soirée » et à Mes listes.") { action(.jeRegarde) }
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct Vide: View {
    let resultat: ResultatSuggestions
    let candidats: Int
    let classementLocal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(resultat.avertissement ?? "Rien ne correspond à cette demande.", systemImage: "questionmark.circle")
                .font(.subheadline)
            Text("\(candidats) titres passés en revue. Élargis ta demande, ou coche d'autres plateformes dans les réglages.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !resultat.repliLocal.isEmpty {
                Button("Voir quand même le classement local", action: classementLocal)
                    .font(.subheadline.weight(.semibold))
                    .tint(Theme.accent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct Bandeau: View {
    let resultat: ResultatSuggestions
    let profil: ProfilGouts
    let candidats: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                resultat.origine == .claude
                    ? "Classé par Claude parmi \(candidats) titres vérifiés."
                    : "Classé sur cet appareil, d'après tes goûts, parmi \(candidats) titres.",
                systemImage: resultat.origine == .claude ? "sparkles" : "person.crop.circle"
            )
            if let avertissement = resultat.avertissement {
                Text(avertissement)
            }
            Text(profil.observations == 0
                 ? "Note ce que tu regardes : les suggestions s'affineront."
                 : "Profil établi sur \(profil.observations) signaux.")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }
}
