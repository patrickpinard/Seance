import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Regarder (8.0) : tout ce qu'on peut regarder, rangé par source — Tout, Streaming, TV, NAS. « Tout » et « TV » suivent
/// le jour choisi dans la rangée : le premier, « Auj. », c'est ce soir ; un autre jour, c'est une soirée à planifier.
/// Streaming et NAS montrent leur catalogue, sans jour.
enum SourceRegarder: String, CaseIterable, Hashable {
    case tout, streaming, tele, nas

    var nom: String {
        switch self {
        case .tout: "Tout"
        case .streaming: "Streaming"
        case .tele: "TV"
        case .nas: "NAS"
        }
    }

    var symbole: String {
        switch self {
        case .tout: "square.grid.2x2"
        case .streaming: "play.rectangle.on.rectangle"
        case .tele: "tv"
        case .nas: "externaldrive"
        }
    }

    /// La rangée de jours n'a de sens que pour ce qui passe à une date : ta soirée et la TV.
    var suitLeJour: Bool { self == .tout || self == .tele }

    /// La source d'Explorer qui porte les filtres de cette page.
    var pourLesFiltres: FiltresExplorer.Source {
        switch self {
        case .tout: .toutes
        case .streaming: .streaming
        case .tele: .tele
        case .nas: .nas
        }
    }
}

