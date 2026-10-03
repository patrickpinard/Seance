import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Ouvre les filtres de Regarder sur une source (8.0).
struct FiltresTVDemande: Hashable {
    let source: ExplorerTV.Source
}

/// La recherche et les filtres sur la TV (8.0, charte commune) : en deux parties, comme sur l'iPad et le Mac — les
/// filtres à gauche, les résultats à droite, recalculés à chaque choix. À la télécommande, on choisit plutôt qu'on ne
/// tape ; le champ de recherche reste là pour la dictée et le clavier de l'iPhone. Depuis Regarder, la source est
/// déjà choisie et le champ disparaît.
struct ExplorerTV: View {
    enum Source: String, CaseIterable, Hashable { case toutes = "Toutes", streaming = "Streaming", nas = "NAS", tele = "TV" }
    enum Categorie: String, CaseIterable, Hashable { case films = "Films", series = "Séries", documentaires = "Documentaires" }
    enum Periode: String, CaseIterable, Hashable { case toutes = "Toutes", depuis2020 = "Depuis 2020", depuis2010 = "Depuis 2010", avant2000 = "Avant 2000" }
    enum Duree: String, CaseIterable, Hashable { case peuImporte = "Peu importe", moinsDeDeuxHeures = "Moins de 2 h", moinsDUneHeureEtDemie = "Moins de 1 h 30" }
    enum Note: String, CaseIterable, Hashable { case toutes = "Toutes", septEtPlus = "7 et plus", huitEtPlus = "8 et plus" }
    enum DejaVus: String, CaseIterable, Hashable { case tous = "Tous", pasVus = "Pas vus", vus = "Déjà vus" }
    /// Une ligne du panneau des filtres (maquette 8.0, n° 8) : son nom, sa valeur à droite ; ses choix s'ouvrent dessous.
    enum Critere: String, CaseIterable, Hashable {
        case categorie = "Catégorie", disponibilite = "Disponibilité", genres = "Genres", periode = "Période", duree = "Durée"
        case acteurs = "Acteurs", note = "Note", dejaVus = "Déjà vus", tri = "Tri"
    }

    /// Depuis Regarder : la source de la page, qu'on ne choisit plus ici.
    var sourceImposee: Source?

