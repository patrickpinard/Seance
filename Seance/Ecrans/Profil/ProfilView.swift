import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Ce qui te concerne, à part des réglages de l'app : ta collection, tes dernières notes, tes acteurs favoris et suivis,
/// tes goûts, tes statistiques et ton bilan de l'année.
/// Sur l'iPhone, l'engrenage ouvre Réglages, qui n'a pas d'onglet à lui.
enum DestinationProfil: Hashable {
    case acteursSuivis, statistiques
}

struct ProfilView: View {
    @Environment(\.horizontalSizeClass) private var classeTaille
    @Environment(\.modelContext) private var contexte
    @Query private var interets: [Interet]
    @Query(sort: \Suivi.ajouteLe, order: .reverse) private var suivis: [Suivi]
    @Query private var visionnages: [Visionnage]
    @Query private var acteursSuivis: [ActeurSuivi]
    @State private var gouts = false
    @State private var bilan = false
    /// Le classement des acteurs parcourt tous les visionnages et leurs castings : calculé une fois, puis seulement
    /// quand ce qu'il compte a changé, pas à chaque rendu de la page.
    @State private var favoris: [Classement<ActeurStat>] = []

    private static let annee = Calendar.current.component(.year, from: .now)

    var body: some View {
        NavigationStack {
            List {
                collection

                let notes = suivis.filter { $0.note != nil }.prefix(3)
                if !notes.isEmpty {
                    Section("Tes dernières notes") {
                        ForEach(Array(notes)) { suivi in
                            NavigationLink(value: suivi.reference) {
                                HStack(spacing: 12) {
                                    ImageDistante(url: ImageTMDB.url(suivi.cheminAffiche, .affiche), coins: 6)
                                        .frame(width: 30, height: 45)
                                    Text(suivi.titre).lineLimit(1)
                                    Spacer()
                                    Label("\(suivi.note ?? 0)/10", systemImage: "star.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.accentClair)
                                }
                            }
                        }
                    }
                }

                if !favoris.isEmpty {
                    Section("Tes acteurs favoris") {
                        ForEach(favoris, id: \.cle) { acteur in
                            if let id = acteur.cle.id {
                                NavigationLink(value: TitresAvecActeur(personne: ReferencePersonne(id: id, nom: acteur.cle.nom),
                                                                       periode: "depuis le début", titres: acteur.titres)) {
                                    LabeledContent(acteur.cle.nom, value: Format.pluriel(acteur.nombreTitres, "titre"))
                                }
                            } else {
                                LabeledContent(acteur.cle.nom, value: Format.pluriel(acteur.nombreTitres, "titre"))
                            }
                        }
                    }
                }

                Section("Tes goûts") {
                    Button { gouts = true } label: {
                        LigneReglage(titre: "Mes goûts", symbole: "heart.fill", couleur: .pink,
                                     valeur: genres.isEmpty ? "À choisir" : "\(genres.count) genres", chevron: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Choisir tes genres et noter des films connus")
                }

                Section {
                    NavigationLink(value: DestinationProfil.acteursSuivis) {
                        LigneReglage(titre: "Acteurs suivis", symbole: "person.2.fill", couleur: .teal,
                                     valeur: acteursSuivis.isEmpty ? "Aucun" : "\(acteursSuivis.count)")
                    }
                } header: {
                    Text("Acteurs")
                } footer: {
                    Text("Suis un acteur depuis sa fiche : Séance te prévient quand un nouveau film avec lui est annoncé.")
                }

                Section("Ce que tu as regardé") {
                    NavigationLink(value: DestinationProfil.statistiques) {
                        LigneReglage(titre: "Statistiques", symbole: "chart.bar.fill", couleur: .purple, valeur: libelleStatistiques)
                    }
                    // Le bilan en cartes a besoin d'au moins un visionnage.
                    if !visionnages.isEmpty {
                        Button { bilan = true } label: {
                            LigneReglage(titre: ServiceStatistiques.bilanOuvert() ? "Ton bilan \(String(Self.annee))" : "Ton année \(String(Self.annee)) jusqu'ici",
                                         symbole: "sparkles.rectangle.stack.fill", couleur: .orange, valeur: nil, chevron: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Ouvre le bilan en plein écran")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.fond)
            .navigationTitle("Profil")
            .boutonBarreLaterale()
            .toolbar {
                if classeTaille == .compact {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: DestinationReglage.reglages) {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Réglages")
                    }
                }
            }
            .task(id: cleFavoris) { favoris = acteursFavoris() }
            .destinationsTitres()
            .navigationDestination(for: DestinationProfil.self) { destination in
                switch destination {
                case .acteursSuivis: ActeursSuivisView()
                case .statistiques: StatistiquesView()
                }
            }
            .navigationDestination(for: TitresAvecActeur.self) { comptes in
                PersonneView(personne: comptes.personne, comptes: comptes)
            }
            .sheet(isPresented: $gouts) {
                BienvenueView(mode: .gouts) { gouts = false }
            }
            .fullScreenCover(isPresented: $bilan) {
                BilanAnneeView(annee: Self.annee)
            }
        }
    }

    /// En un coup d'œil : ce qui est vu (y compris « déjà vu avant » et les titres notés au premier lancement) et noté.
    @ViewBuilder
    private var collection: some View {
        let vus = Set(visionnages.map { ReferenceTitre(type: $0.type, tmdbID: $0.tmdbID) })
            .union(suivis.filter { $0.statut == .termine }.map(\.reference))
        let films = vus.filter { $0.type == .film }.count
        let notes = suivis.filter { $0.note != nil }.count
        if !vus.isEmpty {
            Section {
                HStack(spacing: 0) {
                    chiffre(vus.count, "vus")
                    chiffre(films, films > 1 ? "films" : "film")
                    chiffre(vus.count - films, vus.count - films > 1 ? "séries" : "série")
                    chiffre(notes, notes > 1 ? "notés" : "noté")
                }
                .padding(.vertical, 6)
            } header: {
                Text("Ta collection")
            }
        }
    }

    private func chiffre(_ nombre: Int, _ libelle: String) -> some View {
        VStack(spacing: 2) {
            Text("\(nombre)").font(.title2.weight(.heavy)).monospacedDigit()
            Text(libelle).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Les trois acteurs les plus regardés depuis le début, comptés comme dans les statistiques ;
    /// un acteur vu dans un seul titre n'est pas encore un favori.
    private func acteursFavoris() -> [Classement<ActeurStat>] {
        Array(((try? ServiceStatistiques(contexte: contexte).bilan(annee: nil).acteurs) ?? []).filter { $0.nombreTitres >= 2 }.prefix(3))
    }

    /// Ce dont dépend le classement : les visionnages comptés (pas les « déjà vus avant ») et les suivis, qui portent les castings.
    private var cleFavoris: [Int] {
        [visionnages.count, visionnages.filter(\.anterieur).count, suivis.count]
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
            if !acteurs.isEmpty {
                BandeauAlertesCoupees()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            if acteurs.isEmpty {
                ContentUnavailableView("Aucun acteur suivi", systemImage: "person.2",
                                       description: Text("Sur la fiche d'un acteur, touche la cloche pour être prévenu de ses nouveaux films."))
                    .listRowBackground(Color.clear)
            }
            ForEach(acteurs) { acteur in
                NavigationLink(value: ReferencePersonne(id: acteur.personneID, nom: acteur.nom)) {
                    HStack(spacing: 12) {
                        ImageDistante(url: ImageTMDB.url(acteur.cheminPortrait, .portrait), coins: 22, symboleVide: "person.fill")
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
                // Le Mac n'a pas de glissement : clic droit.
                .contextMenu {
                    Button(role: .destructive) {
                        try? ServiceActeurs(contexte: contexte).nePlusSuivre(acteur.personneID)
                    } label: { Label("Ne plus suivre", systemImage: "bell.slash") }
                }
            }
        }
        .pageReglages("Acteurs suivis")
    }
}
