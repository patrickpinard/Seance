import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Mes listes : à voir, en cours, terminés (EF-16). Les listes personnelles arrivent ensuite.
struct MesListesView: View {
    @Query(sort: \Suivi.ajouteLe, order: .reverse) private var suivis: [Suivi]
    @State private var statut: StatutSuivi = .aVoir

    var body: some View {
        NavigationStack {
            List {
                Picker("Liste", selection: $statut) {
                    Text("À voir").tag(StatutSuivi.aVoir)
                    Text("En cours").tag(StatutSuivi.enCours)
                    Text("Terminés").tag(StatutSuivi.termine)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                let filtres = suivis.filter { $0.statut == statut }
                if filtres.isEmpty {
                    Text("Rien ici pour l'instant.")
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(filtres) { suivi in
                    NavigationLink(value: suivi.reference) {
                        HStack(spacing: 12) {
                            ImageDistante(url: ImageTMDB.url(suivi.cheminAffiche, .affiche), coins: 8)
                                .frame(width: 50, height: 75)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(suivi.titre).font(.headline)
                                Text(suivi.type == .film ? "Film" : "Série")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let note = suivi.note {
                                    Text("Ta note : \(note)/10").font(.caption).foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.fond)
            .navigationTitle("Mes listes")
            .destinationsTitres()
        }
    }
}
