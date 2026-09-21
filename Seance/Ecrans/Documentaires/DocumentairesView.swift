import SeanceKit
import SwiftUI

/// Les documentaires (EF-151, EF-154) : la troisième catégorie, avec ses thèmes. TMDB n'a pas de sous-genres de
/// documentaires — un thème est un jeu de mots-clés (EF-152) —, et le badge « où regarder » s'applique ici comme
/// ailleurs. Ils restent hors des idées du soir : ils ont leurs propres suggestions (EF-156).
struct DocumentairesView: View {
    @Environment(EtatApp.self) private var etat
    @State private var type: TypeTitre?

    private var titres: [TitreResume] {
        switch type {
        case .film: etat.documentaires.films
        case .serie: etat.documentaires.series
        case nil: etat.documentaires.films + etat.documentaires.series
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let erreur = etat.documentaires.erreur {
                    MessageEtat(texte: erreur, ton: .probleme, libelleAction: "Réessayer") { recharger() }
                        .padding(.horizontal, 20)
                }
                themes
                if etat.documentaires.enCours, titres.isEmpty {
                    ProgressView("Lecture des documentaires…").frame(maxWidth: .infinity).padding(.top, 60)
                } else if titres.isEmpty {
                    EtatVide(symbole: "film.stack", titre: "Aucun documentaire",
                             message: "Aucun documentaire ne correspond à ces thèmes. Décoche-en un, ou laisse « tous les thèmes ».",
                             libelleAction: "Relire", symboleAction: "arrow.clockwise") { recharger() }
                        .padding(.horizontal, 20)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 290, maximum: 520), spacing: 14, alignment: .top)], spacing: 14) {
                        ForEach(titres) { titre in
                            NavigationLink(value: titre.reference) {
                                CarteLargeTitre(titre)
                            }
                            .buttonStyle(.plain)
                            .actionsRapides(titre)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 40)
        }
        .background(Theme.fond)
        .navigationTitle("Documentaires")
        .navigationBarTitleDisplayMode(.inline)
        .task { await etat.documentaires.charger(client: etat.tmdb, plateformes: nil) }
        .task(id: titres.map(\.reference)) { await etat.decors.charger(titres.map(\.reference), client: etat.tmdb) }
    }

    /// Les thèmes cochés (EF-152) : aucun coché veut dire « tous ».
    private var themes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ce qui t'intéresse")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Le composant de la charte pour un filtre qu'on allume.
                    ForEach(ThemeDocumentaire.allCases) { theme in
                        PuceFiltre(libelle: theme.libelle, active: etat.documentaires.themes.contains(theme)) {
                            etat.documentaires.basculer(theme)
                            recharger()
                        }
                        .zoneDeToucher()
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func recharger() {
        Task { await etat.documentaires.charger(client: etat.tmdb, plateformes: nil) }
    }
}