    @Environment(EtatTV.self) private var etat
    @Query(filter: #Predicate<Abonnement> { $0.actif }) private var abonnements: [Abonnement]
    @Query private var fichiers: [FichierNAS]
    @Query(sort: \Diffusion.debut) private var diffusions: [Diffusion]
    @Query private var suivis: [Suivi]
    @Query(sort: \ActeurSuivi.nom) private var acteursSuivis: [ActeurSuivi]
    @Query private var visionnages: [Visionnage]

    @State private var categorie = Categorie.films
    @State private var sourceChoisie = Source.toutes
    @State private var genres: [Genre] = []
    @State private var genresChoisis: Set<Int> = []
    @State private var genresExclus: Set<Int> = []
    @State private var periode = Periode.toutes
    @State private var duree = Duree.peuImporte
    @State private var note = Note.toutes
    @State private var tri = CriteresDecouverte.Tri.popularite
    @State private var acteurs: Set<Int> = []
    @State private var dejaVus = DejaVus.tous
    /// La ligne dont les choix sont montrés sous la liste : la dernière qui a eu le focus.
    @State private var ouvert = Critere.categorie
    @FocusState private var ligneAuFocus: Critere?
    /// Le rang du choix au focus, sous la liste : un clic sur une ligne y descend, au premier.
    @FocusState private var choixAuFocus: Int?
    @State private var recherche = ""
    @State private var resultats: [ApercuTV] = []
    /// Les acteurs et réalisateurs trouvés par le texte tapé (8.9) : une rangée au-dessus des titres.
    @State private var personnes: [PersonneResume] = []
    /// Le rangement des résultats et ses sections (8.2.15).
    @State private var rangement = "Pertinence"
    @State private var sections = SectionsRepliables()
    /// Explorer › NAS › Vidéos : les vidéos personnelles plutôt que les films (8.2.15).
    @State private var videos = false

    private var tranches: [(titre: String, titres: [ApercuTV])] {
        switch rangement {
        case "A→Z":
            return [("", resultats.sorted { $0.titre.localizedCaseInsensitiveCompare($1.titre) == .orderedAscending })]
        case "Année":
            let parAnnee = Dictionary(grouping: resultats) { $0.annee }
            return parAnnee.keys.sorted { ($0 ?? 0) > ($1 ?? 0) }.map { ($0.map(String.init) ?? "Année inconnue", parAnnee[$0] ?? []) }
        case "Genre":
            let noms = Dictionary((GenresParDefaut.films + GenresParDefaut.series).map { ($0.id, $0.nom) }, uniquingKeysWith: { premier, _ in premier })
            let parGenre = Dictionary(grouping: resultats) { $0.genres.first.flatMap { noms[$0] } ?? "Autres" }
            return parGenre.keys.sorted { $0 == "Autres" ? false : $1 == "Autres" ? true : $0 < $1 }.map { ($0, parGenre[$0] ?? []) }
        default:
            return [("", resultats)]
        }
    }
    @State private var enCours = false

    private var source: Source { sourceImposee ?? sourceChoisie }
    private var type: TypeTitre { categorie == .series ? .serie : .film }
    /// Les critères qui ne valent que pour TMDB (tout, ou tes plateformes) : le NAS et la TV n'ont que leur liste.
    private var criteresTMDB: Bool { source == .toutes || source == .streaming }

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            colonneFiltres
                .frame(width: 600)
            colonneResultats
        }
        .padding(.leading, MargesTV.bord)
        // 8.8 : la loupe ouvre cette page, comme la Recherche de l'iPhone — le clavier de tvOS en haut (dictée, clavier
        // de l'iPhone), puis les filtres et les résultats. Depuis Regarder, la source est choisie et le clavier n'y est pas.
        .modifier(ClavierRecherche(actif: sourceImposee == nil, texte: $recherche))
        .task(id: Cle(categorie: categorie, source: source, genres: genresChoisis, exclus: genresExclus, periode: periode,
                      duree: duree, note: note, tri: tri, acteurs: acteurs, dejaVus: dejaVus, recherche: recherche, pret: etat.tmdb != nil)) {
            // Laisse finir la frappe avant d'interroger TMDB.
            if !recherche.isEmpty { try? await Task.sleep(for: .milliseconds(500)) }
            guard !Task.isCancelled else { return }
            await chercher()
        }
        .task(id: type) {
            genres = ((try? await etat.tmdb?.genres(type)) ?? []).filter { !Self.genresEcartes.contains($0.id) }
            genresChoisis = []
            genresExclus = []
        }
    }

    // MARK: Les filtres

    /// Les lignes montrées : la disponibilité seulement dans la Recherche (Regarder l'a déjà choisie) ; le NAS et la TV
    /// n'ont que leur liste, sans les critères de TMDB.
    private var criteres: [Critere] {
        Critere.allCases.filter { critere in
            switch critere {
            case .disponibilite: sourceImposee == nil
            case .genres, .periode, .note, .acteurs, .tri: criteresTMDB
            case .duree: criteresTMDB && categorie != .series
            case .categorie, .dejaVus: true
            }
        }
    }

    /// Maquette 8.0, n° 8, comme les Réglages de tvOS : un panneau « Filtres » avec une ligne par critère et sa valeur ;
    /// la ligne au focus montre ses choix dessous, un clic y descend, Retour remonte à la ligne.
    private var colonneFiltres: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Filtres").font(.system(size: 34, weight: .bold))
                        Spacer()
                        Button("Réinitialiser") { reinitialiser() }
                            .buttonStyle(BoutonTV(hauteur: 52))
                    }
                    .padding(.horizontal, 10)
                    VStack(spacing: 2) {
                        ForEach(criteres, id: \.self) { critere in
                            Button {
                                ouvert = critere
                                choixAuFocus = 0
                            } label: {
                                LigneFiltreTV(nom: critere.rawValue, valeur: valeur(critere), ouverte: ouvert == critere)
                            }
                            .buttonStyle(LigneTV())
                            .focused($ligneAuFocus, equals: critere)
                        }
                    }
                    .focusSection()
                    VStack(alignment: .leading, spacing: 10) {
                        if ouvert == .genres {
                            Text("Appui long : exclure").font(.system(size: 20)).foregroundStyle(Theme.texte2).padding(.leading, 10)
                        }
                        FluxTV(espacement: 12) { choix(ouvert) }
                    }
                    .padding(.top, 8)
                    .focusSection()
                    .onExitCommand { ligneAuFocus = ouvert }
                }
                .padding(18)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .padding(.vertical, 30)
            .padding(.trailing, 20)
        }
        .scrollClipDisabled()
        .focusSection()
        .onChange(of: ligneAuFocus) { _, ligne in if let ligne { ouvert = ligne } }
        .onChange(of: criteres) { _, liste in if !liste.contains(ouvert) { ouvert = .categorie } }
    }

    /// Ce que la ligne dit à droite : le choix en cours, en quelques mots.
    private func valeur(_ critere: Critere) -> String {
        switch critere {
        case .categorie: return source == .nas && videos ? "Vidéos" : categorie.rawValue
        case .disponibilite: return source == .streaming ? "Mes plateformes" : source.rawValue
        case .genres:
            let noms = genres.filter { genresChoisis.contains($0.id) }.map(\.nom) + genres.filter { genresExclus.contains($0.id) }.map { "− \($0.nom)" }
            return noms.isEmpty ? "Tous" : noms.joined(separator: ", ")
        case .periode: return periode == .toutes ? "Toutes" : periode.rawValue.lowercased()
        case .duree: return duree.rawValue.lowercased()
        case .acteurs:
            let noms = acteursSuivis.filter { acteurs.contains($0.personneID) }.map(\.nom)
            return noms.isEmpty ? "–" : noms.joined(separator: ", ")
        case .note: return note.rawValue
        case .dejaVus: return dejaVus.rawValue
        case .tri: return libelle(tri)
        }
    }

    private func libelle(_ tri: CriteresDecouverte.Tri) -> String {
        switch tri {
        case .note: "Note"
        case .date: "Date de sortie"
        default: "Popularité"
        }
    }

    /// Les choix de la ligne ouverte, en pastilles ; le premier reçoit le focus quand on clique la ligne.
    @ViewBuilder
    private func choix(_ critere: Critere) -> some View {
        switch critere {
        case .categorie:
            ForEach(Array(Categorie.allCases.enumerated()), id: \.element) { rang, choix in
                puce(choix.rawValue, categorie == choix && !videos, rang: rang) { categorie = choix; videos = false }
            }
            // Sur le NAS, les vidéos personnelles quand elles sont activées (8.2.15), comme sur l'iPhone.
            if source == .nas, etat.videosPerso.actif {
                puce("Vidéos", videos, rang: Categorie.allCases.count) { videos = true }
            }
        case .disponibilite:
            ForEach(Array(Source.allCases.enumerated()), id: \.element) { rang, choix in
                puce(choix == .streaming ? "Mes plateformes" : choix.rawValue, sourceChoisie == choix, rang: rang) { sourceChoisie = choix }
                    .disabled(choix == .streaming && abonnements.isEmpty)
            }
        case .genres:
            ForEach(Array(genres.enumerated()), id: \.element.id) { rang, genre in
                let exclu = genresExclus.contains(genre.id)
                Button {
                    if genresChoisis.contains(genre.id) { genresChoisis.remove(genre.id) } else { genresExclus.remove(genre.id); genresChoisis.insert(genre.id) }
                } label: { Text(exclu ? "− \(genre.nom)" : genre.nom) }
                    .buttonStyle(BoutonTV(principal: genresChoisis.contains(genre.id), hauteur: 56))
                    .simultaneousGesture(LongPressGesture().onEnded { _ in
                        genresChoisis.remove(genre.id)
                        if exclu { genresExclus.remove(genre.id) } else { genresExclus.insert(genre.id) }
                    })
                    .foregroundStyle(exclu ? Theme.rouge : Color.white)
                    .focused($choixAuFocus, equals: rang)
            }
        case .periode:
            ForEach(Array(Periode.allCases.enumerated()), id: \.element) { rang, choix in
                puce(choix.rawValue, periode == choix, rang: rang) { periode = choix }
            }
        case .duree:
            ForEach(Array(Duree.allCases.enumerated()), id: \.element) { rang, choix in
                puce(choix.rawValue, duree == choix, rang: rang) { duree = choix }
            }
        case .acteurs:
            if acteursSuivis.isEmpty {
                Text("Suis un acteur depuis sa fiche : il apparaîtra ici.").font(.system(size: 24)).foregroundStyle(Theme.texte2)
            }
            ForEach(Array(acteursSuivis.enumerated()), id: \.element.personneID) { rang, acteur in
                puce(acteur.nom, acteurs.contains(acteur.personneID), rang: rang) {
                    if acteurs.contains(acteur.personneID) { acteurs.remove(acteur.personneID) } else { acteurs.insert(acteur.personneID) }
                }
            }
        case .note:
            ForEach(Array(Note.allCases.enumerated()), id: \.element) { rang, choix in
                puce(choix.rawValue, note == choix, rang: rang) { note = choix }
            }
        case .dejaVus:
            ForEach(Array(DejaVus.allCases.enumerated()), id: \.element) { rang, choix in
                puce(choix.rawValue, dejaVus == choix, rang: rang) { dejaVus = choix }
            }
        case .tri:
            ForEach(Array([CriteresDecouverte.Tri.popularite, .note, .date].enumerated()), id: \.offset) { rang, choix in
                puce(libelle(choix), tri == choix, rang: rang) { tri = choix }
            }
        }
    }

    private func puce(_ libelle: String, _ choisi: Bool, rang: Int, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(libelle) }
            .buttonStyle(BoutonTV(principal: choisi, hauteur: 56))
            .focused($choixAuFocus, equals: rang)
    }

    private func reinitialiser() {
        categorie = .films
        sourceChoisie = .toutes
        genresChoisis = []
        genresExclus = []
        periode = .toutes
        duree = .peuImporte
        note = .toutes
        tri = .popularite
        acteurs = []
        dejaVus = .tous
        recherche = ""
    }

    // MARK: Les résultats

    private var colonneResultats: some View {
        // 8.10 : ce qui est sur le NAS, calculé une fois pour toute la grille (chaque carte parcourait la bibliothèque).
        let surLeNAS = Set(fichiers.compactMap(\.reference))
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text(enCours && resultats.isEmpty ? "Recherche…" : resultats.count == 1 ? "1 titre" : "\(resultats.count) titres")
                        .font(.system(size: 32, weight: .bold))
                    Spacer()
                    Text("se mettent à jour à chaque choix").font(.system(size: 22)).foregroundStyle(Theme.texte2)
                }
                // Les personnes trouvées par le texte (8.9), en portraits : un clic ouvre leur fiche.
                if !personnes.isEmpty, !recherche.isEmpty {
                    Text("Personnes").font(.system(size: 28, weight: .bold))
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 30) {
                            ForEach(personnes.prefix(12)) { personne in
                                NavigationLink(value: PersonneTVRef(id: personne.id, nom: personne.nom)) {
                                    VStack(spacing: 10) {
                                        ImageTV(url: ImageTMDB.url(personne.cheminPortrait, .portrait), symboleVide: "person.fill")
                                            .frame(width: 150, height: 150)
                                            .clipShape(Circle())
                                        Text(personne.nom).font(.system(size: 22, weight: .semibold)).lineLimit(2)
                                            .multilineTextAlignment(.center).frame(width: 170)
                                    }
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 20)
                    }
                    .scrollClipDisabled()
                    .focusSection()
                }
                if !enCours, resultats.isEmpty {
                    Text(source == .nas ? "Aucun titre de cette catégorie sur ton NAS." : source == .tele ? "Rien de cette catégorie sur tes chaînes cette semaine."
                                        : "Élargis les filtres.")
                        .font(.system(size: 26)).foregroundStyle(Theme.texte2)
                }
                // Explorer › NAS › Vidéos (8.2.15) : les vidéos personnelles, comme sur l'iPhone.
                if source == .nas, videos {
                    VideosPersoTV(integree: true)
                } else {
                // 8.2.15 : les mêmes rangements que sur l'iPhone, en sections qu'on ouvre et qu'on ferme.
                if resultats.count > 1 {
                    HStack(spacing: 14) {
                        ForEach(["Pertinence", "Année", "Genre", "A→Z"], id: \.self) { mode in
                            Button(mode) {
                                rangement = mode
                                sections = SectionsRepliables(ouvertesParDefaut: mode != "Genre")
                            }
                            .buttonStyle(BoutonTV(principal: rangement == mode, hauteur: 56))
                        }
                    }
                    .focusSection()
                }
                ForEach(tranches, id: \.titre) { tranche in
                    if !tranche.titre.isEmpty {
                        Button { withAnimation(.snappy) { sections.basculer(tranche.titre) } } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "chevron.right").rotationEffect(.degrees(sections.ouverte(tranche.titre) ? 90 : 0))
                                Text(tranche.titre).font(.system(size: 32, weight: .bold))
                                Text("\(tranche.titres.count)").font(.system(size: 24)).foregroundStyle(Theme.texte2)
                            }
                        }
                        .buttonStyle(LienTV())
                    }
                    if tranche.titre.isEmpty || sections.ouverte(tranche.titre) {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(360), spacing: 34, alignment: .top), count: 3), spacing: 40) {
                            ForEach(tranche.titres) { apercu in
                                NavigationLink(value: apercu.reference) {
                                    CarteLargeTV(surtitre: surLeNAS.contains(apercu.reference) ? "Sur ton NAS" : nil, titre: apercu.titre, detail: apercu.sousTitre,
                                                 cheminImage: apercu.cheminFond ?? apercu.cheminAffiche, largeur: 360, reference: apercu.reference)
                                }
                                .buttonStyle(.card)
                                .menuCarteTV(apercu.reference, titre: apercu.titre, cheminAffiche: apercu.cheminAffiche)
                            }
                        }
                        .focusSection()
                    }
                }
                }
            }
            .padding(.vertical, 30)
            .padding(.trailing, MargesTV.bord)
        }
        .scrollClipDisabled()
        .focusSection()
    }

    /// Les documentaires ont leur catégorie (EF-151) ; les émissions ne sont pas des séries à regarder.
    private static let genresEcartes: Set<Int> = [99, 10763, 10764, 10767]
    private static let documentaire = 99

    private struct Cle: Hashable {
        let categorie: Categorie, source: Source, genres: Set<Int>, exclus: Set<Int>, periode: Periode, duree: Duree, note: Note
        let tri: CriteresDecouverte.Tri, acteurs: Set<Int>, dejaVus: DejaVus, recherche: String, pret: Bool
    }

    /// Déjà vus : un film avec un visionnage, une série terminée.
    private func estVu(_ reference: ReferenceTitre) -> Bool {
        if reference.type == .film { return visionnages.contains { $0.type == .film && $0.tmdbID == reference.tmdbID } }
        return suivis.contains { $0.reference == reference && $0.statut == .termine }
    }

    private func chercher() async {
        await chercherSansDejaVus()
        switch dejaVus {
        case .tous: break
        case .pasVus: resultats = resultats.filter { !estVu($0.reference) }
        case .vus: resultats = resultats.filter { estVu($0.reference) }
        }
    }

    private func chercherSansDejaVus() async {
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
                // 8.9 (bilan de l'Apple TV) : un texte tapé cherche partout — films, séries et personnes ensemble, comme
                // Netflix — et non plus dans la seule catégorie choisie (« Reacher » restait introuvable sous « Films »).
                // Ce qui est sur le NAS vient en tête. Les documentaires gardent leur filtre.
                let elements = (try? await client.rechercherTout(texte)) ?? []
                var titres = elements.compactMap { element -> TitreResume? in if case .titre(let titre) = element { titre } else { nil } }
                if categorie == .documentaires { titres = titres.filter { $0.genres.contains(Self.documentaire) } }
                personnes = elements.compactMap { element -> PersonneResume? in if case .personne(let personne) = element { personne } else { nil } }
                let surLeNAS = OeuvreTV.regrouper(fichiers.filter { $0.titre.localizedCaseInsensitiveContains(texte) })
                    .map { ApercuTV(reference: $0.reference, titre: $0.titre, sousTitre: $0.detail, cheminAffiche: $0.cheminAffiche, popularite: 0) }
                let dejaLa = Set(surLeNAS.map(\.reference))
                resultats = surLeNAS + titres.filter { !dejaLa.contains($0.reference) && $0.cheminAffiche != nil }.map { titre in
                    ApercuTV(reference: titre.reference, titre: titre.titre,
                             sousTitre: [titre.reference.type == .film ? "Film" : "Série", titre.date.map { String($0.annee) }].compactMap { $0 }.joined(separator: " · "),
                             cheminAffiche: titre.cheminAffiche, cheminFond: titre.cheminFond, popularite: 0,
                             genres: titre.genres, annee: titre.date?.annee, date: titre.date)
                }
                return
            }
            personnes = []
            var criteres = CriteresDecouverte()
            if categorie == .documentaires {
                criteres.genresInclus = [Self.documentaire] + Array(genresChoisis)
                criteres.combinaisonGenres = .tous
            } else {
                criteres.genresInclus = Array(genresChoisis)
            }
            criteres.genresExclus = Array(genresExclus.union(categorie == .documentaires ? [] : Self.genresEcartes))
            switch periode {
            case .toutes: break
            case .depuis2020: criteres.sortieDepuis = DateTMDB(annee: 2020, mois: 1, jour: 1)
            case .depuis2010: criteres.sortieDepuis = DateTMDB(annee: 2010, mois: 1, jour: 1)
            case .avant2000: criteres.sortieJusqua = DateTMDB(annee: 1999, mois: 12, jour: 31)
            }
            switch duree {
            case .peuImporte: break
            case .moinsDeDeuxHeures: criteres.dureeMax = 120
            case .moinsDUneHeureEtDemie: criteres.dureeMax = 90
            }
            switch note {
            case .toutes: break
            case .septEtPlus: criteres.noteMin = 7
            case .huitEtPlus: criteres.noteMin = 8
            }
            criteres.acteurs = Array(acteurs)
            criteres.combinaisonPersonnes = .auMoinsUn
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

