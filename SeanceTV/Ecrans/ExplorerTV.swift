import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Explorer sur la TV : à la télécommande, on choisit plutôt qu'on ne tape. Catégorie, source, genres et tri en
/// rangées de boutons ; la recherche par titre reste là pour qui dicte ou se sert du clavier de l'iPhone.
struct ExplorerTV: View {
    @Environment(EtatTV.self) private var etat
    @Query(filter: #Predicate<Abonnement> { $0.actif }) private var abonnements: [Abonnement]
    @Query private var fichiers: [FichierNAS]
    @Query(sort: \Diffusion.debut) private var diffusions: [Diffusion]
    @Query private var suivis: [Suivi]

    enum Source: String, CaseIterable { case toutes = "Toutes", streaming = "Streaming", nas = "NAS", tele = "TV" }

    @State private var type = TypeTitre.film
    @State private var source = Source.toutes
    @State private var genres: [Genre] = []
    @State private var genresChoisis: Set<Int> = []
    @State private var tri = CriteresDecouverte.Tri.popularite
    @State private var recherche = ""
    @State private var resultats: [ApercuTV] = []
    @State private var enCours = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 34) {
                TextField("Chercher un titre (dictée, ou clavier de l'iPhone)", text: $recherche)
                    .padding(.horizontal, MargesTV.bord)
                rangee("Catégorie") {
                    choix("Films", type == .film) { type = .film }
                    choix("Séries", type == .serie) { type = .serie }
                }
                rangee("Source") {
                    ForEach(Source.allCases, id: \.self) { s in
                        choix(s.rawValue, source == s) { source = s }
                            .disabled(s == .streaming && abonnements.isEmpty)
                    }
                }
                if source == .toutes || source == .streaming {
                    rangee("Genres") {
                        ForEach(genres) { genre in
                            choix(genre.nom, genresChoisis.contains(genre.id)) {
                                if genresChoisis.contains(genre.id) { genresChoisis.remove(genre.id) } else { genresChoisis.insert(genre.id) }
                            }
                        }
                    }
                    rangee("Tri") {
                        choix("Populaires", tri == .popularite) { tri = .popularite }
                        choix("Mieux notés", tri == .note) { tri = .note }
                        choix("Récents", tri == .date) { tri = .date }
                    }
                }
                grille
            }
            .padding(.vertical, 40)
        }
        .task(id: Cle(type: type, source: source, genres: genresChoisis, tri: tri, recherche: recherche, pret: etat.tmdb != nil)) {
            // Laisse finir la frappe avant d'interroger TMDB.
            if !recherche.isEmpty { try? await Task.sleep(for: .milliseconds(500)) }
            guard !Task.isCancelled else { return }
            await chercher()
        }
        .task(id: type) {
            genres = ((try? await etat.tmdb?.genres(type)) ?? []).filter { !Self.genresEcartes.contains($0.id) }
            genresChoisis = []
        }
    }

    /// Les documentaires auront leur propre catégorie (EF-151) ; les émissions ne sont pas des séries à regarder.
    private static let genresEcartes: Set<Int> = [99, 10763, 10764, 10767]

    private struct Cle: Hashable {
        let type: TypeTitre, source: Source, genres: Set<Int>, tri: CriteresDecouverte.Tri, recherche: String, pret: Bool
    }

    @ViewBuilder
    private var grille: some View {
        if enCours, resultats.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 100)
        } else if resultats.isEmpty {
            VideTV(symbole: "sparkle.magnifyingglass", titre: "Rien à montrer",
                   message: source == .nas ? "Aucun titre de cette catégorie sur ton NAS." : source == .tele ? "Rien de cette catégorie sur tes chaînes cette semaine."
                                           : "Élargis les genres, ou change de source.")
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(AfficheTV.largeur), spacing: 40, alignment: .top), count: 6), spacing: 50) {
                ForEach(resultats) { apercu in
                    NavigationLink(value: apercu.reference) {
                        AfficheTV(titre: apercu.titre, sousTitre: apercu.sousTitre, cheminAffiche: apercu.cheminAffiche, marque: marque(apercu.reference))
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(.horizontal, MargesTV.bord)
            .focusSection()
        }
    }

    private func rangee(_ titre: String, @ViewBuilder _ contenu: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titre.uppercased()).font(.system(size: 22, weight: .bold)).foregroundStyle(.secondary).padding(.horizontal, MargesTV.bord)
            ScrollView(.horizontal) {
                HStack(spacing: 18) { contenu() }.padding(.horizontal, MargesTV.bord).padding(.vertical, 12)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }

    private func choix(_ libelle: String, _ choisi: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(libelle) }.buttonStyle(BoutonTV(principal: choisi))
    }

    private func marque(_ reference: ReferenceTitre) -> String? {
        if fichiers.contains(where: { $0.reference == reference }) { return "externaldrive.fill" }
        return suivis.contains { $0.reference == reference } ? "bookmark.fill" : nil
    }

    // MARK: Recherche

    private func chercher() async {
        enCours = true
        defer { enCours = false }
        let texte = recherche.trimmingCharacters(in: .whitespaces)
        switch source {
        case .nas:
            resultats = OeuvreTV.regrouper(fichiers.filter { $0.typeBrut == type.rawValue })
                .filter { texte.isEmpty || $0.titre.localizedCaseInsensitiveContains(texte) }
                .map { ApercuTV(reference: $0.reference, titre: $0.titre, sousTitre: $0.detail, cheminAffiche: $0.cheminAffiche, popularite: 0) }
        case .tele:
            var vus = Set<ReferenceTitre>()
            resultats = GrilleTele.blocs(diffusions.filter { $0.fin > .now && $0.typeBrut == type.rawValue }).compactMap { bloc in
                guard let reference = bloc.reference, vus.insert(reference).inserted,
                      texte.isEmpty || bloc.premiere.titreGuide.localizedCaseInsensitiveContains(texte) else { return nil }
                let quand = bloc.debut.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(Locale(identifier: "fr_CH")))
                return ApercuTV(reference: reference, titre: bloc.premiere.titreGuide, sousTitre: quand, cheminAffiche: bloc.premiere.cheminAffiche, popularite: 0)
            }
        case .toutes, .streaming:
            guard let client = etat.tmdb else { resultats = []; return }
            if !texte.isEmpty {
                switch type {
                case .film: resultats = ApercuTV.meler((try? await client.rechercherFilms(texte))?.resultats ?? [], [], garderLOrdre: true)
                case .serie: resultats = ApercuTV.meler([], (try? await client.rechercherSeries(texte))?.resultats ?? [], garderLOrdre: true)
                }
                return
            }
            var criteres = CriteresDecouverte()
            criteres.genresInclus = Array(genresChoisis)
            criteres.genresExclus = Array(Self.genresEcartes)
            criteres.tri = tri
            criteres.votesMin = tri == .note ? 300 : 50
            if source == .streaming {
                criteres.fournisseurs = abonnements.map(\.providerID)
                criteres.monetisations = [.abonnement]
            }
            switch type {
            case .film: resultats = ApercuTV.meler((try? await client.decouvrirFilms(criteres))?.resultats ?? [], [], garderLOrdre: true)
            case .serie: resultats = ApercuTV.meler([], (try? await client.decouvrirSeries(criteres))?.resultats ?? [], garderLOrdre: true)
            }
        }
    }
}
