import SeanceKit
import SwiftUI

/// Explorer, première version : recherche de films, séries et personnes (EF-05, EF-52).
/// La feuille de filtres de la maquette arrive à l'étape suivante.
struct ExplorerView: View {
    @Environment(EtatApp.self) private var etat
    @State private var texte = ""
    @State private var titres: [TitreResume] = []
    @State private var personnes: [PersonneResume] = []

    private let colonnes = [GridItem(.adaptive(minimum: 105), spacing: 12, alignment: .top)]

    var body: some View {
        NavigationStack {
            Group {
                if etat.tmdb == nil {
                    InviteCleTMDB()
                } else if texte.count < 2 {
                    ContentUnavailableView("Films, séries, personnes", systemImage: "magnifyingglass",
                                           description: Text("Tape au moins deux caractères."))
                } else {
                    ScrollView {
                        if !personnes.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(personnes) { personne in
                                        HStack(spacing: 6) {
                                            ImageDistante(url: ImageTMDB.url(personne.cheminPortrait, .portrait), coins: 14)
                                                .frame(width: 28, height: 28)
                                            Text(personne.nom).font(.subheadline.weight(.semibold))
                                        }
                                        .padding(.trailing, 12).padding(.leading, 3)
                                        .frame(height: 34)
                                        .background(Theme.surface, in: Capsule())
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        LazyVGrid(columns: colonnes, spacing: 18) {
                            ForEach(titres) { titre in
                                NavigationLink(value: titre.reference) {
                                    CarteAffiche(titre: titre, largeur: nil)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .background(Theme.fond)
            .navigationTitle("Explorer")
            .searchable(text: $texte, prompt: "Films, séries, personnes")
            .task(id: texte) { await rechercher() }
            .destinationsTitres()
        }
    }

    private func rechercher() async {
        guard let client = etat.tmdb, texte.count >= 2 else { return }
        // Attente courte : on ne cherche qu'une fois la frappe terminée.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        let resultats = (try? await client.rechercherTout(texte)) ?? []
        titres = resultats.compactMap(\.titre)
        personnes = resultats.compactMap(\.personne)
    }
}