/// Une ligne du panneau des filtres : le nom à gauche, la valeur à droite ; blanche au focus (`LigneTV`), un trait orange
/// à gauche quand ses choix sont ceux montrés dessous.
private struct LigneFiltreTV: View {
    let nom: String
    let valeur: String
    let ouverte: Bool
    @Environment(\.isFocused) private var aLeFocus

    var body: some View {
        HStack(spacing: 16) {
            Text(nom).font(.system(size: 26, weight: .semibold))
            Spacer(minLength: 12)
            Text(valeur).font(.system(size: 22, weight: .medium)).opacity(0.7).lineLimit(1)
        }
        .foregroundStyle(aLeFocus ? .black : .white)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .overlay(alignment: .leading) {
            if ouverte, !aLeFocus { Capsule().fill(Theme.accent).frame(width: 5, height: 30).padding(.leading, 4) }
        }
    }
}

/// Des boutons qui passent à la ligne quand la place manque : les genres, les périodes.
struct FluxTV: Layout {
    var espacement: CGFloat = 14

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let largeur = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, ligne: CGFloat = 0, maxX: CGFloat = 0
        for vue in subviews {
            let taille = vue.sizeThatFits(.unspecified)
            if x > 0, x + taille.width > largeur { x = 0; y += ligne + espacement; ligne = 0 }
            x += taille.width + espacement
            maxX = max(maxX, x - espacement)
            ligne = max(ligne, taille.height)
        }
        return CGSize(width: min(maxX, largeur), height: y + ligne)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, ligne: CGFloat = 0
        for vue in subviews {
            let taille = vue.sizeThatFits(.unspecified)
            if x > bounds.minX, x + taille.width > bounds.maxX { x = bounds.minX; y += ligne + espacement; ligne = 0 }
            vue.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(taille))
            x += taille.width + espacement
            ligne = max(ligne, taille.height)
        }
    }
}

/// Le clavier de tvOS au-dessus de la page, seulement pour la loupe.
private struct ClavierRecherche: ViewModifier {
    let actif: Bool
    @Binding var texte: String

    func body(content: Content) -> some View {
        if actif {
            content.searchable(text: $texte, prompt: "Films, séries, acteurs")
        } else {
            content
        }
    }
}
