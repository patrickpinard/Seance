import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

// Page « Tout voir » de « Nouveautés » ; le programme TV est dans ProgrammeTele.swift.

/// « Nouveautés » en entier : sorties et nouveaux épisodes du mois, les plus populaires d'abord.
/// Avec `choixPlateformes` (7.0), c'est la page Streaming du menu : tes plateformes seulement, une puce par plateforme.
struct DuMomentView: View {
    var plateformes: [Int]?
    var choixPlateformes = false
    @State private var typeChoisi: TypeTitre?
    @State private var plateformeChoisie: Int?
    @State private var liste = ListePaginee()
    @Query(filter: #Predicate<Abonnement> { $0.actif }, sort: \Abonnement.nom) private var abonnements: [Abonnement]
    /// Déjà vus ou refusés (8.2.11) : les nouveautés ne les proposent plus.
    @Query(filter: #Predicate<Suivi> { $0.statutBrut == "exclu" || $0.exclusionLangue || $0.statutBrut == "termine" })
    private var ecartes: [Suivi]
    @AppStorage(PasInteresse.cle) private var pasInteresse = ""

    @Environment(EtatApp.self) private var etat

    /// Dans Regarder › Streaming (8.6), Films et Séries sont les pastilles à côté de « Filtres » ; ailleurs, le sélecteur.
    private var type: TypeTitre? { choixPlateformes ? etat.typeRegarder : typeChoisi }

    /// Les plateformes interrogées : celle de la puce, sinon toutes celles cochées.
    private var plateformesRetenues: [Int]? {
        guard choixPlateformes else { return plateformes }
        if let plateformeChoisie { return [plateformeChoisie] }
        return abonnements.isEmpty ? nil : abonnements.map(\.providerID).sorted()
    }

    private struct Cle: Hashable {
        let type: TypeTitre?
        let plateformes: [Int]?
    }

    var body: some View {
        GrillePaginee(liste: liste, sousTitre: sousTitre, ecartes: Set(ecartes.map(\.reference)).union(PasInteresse.references(pasInteresse))) {
            if choixPlateformes, abonnements.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        PuceFiltre(libelle: "Toutes", active: plateformeChoisie == nil) { plateformeChoisie = nil }
                        ForEach(abonnements) { abonnement in
                            PuceFiltre(libelle: abonnement.nom, active: plateformeChoisie == abonnement.providerID) {
                                plateformeChoisie = abonnement.providerID
                            }
                        }
                    }
                }
                .scrollClipDisabled()
            }
            if !choixPlateformes {
                SelecteurCases(selection: $typeChoisi, cases: [.init(valeur: TypeTitre?.none, nom: "Tout"), .init(valeur: TypeTitre?.some(.film), nom: "Films"),
                                                               .init(valeur: TypeTitre?.some(.serie), nom: "Séries et épisodes")])
            }
        } chargerSuite: {
            await chargerSuite()
        }
        .titrePage(choixPlateformes ? "Streaming" : plateformes == nil ? "Nouveautés" : "Nouveautés sur tes plateformes")
        .modeTitre(choixPlateformes ? .large : .inline)
        .task(id: Cle(type: type, plateformes: plateformesRetenues)) {
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
        let retenues = plateformesRetenues
        let pourFilms = AccueilModele.surPlateformes(CriteresDecouverte.duMoment(.film), retenues)
        let pourSeries = AccueilModele.surPlateformes(CriteresDecouverte.duMoment(.serie), retenues)
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
    /// Les titres à ne plus montrer : déjà vus, refusés.
    var ecartes: Set<ReferenceTitre> = []
    @ViewBuilder let entete: Entete
    let chargerSuite: () async -> Void

    @Environment(\.horizontalSizeClass) private var largeurGrille
    /// Cartes ou liste (8.6), le même choix sur toutes les pages de titres.
    @AppStorage(VueTitres.cle) private var enListe = false
    /// Affiches plus grandes sur le Mac : 105 points y feraient des timbres-poste.
    private var colonnes: [GridItem] {
        CarteLargeTitre.colonnes
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                entete
                HStack {
                    Spacer()
                    BasculeGrilleListe(enGrille: Binding { !enListe } set: { enListe = !$0 })
                }
                let titres = liste.titres.filter { !ecartes.contains($0.reference) }
                if enListe {
                    LazyVStack(spacing: 10) {
                        ForEach(titres) { titre in
                            NavigationLink(value: titre.reference) {
                                LigneTitreListe(titre: titre, detail: sousTitre(titre))
                            }
                            .buttonStyle(.plain)
                            .actionsRapides(titre)
                            .glissementsTitre(titre)
                            .onAppear { suite(apres: titre, parmi: titres) }
                        }
                    }
                } else {
                    LazyVGrid(columns: colonnes, spacing: 18) {
                        ForEach(titres) { titre in
                            NavigationLink(value: titre.reference) {
                                CarteLargeTitre(titre, accroche: sousTitre(titre))
                            }
                            .buttonStyle(.plain)
                            .actionsRapides(titre)
                            .glissementsTitre(titre)
                            .onAppear { suite(apres: titre, parmi: titres) }
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

    /// Le dernier titre montré, écartés compris : sinon la suite ne se chargeait plus.
    private func suite(apres titre: TitreResume, parmi titres: [TitreResume]) {
        if titre.reference == titres.last?.reference { Task { await chargerSuite() } }
    }
}
