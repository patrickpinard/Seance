import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

// Pages « Tout voir » de l'accueil : programme télé et « Du moment ».

/// Tout le programme à venir des chaînes cochées (EF-46 à EF-49), jour par jour.
struct ProgrammeTeleView: View {
    @Query(sort: \Diffusion.debut) private var diffusions: [Diffusion]
    @Query private var chaines: [Chaine]
    @State private var type: TypeTitre? = .film

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                Picker("Type", selection: $type) {
                    Text("Films").tag(TypeTitre?.some(.film))
                    Text("Séries").tag(TypeTitre?.some(.serie))
                    Text("Tout").tag(TypeTitre?.none)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                if parJour.isEmpty {
                    ContentUnavailableView("Rien à venir", systemImage: "tv",
                                           description: Text("Aucun film ni série reconnu sur tes chaînes. Choisis-les dans Réglages › Télévision."))
                }
                ForEach(parJour, id: \.jour) { groupe in
                    Section {
                        ForEach(groupe.diffusions) { diffusion in
                            ligne(diffusion)
                        }
                    } header: {
                        Text(libelle(groupe.jour))
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Theme.fond.opacity(0.95))
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .background(Theme.fond)
        .navigationTitle("Programme télé")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var parJour: [(jour: DateTMDB, diffusions: [Diffusion])] {
        let maintenant = Date.now
        let retenues = diffusions.filter { $0.fin > maintenant && (type == nil || $0.typeBrut == type?.rawValue) }
        let groupes = Dictionary(grouping: retenues) { DateTMDB($0.debut) }
        return groupes.keys.sorted().map { ($0, groupes[$0] ?? []) }
    }

    private func libelle(_ jour: DateTMDB) -> String {
        let aujourdhui = DateTMDB(.now)
        if jour == aujourdhui { return "Aujourd'hui" }
        if jour == DateTMDB(Date.now.addingTimeInterval(86_400)) { return "Demain" }
        return jour.instant(heure: 12).formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_CH"))).capitalized
    }

    @ViewBuilder
    private func ligne(_ diffusion: Diffusion) -> some View {
        let contenu = HStack(spacing: 12) {
            ImageDistante(url: ImageTMDB.url(diffusion.cheminFond, .fond)
                          ?? ImageTMDB.url(diffusion.cheminAffiche, .fond)
                          ?? diffusion.imageGuide.flatMap(URL.init(string:)), coins: 10)
                .frame(width: 128, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(chaines.first { $0.identifiantGuide == diffusion.chaine }?.nom ?? diffusion.chaine)
                        .font(.caption2.weight(.heavy))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.white, in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(.black)
                    if diffusion.debut <= .now {
                        Text("En cours").font(.caption.weight(.bold)).foregroundStyle(.red)
                    } else {
                        Text(diffusion.debut, format: .dateTime.hour().minute()).font(.caption.weight(.bold))
                    }
                }
                Text(diffusion.titreGuide).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(detail(diffusion)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)

        if let tmdbID = diffusion.tmdbID {
            NavigationLink(value: ReferenceTitre(type: TypeTitre(rawValue: diffusion.typeBrut) ?? .film, tmdbID: tmdbID)) { contenu }
                .buttonStyle(.plain)
        } else {
            contenu
        }
    }

    private func detail(_ diffusion: Diffusion) -> String {
        var morceaux = [diffusion.typeBrut == TypeTitre.serie.rawValue ? "Série" : "Film"]
        if let saison = diffusion.saison, let episode = diffusion.episode {
            morceaux.append(NumeroEpisode(saison: saison, episode: episode).description)
        } else if let annee = diffusion.anneeGuide {
            morceaux.append(String(annee))
        }
        morceaux.append("\(Int(diffusion.fin.timeIntervalSince(diffusion.debut) / 60)) min")
        return morceaux.joined(separator: " · ")
    }
}

/// « Du moment » en entier : sorties et nouveaux épisodes du mois, les plus populaires d'abord.
struct DuMomentView: View {
    var plateformes: [Int]?
    @State private var type: TypeTitre?
    @State private var liste = ListePaginee()

    @Environment(EtatApp.self) private var etat

    var body: some View {
        GrillePaginee(liste: liste, sousTitre: sousTitre) {
            Picker("Type", selection: $type) {
                Text("Tout").tag(TypeTitre?.none)
                Text("Films").tag(TypeTitre?.some(.film))
                Text("Séries et épisodes").tag(TypeTitre?.some(.serie))
            }
            .pickerStyle(.segmented)
        } chargerSuite: {
            await chargerSuite()
        }
        .navigationTitle(plateformes == nil ? "Du moment" : "Du moment sur tes plateformes")
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
        [GridItem(.adaptive(minimum: largeurGrille == .regular ? 150 : 105), spacing: 12, alignment: .top)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                entete
                LazyVGrid(columns: colonnes, spacing: 18) {
                    ForEach(liste.titres) { titre in
                        NavigationLink(value: titre.reference) {
                            CarteAffiche(titre: titre, largeur: nil, sousTitre: sousTitre(titre))
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