/// L'onglet Regarder, le même sur l'iPhone, l'iPad et le Mac : la rangée de jours et les sources en tête, puis la page
/// de la source choisie.
struct RegarderView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(sort: \SelectionSoir.ajouteLe) private var selections: [SelectionSoir]
    @Query(filter: #Predicate<Abonnement> { $0.actif }) private var abonnements: [Abonnement]
    @Query(sort: \FiltreEnregistre.creeLe, order: .reverse) private var filtresEnregistres: [FiltreEnregistre]
    /// Les filtres d'Explorer (8.0), appliqués à la source choisie : sans filtre, la page de la source ; avec, ses résultats.
    @State private var filtres = ExplorerModele(filtres: FiltresExplorer(type: .film))
    @State private var feuilleFiltres = false

    /// Les critères posés en plus de la source elle-même.
    private var criteres: [FiltresExplorer.Critere] {
        filtres.filtres.criteresActifs.filter { !filtres.filtres.ditParLaSource($0) }
    }

    /// Le jour de la soirée en cours, à minuit : une soirée va de 6 h à 6 h.
    private var aujourdhui: Date {
        Calendar.current.startOfDay(for: ServiceSoiree.jour(ServiceSoiree.soiree()) ?? .now)
    }

    /// Le jour affiché : jamais dans le passé, même si la page est restée ouverte jusqu'au lendemain.
    private var jour: Date {
        max(etat.jourRegarder ?? aujourdhui, aujourdhui)
    }

    /// Nombre de titres par soirée, pour marquer les jours de la rangée.
    private var prevus: [String: Int] {
        Dictionary(grouping: selections.filter { $0.soiree >= ServiceSoiree.soiree() }, by: \.soiree).mapValues(\.count)
    }

    var body: some View {
        @Bindable var etat = etat
        NavigationStack {
            Group {
                if criteres.isEmpty {
                    ContenuSource(source: etat.sourceRegarder, jour: jour)
                } else {
                    ResultatsFiltres(modele: filtres)
                }
            }
                .id(etat.sourceRegarder)
                .environment(\.dansRegarder, true)
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        // Toujours là (25.09.2026) : sur Streaming et le NAS, le jour choisi est celui où l'appui long
                        // (« Prévoir pour … ») range le titre ; Tout et TV le suivent aussi pour leur contenu.
                        BandeSoirees(jour: Binding { jour } set: { etat.jourRegarder = $0 == aujourdhui ? nil : $0 },
                                     aujourdhui: aujourdhui, prevus: prevus)
                        if !etat.sourceRegarder.suitLeJour, let choisi = etat.jourRegarder {
                            Label("Pour \(LibelleSoiree.jour(choisi).lowercased()) : appui long sur un titre › « Prévoir pour ce soir-là »",
                                  systemImage: "calendar.badge.plus")
                                .font(.footnote)
                                .foregroundStyle(Theme.texte2)
                                .padding(.horizontal, 20)
                        }
                        SelecteurPuces(selection: $etat.sourceRegarder,
                                       choix: SourceRegarder.allCases.map { .init(valeur: $0, nom: $0.nom) })
                        barreFiltres
                    }
                    .padding(.vertical, 6)
                    .background(Theme.fond)
                }
                .navigationTitle("Regarder")
                .navigationBarTitleDisplayMode(.inline)
                .boutonBarreLaterale()
                .destinationsTitres()
                .destinationsAccueil()
                .sheet(isPresented: $feuilleFiltres) {
                    FeuilleFiltres(depart: filtres.filtres, modele: filtres) { filtres.filtres = $0 }
                }
        }
        // La source choisie est celle des filtres ; les autres critères restent.
        .onChange(of: etat.sourceRegarder, initial: true) { _, source in
            filtres.filtres.source = source.pourLesFiltres
        }
        .task(id: criteres.isEmpty ? nil : filtres.filtres) {
            guard !criteres.isEmpty, let client = etat.tmdb else { return }
            await filtres.recharger(client: client, contexte: contexte, abonnements: abonnements.map(\.providerID))
        }
    }

    /// « Filtres n », les filtres posés en pastilles qu'une croix retire, puis les filtres enregistrés.
    private var barreFiltres: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { feuilleFiltres = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease")
                        Text("Filtres")
                        if !criteres.isEmpty {
                            Text("\(criteres.count)")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6)
                                .background(Theme.accent, in: Capsule())
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.texte)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 34)
                    .background(Theme.eleve, in: Capsule())
                    .zoneDeToucher()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("boutonFiltres")
                let genres = etat.genres[filtres.filtres.type] ?? []
                ForEach(criteres, id: \.self) { critere in
                    let libelle = LibellesFiltres.libelle(critere, filtres.filtres, genres: genres)
                    PuceActive(libelle: libelle.texte, portrait: libelle.portrait) {
                        withAnimation(.snappy) { filtres.filtres.retirer(critere) }
                    }
                }
                ForEach(filtresEnregistres) { enregistre in
                    Button {
                        if var rappel = enregistre.filtres {
                            rappel.source = etat.sourceRegarder.pourLesFiltres
                            filtres.filtres = rappel
                        }
                    } label: {
                        Label(enregistre.nom, systemImage: "star.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.texte)
                            .padding(.horizontal, 11)
                            .frame(minHeight: 30)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.trait))
                            .zoneDeToucher()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

/// Les résultats des filtres de Regarder : les cartes d'Explorer, chargées au fil du défilement.
private struct ResultatsFiltres: View {
    let modele: ExplorerModele
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(filter: #Predicate<Abonnement> { $0.actif }) private var abonnements: [Abonnement]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(modele.enCours && modele.resultats.isEmpty ? "Recherche…"
                     : Format.pluriel(modele.resultats.count, "titre"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.texte2)
                    .padding(.horizontal, 20)
                if modele.resultats.isEmpty, !modele.enCours {
                    EtatVide(symbole: "line.3.horizontal.decrease", titre: "Aucun titre",
                             message: "Retire un filtre pour élargir.")
                }
                LazyVGrid(columns: CarteLargeTitre.colonnes, spacing: 14) {
                    ForEach(modele.resultats) { titre in
                        NavigationLink(value: titre.reference) { CarteLargeTitre(titre) }
                            .buttonStyle(.plain)
                            .actionsRapides(titre)
                            .onAppear {
                                guard titre.reference == modele.resultats.last?.reference, let client = etat.tmdb else { return }
                                Task { await modele.chargerSuite(client: client, contexte: contexte, abonnements: abonnements.map(\.providerID)) }
                            }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 12)
        }
        .background(Theme.fond)
    }
}

private struct ContenuSource: View {
    let source: SourceRegarder
    let jour: Date
    @Environment(EtatApp.self) private var etat
    @Query(filter: #Predicate<Abonnement> { $0.actif }) private var abonnements: [Abonnement]

    var body: some View {
        switch source {
        case .tout:
            SoireeView(jour: jour)
        case .streaming:
            if etat.tmdb == nil {
                InviteCleTMDB()
            } else if abonnements.isEmpty {
                EtatVide(symbole: "play.rectangle.on.rectangle", titre: "Aucune plateforme cochée",
                         message: "Coche tes abonnements — Netflix, Disney+, Prime Video… — et cette page montre ce qu'ils proposent de nouveau.",
                         libelleAction: "Choisir mes plateformes", symboleAction: "checklist") { etat.ongletDemande = .reglages }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.fond)
            } else {
                DuMomentView(choixPlateformes: true)
            }
        case .tele:
            ProgrammeTeleView(jourImpose: DateTMDB(jour.addingTimeInterval(12 * 3600)))
        case .nas:
            NASView()
        }
    }
}

/// Les pages que l'accueil ouvre en grand : aussi déclarées à la racine de Regarder.
extension View {
    func destinationsAccueil() -> some View {
        navigationDestination(for: DestinationAccueil.self) { destination in
            Group {
                switch destination {
                case .nas: NASView()
                case .tele: ProgrammeTeleView()
                case .duMoment(let plateformes): DuMomentView(plateformes: plateformes)
                case .documentaires: DocumentairesView()
                }
            }
            .boutonBarreLaterale(preferences: false)
        }
    }
}
