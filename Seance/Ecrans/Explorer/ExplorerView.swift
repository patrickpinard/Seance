import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Portée de la recherche par texte : tout, films, séries, ou acteurs et réalisateurs seulement.
enum PorteeRecherche: String, CaseIterable, Hashable {
    case tout = "Tout"
    case films = "Films"
    case series = "Séries"
    case acteurs = "Acteurs"

    func retient(_ type: TypeTitre) -> Bool {
        switch self {
        case .tout: true
        case .films: type == .film
        case .series: type == .serie
        case .acteurs: false
        }
    }
}

/// Explorer (EF-52 à EF-59, maquette 2) : recherche par texte, et découverte par critères avec la
/// feuille de filtres, les puces actives, la grille ou la liste, et les filtres enregistrés.
/// Un nom d'acteur tapé montre aussi ses titres les plus connus, prêts à filtrer.
struct ExplorerView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(filter: #Predicate<Abonnement> { $0.actif }) private var abonnements: [Abonnement]
    @Query(sort: \FiltreEnregistre.creeLe, order: .reverse) private var filtresEnregistres: [FiltreEnregistre]
    @Query(filter: #Predicate<FichierNAS> { $0.tmdbID != nil }) private var fichiersNAS: [FichierNAS]
    @Query private var visionnages: [Visionnage]
    @Query(sort: \Suivi.ajouteLe, order: .reverse) private var mesTitres: [Suivi]
    @Query(filter: #Predicate<Suivi> { $0.statutBrut == "termine" }) private var termines: [Suivi]

    /// Les résultats sans ce que tu as écarté (« Je n'aime pas », ni VF ni sous-titres) : ils ne sont plus proposés.
    private var resultatsProposes: [TitreResume] {
        let ecartes = Set(mesTitres.filter { $0.statut == .exclu || $0.exclusionLangue }.map(\.reference))
        return ecartes.isEmpty ? modele.resultats : modele.resultats.filter { !ecartes.contains($0.reference) }
    }

    @State private var texte = ""
    @State private var portee = PorteeRecherche.tout
    @State private var titres: [TitreResume] = []
    @State private var personnes: [PersonneResume] = []
    /// La personne cherchée, quand la recherche porte sur elle, et ses titres les plus connus.
    @State private var vedette: PersonneResume?
    @State private var titresVedette: [TitreResume] = []
    /// La dernière recherche terminée : « Aucun résultat » ne s'affiche pas pendant la frappe.
    @State private var recherchee: CleRecherche?
    @State private var modele = ExplorerModele()
    @State private var feuilleOuverte = false
    @AppStorage("explorer.liste") private var enListe = false
    @AppStorage("explorer.recentes") private var recentesBrut = ""
    @FocusState private var rechercheActive: Bool
    @State private var chemin = NavigationPath()

    @Environment(\.horizontalSizeClass) private var largeurGrille
    /// Affiches plus grandes sur le Mac : 105 points y feraient des timbres-poste.
    private var colonnes: [GridItem] {
        [GridItem(.adaptive(minimum: largeurGrille == .regular ? 150 : 105), spacing: 12, alignment: .top)]
    }

    var body: some View {
        NavigationStack(path: $chemin) {
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
            .boutonBarreLaterale()
            .searchable(text: $texte, prompt: "Films, séries, acteurs")
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
            .task(id: CleRecherche(texte: texte, portee: portee)) { await rechercher() }
            .task(id: CleChargement(filtres: modele.filtres, abonnements: abonnements.map(\.providerID), cle: etat.tmdb != nil)) {
                guard let client = etat.tmdb else { return }
                await modele.recharger(client: client, contexte: contexte, abonnements: abonnements.map(\.providerID))
            }
            // ⌘F : le champ de recherche prend la main.
            .onChange(of: etat.rechercheDemandee, initial: true) { _, demandee in
                guard demandee else { return }
                chemin = NavigationPath()
                rechercheActive = true
                etat.rechercheDemandee = false
            }
            // Sans plateforme cochée, la puce « Mes plateformes » ne filtrerait rien : elle est retirée.
            .task {
                if abonnements.isEmpty, modele.filtres.mesPlateformes { modele.filtres.mesPlateformes = false }
            }
            // « Dans Explorer » depuis une fiche acteur : Explorer revient à la racine, filtré sur la personne.
            .onChange(of: etat.filtreExplorerDemande, initial: true) { _, demande in
                guard let demande else { return }
                var filtres = modele.filtres
                filtres.personnes = [demande]
                modele.filtres = filtres
                texte = ""
                chemin = NavigationPath()
                etat.filtreExplorerDemande = nil
            }
            .onChange(of: modele.erreur) { _, erreur in
                guard erreur != nil else { return }
                etat.journal.noter(.tmdb, "Explorer n'a pas pu charger les résultats.", erreur: modele.erreurDetaillee)
            }
            .sheet(isPresented: $feuilleOuverte) {
                FeuilleFiltres(depart: modele.filtres, modele: modele) { modele.filtres = $0 }
            }
            .destinationsTitres()
        }
    }

    private struct CleRecherche: Hashable {
        let texte: String
        let portee: PorteeRecherche
    }

    /// Ce qui relance la découverte : les filtres, les plateformes cochées, l'arrivée de la clé.
    private struct CleChargement: Hashable {
        let filtres: FiltresExplorer
        let abonnements: [Int]
        let cle: Bool
    }

    // MARK: Recherche par texte

    /// Tes titres dont le nom contient la recherche, quel que soit leur statut.
    private var dansMesListes: [Suivi] {
        let cherche = texte.trimmingCharacters(in: .whitespaces)
        guard cherche.count >= 2 else { return [] }
        return Array(mesTitres.filter { !$0.masque && $0.statut != .exclu && $0.titre.localizedStandardContains(cherche) }.prefix(12))
    }

    private var resultatsTexte: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Les portées ne s'affichent que pendant une recherche : sur le Mac, celles de la barre de recherche
                // restaient visibles au-dessus de Films / Séries, et manquaient au premier affichage.
                Picker("Portée", selection: $portee) {
                    ForEach(PorteeRecherche.allCases, id: \.self) { portee in
                        Text(portee.rawValue).tag(portee)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                // Ce que tu cherches est peut-être déjà chez toi : tes listes d'abord, sans attendre TMDB.
                if portee != .acteurs, !dansMesListes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        TitreSection("Dans tes listes")
                        DefilementHorizontal {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(dansMesListes) { suivi in
                                    NavigationLink(value: suivi.reference) {
                                        AfficheSuivi(suivi: suivi, rendezVous: nil, episodesVus: 0).frame(width: 110)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
                if portee != .acteurs, !personnes.isEmpty {
                    pastillesPersonnes
                }
                if let vedette, !titresVedette.isEmpty {
                    sectionVedette(vedette)
                }
                if portee == .acteurs {
                    listePersonnes
                } else {
                    if vedette != nil, !titres.isEmpty {
                        TitreSection("Titres")
                    }
                    LazyVGrid(columns: colonnes, spacing: 18) {
                        ForEach(titres) { titre in
                            NavigationLink(value: titre.reference) {
                                CarteAffiche(titre: titre, largeur: nil)
                            }
                            .buttonStyle(.plain)
                            .actionsRapides(titre)
                            .simultaneousGesture(TapGesture().onEnded { memoriser(texte) })
                        }
                    }
                    .padding(.horizontal, 20)
                }
                if titres.isEmpty, personnes.isEmpty, recherchee == CleRecherche(texte: texte, portee: portee) {
                    ContentUnavailableView.search(text: texte)
                }
            }
            .padding(.vertical, 20)
        }
        // Parcourir les résultats range le clavier et rend la barre d'onglets.
        .scrollDismissesKeyboard(.immediately)
    }

    private var pastillesPersonnes: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(personnes) { personne in
                    NavigationLink(value: ReferencePersonne(id: personne.id, nom: personne.nom)) {
                        HStack(spacing: 6) {
                            ImageDistante(url: ImageTMDB.url(personne.cheminPortrait, .portrait), coins: 14, symboleVide: "person.fill")
                                .frame(width: 28, height: 28)
                            Text(personne.nom).font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.trailing, 12).padding(.leading, 3)
                        .frame(height: 34)
                        .background(Theme.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { memoriser(texte) })
                    .contextMenu {
                        Button("Filtrer Explorer sur \(personne.nom)", systemImage: "line.3.horizontal.decrease") { filtrerPar(personne) }
                    }
                    .accessibilityHint("Ouvre sa fiche : filmographie, vus et pas vus")
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// « Avec Jason Statham » : ses titres les plus connus, un bouton visible pour filtrer Explorer sur lui.
    private func sectionVedette(_ personne: PersonneResume) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TitreSection(titre: personne.domaine == "Directing" ? "Réalisés par \(personne.nom)" : "Avec \(personne.nom)") {
                Button { filtrerPar(personne) } label: {
                    Label("Filtrer", systemImage: "line.3.horizontal.decrease")
                }
                .font(.subheadline.weight(.semibold))
                .tint(Theme.accent)
                .help("Tous ses titres dans Explorer, à filtrer par genre, période ou plateforme")
            }
            DefilementHorizontal {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(titresVedette) { titre in
                        NavigationLink(value: titre.reference) {
                            CarteAffiche(titre: titre)
                                .overlay(alignment: .topTrailing) { badgeVu(titre.reference) }
                        }
                        .buttonStyle(.plain)
                        .actionsRapides(titre)
                        .simultaneousGesture(TapGesture().onEnded { memoriser(texte) })
                    }
                }
                .padding(.horizontal, 20)
            }
            NavigationLink(value: ReferencePersonne(id: personne.id, nom: personne.nom)) {
                Label("Sa fiche : toute la filmographie, vus et pas vus", systemImage: "person.crop.rectangle")
                    .font(.subheadline)
            }
            .tint(Theme.accentClair)
            .padding(.horizontal, 20)
            .simultaneousGesture(TapGesture().onEnded { memoriser(texte) })
        }
    }

    /// Portée « Acteurs » : chaque personne ouvre sa fiche ; le bouton de droite filtre Explorer sur elle.
    private var listePersonnes: some View {
        LazyVStack(spacing: 10) {
            ForEach(personnes) { personne in
                HStack(spacing: 12) {
                    NavigationLink(value: ReferencePersonne(id: personne.id, nom: personne.nom)) {
                        HStack(spacing: 12) {
                            ImageDistante(url: ImageTMDB.url(personne.cheminPortrait, .portrait), coins: 28, symboleVide: "person.fill")
                                .frame(width: 56, height: 56)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(personne.nom).font(.headline)
                                Text(personne.domaine == "Directing" ? "Réalisation" : personne.domaine == "Acting" ? "Interprétation" : "Autre")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { memoriser(texte) })
                    Button { filtrerPar(personne) } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Filtrer Explorer sur \(personne.nom)")
                    .help("Filtrer Explorer sur \(personne.nom)")
                }
                .padding(10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func badgeVu(_ reference: ReferenceTitre) -> some View {
        if vus.contains(reference) {
            Image(systemName: "checkmark")
                .font(.caption2.weight(.heavy))
                .padding(5)
                .background(.black.opacity(0.7), in: Circle())
                .foregroundStyle(.green)
                .padding(5)
                .accessibilityLabel("Vu")
        }
    }

    private var vus: Set<ReferenceTitre> {
        Set(visionnages.map { ReferenceTitre(type: $0.type, tmdbID: $0.tmdbID) }).union(termines.map(\.reference))
    }

    private func rechercher() async {
        guard let client = etat.tmdb, texte.count >= 2 else { return }
        // Attente courte : on ne cherche qu'une fois la frappe terminée.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        let cle = CleRecherche(texte: texte, portee: portee)
        var trouvee: PersonneResume?
        if portee == .acteurs {
            let resultats = (try? await client.rechercherPersonnes(texte)) ?? []
            guard !Task.isCancelled else { return }
            titres = []
            // Les homonymes sans photo ni carrière connue passent après.
            personnes = resultats.filter { $0.cheminPortrait != nil } + resultats.filter { $0.cheminPortrait == nil }
            trouvee = personnes.first
        } else {
            let resultats = (try? await client.rechercherTout(texte)) ?? []
            guard !Task.isCancelled else { return }
            let retenus = resultats.compactMap(\.titre).filter { portee.retient($0.reference.type) }
            titres = retenus.filter { $0.cheminAffiche != nil } + retenus.filter { $0.cheminAffiche == nil }
            personnes = portee == .tout ? resultats.compactMap(\.personne) : []
            // Un nom d'acteur tapé : TMDB le classe en tête, devant les titres qui le contiennent.
            trouvee = portee == .tout ? resultats.first?.personne : nil
        }
        recherchee = cle
        vedette = trouvee
        titresVedette = []
        guard let trouvee, let filmographie = try? await client.filmographie(personne: trouvee.id), !Task.isCancelled else { return }
        titresVedette = Self.plusConnus(trouvee.domaine == "Directing" ? filmographie.realisations : filmographie.roles)
    }

    /// Les vingt titres les plus votés, avec affiche, sans apparitions « dans son propre rôle ».
    static func plusConnus(_ credits: [CreditPersonne]) -> [TitreResume] {
        AnalyseFilmographie.significatifs(credits)
            .filter { $0.cheminAffiche != nil }
            .sorted { ($0.nombreVotes ?? 0) > ($1.nombreVotes ?? 0) }
            .prefix(20)
            .map(\.titreResume)
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
                SelecteurCases(selection: Binding { modele.filtres.type } set: { changerType($0) },
                               cases: [.init(valeur: TypeTitre.film, nom: "Films"), .init(valeur: TypeTitre.serie, nom: "Séries")])
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 20)

                selecteurSource

                pucesActives

                if !filtresEnregistres.isEmpty {
                    enregistres
                }

                HStack(alignment: .center) {
                    resume
                    Spacer()
                    BasculeGrilleListe(enGrille: Binding { !enListe } set: { enListe = !$0 })
                }
                .font(.title3)
                .padding(.horizontal, 20)

                resultats

                if let erreur = modele.erreur {
                    MessageEtat(texte: erreur, ton: .probleme, libelleAction: "Réessayer") {
                        guard let client = etat.tmdb else { return }
                        Task { await modele.recharger(client: client, contexte: contexte, abonnements: abonnements.map(\.providerID)) }
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    /// D'où viennent les idées : tout TMDB, tes plateformes, ton NAS ou la télé. Une source sans rien derrière
    /// (aucune plateforme cochée, NAS vide) reste visible mais ne se choisit pas.
    private var selecteurSource: some View {
        VStack(alignment: .leading, spacing: 8) {
            SelecteurCases(selection: Binding { modele.filtres.source } set: { modele.filtres.source = $0 }, cases: [
                .init(valeur: FiltresExplorer.Source.toutes, nom: "Toutes", symbole: "square.grid.2x2"),
                .init(valeur: .streaming, nom: "Streaming", symbole: "play.tv", disponible: !abonnements.isEmpty, aide: "Coche tes plateformes dans Réglages › Plateformes."),
                .init(valeur: .nas, nom: "NAS", symbole: "externaldrive.fill", disponible: !fichiersNAS.isEmpty, aide: "Aucun titre reconnu sur ton NAS pour l'instant."),
                .init(valeur: .tele, nom: "Télé", symbole: "tv"),
            ])
            .frame(maxWidth: 560)
            .padding(.horizontal, 20)
            if modele.filtres.source == .tele {
                HStack(spacing: 8) {
                    puceTele(.ceSoir, "Ce soir")
                    puceTele(.cetteSemaine, "Cette semaine")
                }
                .padding(.horizontal, 20)
                .transition(.opacity)
            }
        }
    }

    private func puceTele(_ quand: FiltresLocaux.Tele, _ nom: String) -> some View {
        let active = modele.filtres.locaux.tele == quand
        return Button {
            withAnimation(.snappy) { modele.filtres.locaux.tele = quand }
        } label: {
            Text(nom)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .foregroundStyle(active ? Theme.accentClair : Color.secondary)
                .background(active ? AnyShapeStyle(Theme.accent.opacity(0.18)) : AnyShapeStyle(Theme.surface), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var pucesActives: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { feuilleOuverte = true } label: {
                    let nombre = modele.filtres.criteresActifs.filter { !modele.filtres.ditParLaSource($0) }.count
                    Label(nombre == 0 ? "Filtres" : "Filtres · \(nombre)",
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
                ForEach(modele.filtres.criteresActifs.filter { !modele.filtres.ditParLaSource($0) }, id: \.self) { critere in
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
                            contexte.sauver()
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
            if modele.total != nil {
                Text("· triés par \(LibellesFiltres.nom(modele.filtres.tri))")
            }
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
                ForEach(resultatsProposes) { titre in
                    NavigationLink(value: titre.reference) { ligne(titre) }
                        .buttonStyle(.plain)
                        .actionsRapides(titre)
                        .onAppear { suite(apres: titre) }
                }
            }
            .padding(.horizontal, 20)
        } else {
            LazyVGrid(columns: colonnes, spacing: 18) {
                ForEach(resultatsProposes) { titre in
                    NavigationLink(value: titre.reference) {
                        CarteAffiche(titre: titre, largeur: nil)
                    }
                    .buttonStyle(.plain)
                    .actionsRapides(titre)
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
        guard titre.reference == resultatsProposes.last?.reference, let client = etat.tmdb else { return }
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
