import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Ce qui te concerne, à part des réglages de l'app : tes goûts, tes acteurs suivis, tes statistiques et ton bilan de l'année.
/// Sur l'iPhone, l'engrenage ouvre Réglages, qui n'a pas d'onglet à lui.
struct ProfilView: View {
    @Environment(\.horizontalSizeClass) private var classeTaille
    @Query private var interets: [Interet]
    @Query private var visionnages: [Visionnage]
    @Query private var acteursSuivis: [ActeurSuivi]
    @State private var gouts = false
    @State private var bilan = false

    private static let annee = Calendar.current.component(.year, from: .now)

    var body: some View {
        NavigationStack {
            List {
                Section("Tes goûts") {
                    Button { gouts = true } label: {
                        LigneReglage(titre: "Mes goûts", symbole: "heart.fill", couleur: .pink,
                                     valeur: genres.isEmpty ? "À choisir" : "\(genres.count) genres")
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Choisir tes genres et noter des films connus")
                }

                Section {
                    NavigationLink { ActeursSuivisView() } label: {
                        LigneReglage(titre: "Acteurs suivis", symbole: "person.2.fill", couleur: .teal,
                                     valeur: acteursSuivis.isEmpty ? "Aucun" : "\(acteursSuivis.count)")
                    }
                } header: {
                    Text("Acteurs")
                } footer: {
                    Text("Suis un acteur depuis sa fiche : Séance te prévient quand un nouveau film avec lui est annoncé.")
                }

                Section("Ce que tu as regardé") {
                    NavigationLink { StatistiquesView() } label: {
                        LigneReglage(titre: "Statistiques", symbole: "chart.bar.fill", couleur: .purple, valeur: libelleStatistiques)
                    }
                    // Le bilan en cartes a besoin d'au moins un visionnage.
                    if !visionnages.isEmpty {
                        Button { bilan = true } label: {
                            LigneReglage(titre: ServiceStatistiques.bilanOuvert() ? "Ton bilan \(String(Self.annee))" : "Ton année \(String(Self.annee)) jusqu'ici",
                                         symbole: "sparkles.rectangle.stack.fill", couleur: .orange, valeur: nil)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Ouvre le bilan en plein écran")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.fond)
            .navigationTitle("Profil")
            .toolbar {
                if classeTaille == .compact {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            ReglagesView()
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Réglages")
                    }
                }
            }
            .destinationsTitres()
            .sheet(isPresented: $gouts) {
                BienvenueView(mode: .gouts) { gouts = false }
            }
            .fullScreenCover(isPresented: $bilan) {
                BilanAnneeView(annee: Self.annee)
            }
        }
    }

    private var genres: Set<String> {
        Set(interets.map(\.libelle))
    }

    /// Les heures de l'année, sans les titres « déjà vus avant ».
    private var libelleStatistiques: String? {
        let debut = ServiceStatistiques.bornesAnnee(Self.annee).lowerBound
        let minutes = visionnages.filter { !$0.anterieur && $0.vuLe >= debut }.reduce(0) { $0 + $1.dureeMinutes }
        return minutes == 0 ? nil : "\(Format.duree(minutes)) en \(String(Self.annee))"
    }
}

/// Les acteurs suivis : chacun ouvre sa fiche ; glisser pour ne plus le suivre.
struct ActeursSuivisView: View {
    @Environment(\.modelContext) private var contexte
    @Query(sort: \ActeurSuivi.nom) private var acteurs: [ActeurSuivi]

    var body: some View {
        List {
            if acteurs.isEmpty {
                ContentUnavailableView("Aucun acteur suivi", systemImage: "person.2",
                                       description: Text("Sur la fiche d'un acteur, touche la cloche pour être prévenu de ses nouveaux films."))
                    .listRowBackground(Color.clear)
            }
            ForEach(acteurs) { acteur in
                NavigationLink(value: ReferencePersonne(id: acteur.personneID, nom: acteur.nom)) {
                    HStack(spacing: 12) {
                        ImageDistante(url: ImageTMDB.url(acteur.cheminPortrait, .portrait), coins: 22)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(acteur.nom)
                            Text("Suivi depuis le \(acteur.suiviLe.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "fr_CH"))))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions {
                    Button("Ne plus suivre", role: .destructive) {
                        try? ServiceActeurs(contexte: contexte).nePlusSuivre(acteur.personneID)
                    }
                }
            }
        }
        .pageReglages("Acteurs suivis")
    }
}
