import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

// Page « Tout voir » de « Nouveautés » ; le programme TV est dans ProgrammeTele.swift.

/// « Nouveautés » en entier : sorties et nouveaux épisodes du mois, les plus populaires d'abord.
struct DuMomentView: View {
    var plateformes: [Int]?
    @State private var type: TypeTitre?
    @State private var liste = ListePaginee()

    @Environment(EtatApp.self) private var etat

    var body: some View {
        GrillePaginee(liste: liste, sousTitre: sousTitre) {
            SelecteurCases(selection: $type, cases: [.init(valeur: TypeTitre?.none, nom: "Tout"), .init(valeur: TypeTitre?.some(.film), nom: "Films"),
                                                     .init(valeur: TypeTitre?.some(.serie), nom: "Séries et épisodes")])
        } chargerSuite: {
            await chargerSuite()
        }
        .navigationTitle(plateformes == nil ? "Nouveautés" : "Nouveautés sur tes plateformes")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: type) {
            liste = ListePaginee()
            await chargerSuite()
        }
    }

    private func sousTitre(_ titre: TitreResume) -> String? {
        titre.reference.type == .film ? titre.date.map { "Sortie \(LibelleDate.jour($0))" } : liste.dates[titre.reference]
    }

    private func chargerSuite() async {
        guard let client = etat.tmdb else { return }
        let typeDemande = type
        let pourFilms = AccueilModele.surPlateformes(CriteresDecouverte.duMoment(.film), plateformes)
        let pourSeries = AccueilModele.surPlateformes(CriteresDecouverte.duMoment(.serie), plateformes)
        await liste.charger { page in
            var criteresFilms = pourFilms
            criteresFilms.page = page
            var criteresSeries = pourSeries
            criteresSeries.page = page
            let films = typeDemande == .serie ? [] : try await client.decouvrirFilms(criteresFilms).resultats.map(\.titreResume)
            let series = typeDemande == .film ? [] : try await client.decouvrirSeries(criteresSeries).resultats.map(\.titreResume)
            return AccueilModele.affichables(AccueilModele.entrelacer(films, series))
        } dates: { titres in
            await DatesNouveautes.episodes(titres.filter { $0.reference.type == .serie }, client: client)
        }
    }
}

/// Résultats chargés page par page, sans doublon, au fil du défilement.
@MainActor
@Observable
final class ListePaginee {
    private(set) var titres: [TitreResume] = []
    private(set) var dates: [ReferenceTitre: String] = [:]
    private(set) var enCours = false
    private(set) var termine = false
    private var page = 0
    /// Au-delà, le défilement devient une liste sans fin : dix pages suffisent.
    private static let pagesMax = 10

    func charger(
        _ lire: (Int) async throws -> [TitreResume],
        dates lireDates: ([TitreResume]) async -> [ReferenceTitre: String]
    ) async {
        guard !enCours, !termine else { return }
        enCours = true
        defer { enCours = false }
        guard let nouveaux = try? await lire(page + 1) else {
            termine = true
            return
        }
        page += 1
        let connus = Set(titres.map(\.reference))
        let ajoutes = nouveaux.filter { !connus.contains($0.reference) }
        dates.merge(await lireDates(ajoutes)) { _, nouveau in nouveau }
        titres += ajoutes
        termine = nouveaux.isEmpty || page >= Self.pagesMax
    }
}

/// Grille d'affiches commune aux pages « Tout voir ».
private struct GrillePaginee<Entete: View>: View {
    let liste: ListePaginee
    let sousTitre: (TitreResume) -> String?
    @ViewBuilder let entete: Entete
    let chargerSuite: () async -> Void

    @Environment(\.horizontalSizeClass) private var largeurGrille
    /// Affiches plus grandes sur le Mac : 105 points y feraient des timbres-poste.
    private var colonnes: [GridItem] {
        CarteLargeTitre.colonnes
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                entete
                LazyVGrid(columns: colonnes, spacing: 18) {
                    ForEach(liste.titres) { titre in
                        NavigationLink(value: titre.reference) {
                            CarteLargeTitre(titre, accroche: sousTitre(titre))
                        }
                        .buttonStyle(.plain)
                        .actionsRapides(titre)
                        .onAppear {
                            if titre.reference == liste.titres.last?.reference {
                                Task { await chargerSuite() }
                            }
                        }
                    }
                }
                if liste.enCours {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if liste.titres.isEmpty, liste.termine {
                    ContentUnavailableView("Rien pour cette période", systemImage: "calendar")
                }
            }
            .padding(20)
        }
        .background(Theme.fond)
    }
}
