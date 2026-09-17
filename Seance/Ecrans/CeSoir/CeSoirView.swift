import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// « Ce soir » : ta soirée, ce qu'il ne faut pas manquer, tes épisodes, les titres de ta liste regardables,
/// puis des idées choisies selon tes goûts. Pour chercher autre chose, Explorer.
struct CeSoirView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @State private var soiree = SoireeModele()
    @State private var idees = IdeesModele()

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
            .boutonBarreLaterale()
            .destinationsTitres()
            .task(id: etat.tmdb != nil) { await soiree.charger(etat: etat, contexte: contexte) }
        }
    }

    private var contenu: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionsSoiree(modele: soiree)
                SectionIdees(modele: idees, dejaMontres: dejaMontres)
                autreChose
            }
            .padding(20)
        }
        .refreshable { await soiree.charger(etat: etat, contexte: contexte) }
    }

    @Query(sort: \SelectionSoir.ajouteLe) private var selections: [SelectionSoir]

    /// Ma soirée et ta liste regardable : les idées ne les répètent pas.
    private var dejaMontres: Set<ReferenceTitre> {
        let jour = ServiceSoiree.soiree()
        return Set(selections.filter { $0.soiree == jour }.map(\.reference))
            .union(soiree.disponibles.map(\.id))
            .union(soiree.episodes.map(\.id))
    }

    private var autreChose: some View {
        Button { etat.ongletDemande = .explorer } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(Theme.accent.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Envie d'autre chose ?").font(.headline)
                    Text("Cherche un film ou une série dans Explorer, puis touche 🌙 sur sa fiche.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}
