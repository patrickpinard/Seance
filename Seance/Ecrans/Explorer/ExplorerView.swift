import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Explorer (EF-52 à EF-59, maquette 2) : recherche par texte, et découverte par critères avec la
/// feuille de filtres, les puces actives, la grille ou la liste, et les filtres enregistrés.
struct ExplorerView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(filter: #Predicate<Abonnement> { $0.actif }) private var abonnements: [Abonnement]
    @Query(sort: \FiltreEnregistre.creeLe, order: .reverse) private var filtresEnregistres: [FiltreEnregistre]
    @Query(filter: #Predicate<FichierNAS> { $0.tmdbID != nil }) private var fichiersNAS: [FichierNAS]

    @State private var texte = ""
    @State private var titres: [TitreResume] = []
    @State private var personnes: [PersonneResume] = []
    @State private var modele = ExplorerModele()
    @State private var feuilleOuverte = false
    @AppStorage("explorer.liste") private var enListe = false
    @AppStorage("explorer.recentes") private var recentesBrut = ""
    @FocusState private var rechercheActive: Bool

    private let colonnes = [GridItem(.adaptive(minimum: 105), spacing: 12, alignment: .top)]

    var body: some View {
        NavigationStack {
            Group {
                if etat.tmdb == nil {
                    InviteCleTMDB()
                } else if texte.count >= 2 {
                    resultatsTexte
                } else {
                    decouverte
                }
            }
            .background(Theme.fond)
            .navigationTitle("Explorer")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { feuilleOuverte = true } label: {
                        Label("Filtres", systemImage: "slider.horizontal.3")
                    }
                    .disabled(etat.tmdb == nil)
                }
            }
            .searchable(text: $texte, prompt: "Films, séries, personnes")
            .searchFocused($rechercheActive)
            .searchSuggestions {
                if texte.isEmpty, !recentes.isEmpty {
                    Section("Recherches récentes") {
                        ForEach(recentes, id: \.self) { recente in
                            Label(recente, systemImage: "clock.arrow.circlepath").searchCompletion(recente)
                        }
                    }
                }
            }
            // La touche Rechercher garde le texte et les résultats, mais range le clavier.
            .onSubmit(of: .search) {
                memoriser(texte)
                rechercheActive = false
            }
            .task(id: texte) { await rechercher() }
            .task(id: CleChargement(filtres: modele.filtres, abonnements: abonnements.map(\.providerID), cle: etat.tmdb != nil)) {
                guard let client = etat.tmdb else { return }
                await modele.recharger(client: client, contexte: contexte, abonnements: abonnements.map(\.providerID))
            }
            .sheet(isPresented: $feuilleOuverte) {
                FeuilleFiltres(depart: modele.filtres, modele: modele) { modele.filtres = $0 }
            }
            .destinationsTitres()
        }
    }

    /// Ce qui relance la découverte : les filtres, les plateformes cochées, l'arrivée de la clé.
    private struct CleChargement: Hashable {
        let filtres: FiltresExplorer
        let abonnements: [Int]
        let cle: Bool
    }

    // MARK: Recherche par texte

    private var resultatsTexte: some View {
        ScrollView {
            if !personnes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(personnes) { personne in
                            Button { filtrerPar(personne) } label: {
                                HStack(spacing: 6) {
                                    ImageDistante(url: ImageTMDB.url(personne.cheminPortrait, .portrait), coins: 14)
                                        .frame(width: 28, height: 28)
                                    Text(personne.nom).font(.subheadline.weight(.semibold))
                                    Image(systemName: "line.3.horizontal.decrease").font(.caption2).foregroundStyle(.secondary)
                                }
                                .padding(.trailing, 12).padding(.leading, 3)
                                .frame(height: 34)
                                .background(Theme.surface, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Filtre Explorer sur cette personne")
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            LazyVGrid(columns: colonnes, spacing: 18) {
                ForEach(titres) { titre in
                    NavigationLink(value: titre.reference) {
                        CarteAffiche(titre: titre, largeur: nil)
                            .overlay(alignment: .topTrailing) { badges(titre.reference) }
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { memoriser(texte) })
                }
            }
            .padding(20)
        }
        // Parcourir les résultats range le clavier et rend la barre d'onglets.
        .scrollDismissesKeyboard(.immediately)
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

    /// Toucher une personne dans la recherche l'ajoute aux filtres (maquette : puce « Keanu Reeves »).
    private func filtrerPar(_ personne: PersonneResume) {
        memoriser(texte)
        var filtres = modele.filtres
        if !filtres.personnes.contains(where: { $0.id == personne.id }) {
            filtres.personnes.append(PersonneFiltre(id: personne.id, nom: personne.nom, cheminPortrait: personne.cheminPortrait,
                                                    estRealisateur: personne.domaine == "Directing"))
        }
        modele.filtres = filtres
        texte = ""
        rechercheActive = false
    }

    // MARK: Recherches récentes (EF-52)

    private var recentes: [String] {
        recentesBrut.split(separator: "\n").map(String.init)
    }

    private func memoriser(_ recherche: String) {
        let propre = recherche.trimmingCharacters(in: .whitespaces)
        guard propre.count >= 2 else { return }
        let liste = [propre] + recentes.filter { $0.caseInsensitiveCompare(propre) != .orderedSame }
        recentesBrut = liste.prefix(8).joined(separator: "\n")
    }

    // MARK: Découverte par critères

    private var decouverte: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Type", selection: Binding { modele.filtres.type } set: { changerType($0) }) {
                    Text("Films").tag(TypeTitre.film)
                    Text("Séries").tag(TypeTitre.serie)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                pucesActives

                if !filtresEnregistres.isEmpty {
                    enregistres
                }

                HStack(alignment: .firstTextBaseline) {
                    resume
                    Spacer()
                    Button { enListe = false } label: {
                        Image(systemName: "square.grid.2x2.fill")
                            .foregroundStyle(enListe ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.accent))
                    }
                    .accessibilityLabel("Grille")
                    Button { enListe = true } label: {
                        Image(systemName: "list.bullet")
                            .foregroundStyle(enListe ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                    }
                    .accessibilityLabel("Liste")
                }
                .font(.title3)
                .padding(.horizontal, 20)

                resultats

                if let erreur = modele.erreur {
                    Label(erreur, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var pucesActives: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { feuilleOuverte = true } label: {
                    Label(modele.filtres.criteresActifs.isEmpty ? "Filtres" : "Filtres · \(modele.filtres.criteresActifs.count)",
                          systemImage: "line.3.horizontal.decrease")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .foregroundStyle(.black)
                        .background(Theme.degradeAccent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("boutonFiltres")

                let genres = etat.genres[modele.filtres.type] ?? []
                ForEach(modele.filtres.criteresActifs, id: \.self) { critere in
                    let libelle = LibellesFiltres.libelle(critere, modele.filtres, genres: genres)
                    PuceActive(libelle: libelle.texte, portrait: libelle.portrait) {
                        withAnimation(.snappy) { modele.filtres.retirer(critere) }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// Filtres enregistrés (EF-57) : toucher rappelle, appui long propose de supprimer.
    private var enregistres: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filtresEnregistres) { filtre in
                    Button {
                        if let filtres = filtre.filtres { modele.filtres = filtres }
                    } label: {
                        Label(filtre.nom, systemImage: "bookmark.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 11)
                            .frame(height: 30)
                            .background(Theme.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Supprimer", systemImage: "trash", role: .destructive) {
                            contexte.delete(filtre)
                            try? contexte.save()
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var resume: some View {
        let mot = modele.filtres.type == .film ? "films" : "séries"
        return HStack(spacing: 4) {
            if let total = modele.total {
                let filtres = modele.filtres
                if filtres.filtresAppActifs && !filtres.partDUneListeLocale && !filtres.personnesParFilmographie {
                    Text("\(modele.resultats.count) \(mot)").font(.subheadline.weight(.bold))
                    Text(total >= 20_000 ? "retenus parmi plus de 20 000" : "retenus sur \(total.formatted())")
                } else if total >= 20_000 {
                    // TMDB plafonne le nombre annoncé à 20 001.
                    Text("Plus de 20 000 \(mot)").font(.subheadline.weight(.bold))
                } else {
                    Text("\(total.formatted()) \(mot)").font(.subheadline.weight(.bold))
                }
            } else if modele.enCours {
                ProgressView().controlSize(.small)
            }
            Text("· triés par \(LibellesFiltres.nom(modele.filtres.tri))")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("compteurResultats")
    }

    @ViewBuilder
    private var resultats: some View {
        if modele.resultats.isEmpty, !modele.enCours, modele.total != nil {
            ContentUnavailableView("Aucun résultat", systemImage: "line.3.horizontal.decrease",
                                   description: Text("Retire un filtre pour élargir la recherche."))
        }
        if enListe {
            LazyVStack(spacing: 12) {
                ForEach(modele.resultats) { titre in
                    NavigationLink(value: titre.reference) { ligne(titre) }
                        .buttonStyle(.plain)
                        .onAppear { suite(apres: titre) }
                }
            }
            .padding(.horizontal, 20)
        } else {
            LazyVGrid(columns: colonnes, spacing: 18) {
                ForEach(modele.resultats) { titre in
                    NavigationLink(value: titre.reference) {
                        CarteAffiche(titre: titre, largeur: nil)
                            .overlay(alignment: .topTrailing) { badges(titre.reference) }
                    }
                    .buttonStyle(.plain)
                    .onAppear { suite(apres: titre) }
                }
            }
            .padding(.horizontal, 20)
        }
        if modele.enCours, !modele.resultats.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding()
        }
    }

    /// Liste détaillée (EF-56) : affiche, titre, année, genres, note et début du synopsis.
    private func ligne(_ titre: TitreResume) -> some View {
        let noms = etat.genres[titre.reference.type] ?? []
        return HStack(alignment: .top, spacing: 12) {
            ImageDistante(url: ImageTMDB.url(titre.cheminAffiche, .affiche), coins: 8)
                .frame(width: 64, height: 96)
                .overlay(alignment: .topTrailing) { badges(titre.reference) }
            VStack(alignment: .leading, spacing: 4) {
                Text(titre.titre).font(.headline).lineLimit(2)
                Text([titre.date.map { String($0.annee) }, titre.genres.prefix(3).compactMap { id in noms.first { $0.id == id }?.nom }.joined(separator: ", ")]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !titre.synopsis.isEmpty {
                    Text(titre.synopsis).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if titre.nombreVotes > 0 {
                AnneauNote(pourcentage: titre.pourcentageNote, diametre: 36)
            }
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Ce que l'iPhone sait déjà : le titre est sur le NAS.
    @ViewBuilder
    private func badges(_ reference: ReferenceTitre) -> some View {
        if referencesNAS.contains(reference) {
            Image(systemName: "externaldrive.fill")
                .font(.caption2.weight(.bold))
                .padding(5)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(Theme.accentClair)
                .padding(5)
                .accessibilityLabel("Sur le NAS")
        }
    }

    private var referencesNAS: Set<ReferenceTitre> {
        Set(fichiersNAS.compactMap(\.reference))
    }

    private func suite(apres titre: TitreResume) {
        guard titre.reference == modele.resultats.last?.reference, let client = etat.tmdb else { return }
        Task { await modele.chargerSuite(client: client, contexte: contexte, abonnements: abonnements.map(\.providerID)) }
    }

    /// Les genres n'ont pas les mêmes identifiants pour les films et les séries : ils sont vidés.
    private func changerType(_ type: TypeTitre) {
        guard type != modele.filtres.type else { return }
        var filtres = modele.filtres
        filtres.type = type
        filtres.genresInclus = []
        filtres.genresExclus = []
        filtres.typesSortie = []
        filtres.dureeMax = nil
        modele.filtres = filtres
    }
}
