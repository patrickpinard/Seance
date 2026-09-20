import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Chercher un titre sans quitter « Ajouter à ma soirée » : films et séries mêlés, où les regarder, et « + » sur chaque
/// ligne. Avant, la feuille renvoyait à Explorer avec un mode d'emploi ; on y perdait le fil de la soirée.
@MainActor
@Observable
final class RechercheSoireeModele {
    var texte = ""
    private(set) var resultats: [TitreResume] = []
    private(set) var enCours = false
    /// Le texte dont `resultats` est la réponse : « rien trouvé » ne se dit qu'une fois la réponse arrivée.
    private(set) var cherche = ""

    var texteNettoye: String { texte.trimmingCharacters(in: .whitespacesAndNewlines) }

    func chercher(client: TMDBClient?, ecartes: Set<ReferenceTitre>) async {
        let demande = texteNettoye
        guard let client, demande.count >= 2 else {
            resultats = []
            cherche = ""
            return
        }
        // La frappe se pose avant que TMDB ne soit interrogé.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        enCours = true
        defer { enCours = false }
        async let films = client.rechercherFilms(demande)
        async let series = client.rechercherSeries(demande)
        let trouves = ((try? await films.resultats.map(\.titreResume)) ?? []) + ((try? await series.resultats.map(\.titreResume)) ?? [])
        guard !Task.isCancelled else { return }
        // Les plus connus d'abord, films et séries mêlés ; ce que tu as écarté ne revient pas.
        resultats = Array(trouves.filter { !ecartes.contains($0.reference) && $0.cheminAffiche != nil }
            .sorted { $0.nombreVotes > $1.nombreVotes }
            .prefix(12))
        cherche = demande
    }
}

/// Le champ de recherche de la feuille.
struct ChampRechercheSoiree: View {
    @Bindable var modele: RechercheSoireeModele
    @FocusState private var actif: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Chercher un film ou une série", text: $modele.texte)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($actif)
                .accessibilityIdentifier("rechercheSoiree")
            if !modele.texte.isEmpty {
                Button { modele.texte = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).zoneDeToucher(largeur: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Effacer la recherche")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Les réponses : une ligne par titre, où le regarder dessous, « + » pour la soirée choisie.
struct ResultatsRechercheSoiree: View {
    let modele: RechercheSoireeModele
    /// La soirée à remplir ; `nil` pour ce soir.
    var soiree: String?

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(sort: \SelectionSoir.ajouteLe) private var selections: [SelectionSoir]

    private var retenus: Set<ReferenceTitre> {
        let jour = soiree ?? ServiceSoiree.soiree()
        return Set(selections.filter { $0.soiree == jour }.map(\.reference))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if modele.resultats.isEmpty {
                if modele.enCours || modele.cherche != modele.texteNettoye {
                    MessageEtat(texte: "Recherche…", ton: .attente).padding(.horizontal, -20)
                } else {
                    MessageEtat(texte: "Aucun film ni série de ce nom. Essaie le titre original, ou cherche un acteur dans Explorer.",
                                symbole: "magnifyingglass")
                        .padding(.horizontal, -20)
                }
            }
            ForEach(modele.resultats) { titre in
                ligne(titre)
            }
        }
    }

    private func ligne(_ titre: TitreResume) -> some View {
        let dansLaSoiree = retenus.contains(titre.reference)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                NavigationLink(value: titre.reference) {
                    HStack(spacing: 12) {
                        ImageDistante(url: ImageTMDB.url(titre.cheminAffiche, .affiche), coins: 8)
                            .frame(width: 44, height: 66)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(titre.titre).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                            Text([titre.reference.type == .film ? "Film" : "Série", titre.date.map { String($0.annee) }]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .actionsRapides(titre)
                BoutonIcone(symbole: dansLaSoiree ? "checkmark" : "plus",
                            libelle: dansLaSoiree ? "Retirer \(titre.titre) de la soirée" : "Ajouter \(titre.titre) à la soirée",
                            principal: !dansLaSoiree, actif: dansLaSoiree, taille: 34,
                            explication: dansLaSoiree ? "Déjà dans la soirée : toucher pour le retirer." : "Ajouter ce titre à la soirée choisie.") {
                    let service = ServiceSoiree(contexte: contexte)
                    if dansLaSoiree {
                        try? service.retirer(titre.reference, soiree: soiree)
                    } else {
                        try? service.retenir(titre.reference, titre: titre.titre, cheminAffiche: titre.cheminAffiche, soiree: soiree)
                    }
                }
            }
            ActionsOuRegarder(reference: titre.reference, titre: titre.titre)
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
