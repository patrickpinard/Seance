import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Ce que l'accueil montre : tout le catalogue ou certaines plateformes, et les sections télé et NAS.
struct SourcesAccueil: Codable, Hashable {
    /// `nil` : tout le catalogue TMDB ; sinon, les plateformes choisies.
    var plateformes: [Int]?
    var tele = true
    var nas = true

    var filtrees: [Int]? {
        guard let plateformes, !plateformes.isEmpty else { return nil }
        return plateformes.sorted()
    }

    var modifiees: Bool {
        filtrees != nil || !tele || !nas
    }
}

@MainActor
@Observable
final class AccueilModele {
    var tendancesJour: [TitreResume] = []
    var tendancesSemaine: [TitreResume] = []
    /// Nouveaux films et séries avec un épisode récent, du jour ou de la semaine.
    var nouveauxFilms: [TitreResume] = []
    var nouvellesSeries: [TitreResume] = []
    /// Pour chaque série : l'épisode diffusé dans la période, ou sa première diffusion.
    var datesSeries: [ReferenceTitre: String] = [:]
    var nouveautesChargees = false
    var erreur: String?
    /// Dernière erreur, pour le journal ; `erreur` garde la phrase affichée.
    var erreurDetaillee: (any Error)?
    var charge = false

    /// Critères limités aux plateformes choisies, en abonnement ou gratuites, en Suisse.
    static func surPlateformes(_ criteres: CriteresDecouverte, _ plateformes: [Int]?) -> CriteresDecouverte {
        guard let plateformes, !plateformes.isEmpty else { return criteres }
        var c = criteres
        c.fournisseurs = plateformes
        c.monetisations = [.abonnement, .gratuit, .avecPublicite]
        return c
    }

    /// TMDB n'a pas de tendances par plateforme : ce sont alors les titres les plus populaires qu'elles proposent.
    static func populaires(_ plateformes: [Int]) -> CriteresDecouverte {
        var c = surPlateformes(CriteresDecouverte(), plateformes)
        c.votesMin = 50
        return c
    }

    /// Films et séries alternés, pour qu'aucun des deux ne masque l'autre.
    static func entrelacer(_ a: [TitreResume], _ b: [TitreResume]) -> [TitreResume] {
        (0..<max(a.count, b.count)).flatMap { i in [i < a.count ? a[i] : nil, i < b.count ? b[i] : nil].compactMap { $0 } }
    }

    func chargerNouveautes(client: TMDBClient, periode: PeriodeTendance, plateformes: [Int]?) async {
        async let films = client.decouvrirFilms(Self.surPlateformes(CriteresDecouverte.nouveautes(.film, periode: periode), plateformes))
        async let series = client.decouvrirSeries(Self.surPlateformes(CriteresDecouverte.nouveautes(.serie, periode: periode), plateformes))
        // Sans affiche, une carte ne dit rien ; hors français et anglais, pas de version regardable (EF-28).
        func retenir(_ titres: [TitreResume]) -> [TitreResume] {
            titres.filter { $0.cheminAffiche != nil && RegleLangue.accepte(langueOriginale: $0.langueOriginale, exclu: false) }
        }
        nouveauxFilms = retenir((try? await films.resultats.map(\.titreResume)) ?? [])
        let seriesRetenues = retenir((try? await series.resultats.map(\.titreResume)) ?? [])
        datesSeries = await DatesNouveautes.episodes(seriesRetenues, periode: periode, client: client)
        nouvellesSeries = seriesRetenues
        nouveautesChargees = true
    }

    /// Tendances (EF-01) : celles de TMDB pour tout le catalogue, sinon les titres populaires des plateformes choisies.
    func charger(client: TMDBClient, plateformes: [Int]?) async {
        erreur = nil
        do {
            if let plateformes {
                async let films = client.decouvrirFilms(Self.populaires(plateformes))
                async let series = client.decouvrirSeries(Self.populaires(plateformes))
                let melange = Self.entrelacer(try await films.resultats.map(\.titreResume), try await series.resultats.map(\.titreResume))
                tendancesJour = melange
                tendancesSemaine = melange
            } else {
                async let jour = client.tendances(.jour)
                async let semaine = client.tendances(.semaine)
                tendancesJour = try await jour
                tendancesSemaine = try await semaine
            }
        } catch is CancellationError {
            return
        } catch {
            erreur = Journal.conseil(error) ?? "TMDB ne répond pas pour l'instant : tire vers le bas pour réessayer."
            erreurDetaillee = error
        }
        charge = true
    }
}

/// Écrans ouverts depuis l'accueil, en plus des fiches.
enum DestinationAccueil: Hashable {
    case nas
    case tele
    case nouveautes(PeriodeTendance, plateformes: [Int]?)
    case tendances(PeriodeTendance, plateformes: [Int]?)
}

struct AccueilView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(filter: #Predicate<Abonnement> { $0.actif }, sort: \Abonnement.nom) private var abonnements: [Abonnement]
    @Query(sort: \Diffusion.debut) private var diffusions: [Diffusion]
    @AppStorage("accueil.sources") private var sourcesBrutes = Data()
    @State private var modele = AccueilModele()
    @State private var periodeTendances = PeriodeTendance.jour
    @State private var periodeNouveautes = PeriodeTendance.jour
    @State private var reglageSources = false
    /// EF-62 : les tendances et les nouveautés reclassées selon les goûts, sans réseau ni Claude.
    @State private var pourToi: [SuggestionClassee] = []
    @State private var chemin = NavigationPath()

    private var sources: SourcesAccueil {
        (try? JSONDecoder().decode(SourcesAccueil.self, from: sourcesBrutes)) ?? SourcesAccueil()
    }

    /// Les plateformes choisies encore cochées dans les réglages.
    private var plateformes: [Int]? {
        sources.filtrees.map { ids in ids.filter { id in abonnements.contains { $0.providerID == id } } }.flatMap { $0.isEmpty ? nil : $0 }
    }

    var body: some View {
        NavigationStack(path: $chemin) {
            Group {
                if let client = etat.tmdb {
                    contenu
                        .task(id: plateformes) {
                            await modele.charger(client: client, plateformes: plateformes)
                            rafraichirPourToi()
                        }
                        .task(id: CleNouveautes(periode: periodeNouveautes, plateformes: plateformes)) {
                            await modele.chargerNouveautes(client: client, periode: periodeNouveautes, plateformes: plateformes)
                            rafraichirPourToi()
                        }
                        .refreshable {
                            await modele.charger(client: client, plateformes: plateformes)
                            await modele.chargerNouveautes(client: client, periode: periodeNouveautes, plateformes: plateformes)
                            rafraichirPourToi()
                        }
                        .onChange(of: modele.erreur) { _, erreur in
                            guard erreur != nil else { return }
                            etat.journal.noter(.tmdb, "L'accueil n'a pas pu se charger.", erreur: modele.erreurDetaillee)
                        }
                } else {
                    InviteCleTMDB()
                }
            }
            .background(Theme.fond)
            .destinationsTitres()
            .navigationDestination(for: DestinationAccueil.self) { destination in
                switch destination {
                case .nas: NASView()
                case .tele: ProgrammeTeleView()
                case .nouveautes(let periode, let plateformes): NouveautesView(periode: periode, plateformes: plateformes)
                case .tendances(let periode, let plateformes): TendancesView(periode: periode, plateformes: plateformes)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { reglageSources = true } label: {
                        Label("Sources", systemImage: sources.modifiees ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .help("Choisir les sources affichées : plateformes, télévision, NAS")
                    .accessibilityIdentifier("boutonSources")
                    if sources.nas {
                        Button { chemin.append(DestinationAccueil.nas) } label: {
                            Label("NAS", systemImage: "externaldrive.fill")
                        }
                        .help("Ouvrir la bibliothèque du NAS")
                        .accessibilityIdentifier("boutonNAS")
                    }
                }
            }
            .sheet(isPresented: $reglageSources) {
                ReglageSourcesAccueil(sources: Binding {
                    sources
                } set: { nouvelles in
                    sourcesBrutes = (try? JSONEncoder().encode(nouvelles)) ?? Data()
                }, abonnements: abonnements)
            }
        }
        .onChange(of: etat.ficheDemandee, initial: true) { _, reference in
            guard let reference else { return }
            chemin.append(reference)
            etat.ficheDemandee = nil
        }
    }

    private var contenu: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                BandeauVedette(titres: Array(modele.tendancesSemaine.prefix(5)))

                if let erreur = modele.erreur {
                    MessageEtat(texte: erreur, ton: .probleme, libelleAction: "Réessayer") {
                        guard let client = etat.tmdb else { return }
                        Task {
                            await modele.charger(client: client, plateformes: plateformes)
                            rafraichirPourToi()
                        }
                    }
                }

                if !pourToi.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        TitreSection("Pour toi")
                        CarrouselExplique(suggestions: pourToi)
                    }
                }

                if sources.tele {
                    SectionTele(diffusions: diffusions, lectureEnCours: etat.teleEnCours) {
                        chemin.append(DestinationAccueil.tele)
                    }
                }

                SectionNouveautes(modele: modele, periode: $periodeNouveautes) {
                    chemin.append(DestinationAccueil.nouveautes(periodeNouveautes, plateformes: plateformes))
                }

                if sources.nas {
                    SectionNAS { chemin.append(DestinationAccueil.nas) }
                }

                VStack(alignment: .leading, spacing: 12) {
                    TitreSection(titre: plateformes == nil ? "Tendances" : "Populaires") {
                        if plateformes == nil {
                            ChoixPeriode(periode: $periodeTendances)
                        }
                        BoutonToutVoir { chemin.append(DestinationAccueil.tendances(periodeTendances, plateformes: plateformes)) }
                    }
                    if let plateformes {
                        Text("Sur \(nomsPlateformes(plateformes))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                    }
                    Carrousel(titres: periodeTendances == .semaine ? modele.tendancesSemaine : modele.tendancesJour)
                }
            }
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(edges: .top)
        .overlay {
            if !modele.charge { ProgressView() }
        }
    }

    private struct CleNouveautes: Hashable {
        let periode: PeriodeTendance
        let plateformes: [Int]?
    }

    private func nomsPlateformes(_ ids: [Int]) -> String {
        let noms = abonnements.filter { ids.contains($0.providerID) }.map(\.nom)
        return noms.count > 2 ? "\(noms.count) plateformes" : noms.joined(separator: " et ")
    }

    /// Le même classement que « Ce soir », appliqué à ce qui est déjà affiché : aucun appel
    /// supplémentaire à TMDB, et rien qui sorte de l'appareil.
    private func rafraichirPourToi() {
        let gouts = ServiceGouts(contexte: contexte)
        guard let profil = try? gouts.profil(), !profil.estVide,
              let exclusions = try? gouts.contexteCandidats()
        else {
            pourToi = []
            return
        }
        var vues = Set<ReferenceTitre>()
        let candidats = (modele.nouveauxFilms + modele.nouvellesSeries + modele.tendancesSemaine + modele.tendancesJour)
            .filter { vues.insert($0.reference).inserted }
            .filter { !exclusions.dejaVus.contains($0.reference) && !exclusions.exclus.contains($0.reference) }
            .filter { RegleLangue.accepte(langueOriginale: $0.langueOriginale, exclu: false) }
            .map { CandidatSuggestion(titre: $0) }
        pourToi = Array(ClassementLocal.classer(candidats, profil: profil, nomsGenres: etat.nomsGenres).prefix(12))
    }
}

/// Période d'une section, en menu compact : « Aujourd'hui ⌄ ».
struct ChoixPeriode: View {
    @Binding var periode: PeriodeTendance

    var body: some View {
        Menu {
            Picker("Période", selection: $periode) {
                Text("Aujourd'hui").tag(PeriodeTendance.jour)
                Text("Cette semaine").tag(PeriodeTendance.semaine)
            }
        } label: {
            HStack(spacing: 4) {
                Text(periode == .jour ? "Aujourd'hui" : "Semaine")
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Theme.surface, in: Capsule())
        }
        .fixedSize()
    }
}

/// Feuille « Sources » de l'accueil : plateformes affichées, télévision et NAS.
private struct ReglageSourcesAccueil: View {
    @Binding var sources: SourcesAccueil
    let abonnements: [Abonnement]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Afficher", selection: Binding {
                        sources.plateformes == nil
                    } set: { toutLeCatalogue in
                        sources.plateformes = toutLeCatalogue ? nil : abonnements.map(\.providerID)
                    }) {
                        Text("Tout le catalogue").tag(true)
                        Text("Mes plateformes").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)

                    if sources.plateformes != nil {
                        if abonnements.isEmpty {
                            Text("Coche d'abord tes abonnements dans Réglages › Plateformes.").foregroundStyle(.secondary)
                        }
                        ForEach(abonnements) { abonnement in
                            Toggle(abonnement.nom, isOn: Binding {
                                sources.plateformes?.contains(abonnement.providerID) == true
                            } set: { actif in
                                var liste = sources.plateformes ?? []
                                if actif { liste.append(abonnement.providerID) } else { liste.removeAll { $0 == abonnement.providerID } }
                                sources.plateformes = liste
                            })
                            .tint(Theme.accent)
                        }
                    }
                } header: {
                    Text("Films et séries")
                } footer: {
                    Text("Nouveautés, tendances et suggestions « Pour toi » ne montrent que ce qui est disponible sur les plateformes choisies.")
                }

                Section {
                    Toggle("Ce soir à la télé", isOn: $sources.tele).tint(Theme.accent)
                    Toggle("Sur ton NAS", isOn: $sources.nas).tint(Theme.accent)
                } header: {
                    Text("Aussi sur l'accueil")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.fond)
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.fond)
    }
}

/// UX-01 : bandeau vedette à faire défiler.
private struct BandeauVedette: View {
    let titres: [TitreResume]

    var body: some View {
        TabView {
            ForEach(titres) { titre in
                NavigationLink(value: titre.reference) {
                    ZStack(alignment: .bottomLeading) {
                        ImageDistante(url: ImageTMDB.url(titre.cheminFond, .fondGrand), coins: 0)
                        LinearGradient(colors: [.clear, .clear, Theme.fond.opacity(0.8), Theme.fond],
                                       startPoint: .top, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(titre.titre)
                                .font(.system(size: 32, weight: .heavy))
                                .lineLimit(2)
                            HStack(spacing: 10) {
                                AnneauNote(pourcentage: titre.pourcentageNote)
                                if let annee = titre.date?.annee { Text(String(annee)) }
                                Text(titre.reference.type == .film ? "Film" : "Série")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 44)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(height: 440)
    }
}

private struct Carrousel: View {
    let titres: [TitreResume]
    /// Ligne sous le titre à la place de l'année, par exemple la date de sortie.
    var sousTitre: (TitreResume) -> String? = { _ in nil }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(titres) { titre in
                    NavigationLink(value: titre.reference) {
                        CarteAffiche(titre: titre, sousTitre: sousTitre(titre))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollTargetBehavior(.viewAligned)
    }
}

/// Comme le carrousel, mais chaque affiche dit en une ligne pourquoi elle est là.
private struct CarrouselExplique: View {
    let suggestions: [SuggestionClassee]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(suggestions) { suggestion in
                    NavigationLink(value: suggestion.reference) {
                        VStack(alignment: .leading, spacing: 6) {
                            CarteAffiche(titre: suggestion.candidat.titre, largeur: 140)
                            Text(suggestion.phrase)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(3, reservesSpace: true)
                                .frame(width: 140, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

/// Aperçu du NAS : les arrivées du dossier NEW d'abord, puis les films les mieux notés.
private struct SectionNAS: View {
    let toutVoir: () -> Void
    @Query(filter: #Predicate<FichierNAS> { $0.tmdbID != nil }, sort: \FichierNAS.noteMoyenne, order: .reverse)
    private var fichiers: [FichierNAS]

    var body: some View {
        let oeuvres = OeuvreNAS.regrouper(fichiers)
        let apercu = Array((oeuvres.filter(\.nouveaute) + oeuvres.filter { !$0.nouveaute }).prefix(15))
        if !apercu.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                TitreSection(titre: "Sur ton NAS") {
                    BoutonToutVoir(action: toutVoir)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(apercu) { oeuvre in
                            CarteOeuvreNAS(oeuvre: oeuvre, largeur: 118)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
}

/// Les nouveautés du jour ou de la semaine : films sortis, puis séries avec un épisode diffusé.
private struct SectionNouveautes: View {
    let modele: AccueilModele
    @Binding var periode: PeriodeTendance
    let toutVoir: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TitreSection(titre: "Nouveautés") {
                ChoixPeriode(periode: $periode)
                BoutonToutVoir(action: toutVoir)
            }
            if modele.nouveautesChargees && modele.nouveauxFilms.isEmpty && modele.nouvellesSeries.isEmpty {
                if periode == .jour {
                    MessageEtat(texte: "Rien de neuf aujourd'hui.", symbole: "calendar", libelleAction: "Voir la semaine") { periode = .semaine }
                } else {
                    MessageEtat(texte: "Aucune nouveauté cette semaine.", symbole: "calendar")
                }
            }
            if !modele.nouveauxFilms.isEmpty {
                sousTitre("Films")
                Carrousel(titres: modele.nouveauxFilms) { titre in
                    titre.date.map { "Sortie \(LibelleDate.jour($0))" }
                }
            }
            if !modele.nouvellesSeries.isEmpty {
                sousTitre("Séries et nouveaux épisodes")
                Carrousel(titres: modele.nouvellesSeries) { titre in
                    modele.datesSeries[titre.reference]
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: periode)
    }

    private func sousTitre(_ texte: String) -> some View {
        Text(texte.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
    }
}

/// UX-19 : cartes larges des diffusions de ce soir ; quand la soirée est vide ou passée,
/// les prochains films de la semaine.
private struct SectionTele: View {
    let diffusions: [Diffusion]
    let lectureEnCours: Bool
    let toutVoir: () -> Void
    @Query private var chaines: [Chaine]

    /// EF-46 : ce qui commence entre 20 h et 23 h aujourd'hui et n'est pas terminé ; les films d'abord.
    private var ceSoir: [Diffusion] {
        let jour = DateTMDB(.now)
        let debut = jour.instant(heure: 20)
        let fin = jour.instant(heure: 23)
        return diffusions
            .filter { $0.debut >= debut && $0.debut <= fin && $0.fin > .now }
            .sorted { ($0.typeBrut == TypeTitre.film.rawValue ? 0 : 1, $0.debut) < ($1.typeBrut == TypeTitre.film.rawValue ? 0 : 1, $1.debut) }
    }

    /// Les séries passent tous les jours : la suite de la semaine ne montre que les films.
    private var prochainement: [Diffusion] {
        Array(diffusions.filter { $0.debut > .now && $0.typeBrut == TypeTitre.film.rawValue }.prefix(12))
    }

    var body: some View {
        let soir = ceSoir
        let affichees = soir.isEmpty ? prochainement : soir
        VStack(alignment: .leading, spacing: 12) {
            TitreSection(titre: soir.isEmpty ? "Prochainement à la télé" : "Ce soir à la télé") {
                if lectureEnCours {
                    ProgressView().controlSize(.small)
                } else if !soir.isEmpty {
                    Circle().fill(.red).frame(width: 8, height: 8)
                }
                if !diffusions.isEmpty {
                    BoutonToutVoir(action: toutVoir)
                }
            }
            if affichees.isEmpty {
                if lectureEnCours {
                    MessageEtat(texte: "Lecture des programmes de tes chaînes…", ton: .attente)
                } else {
                    MessageEtat(texte: "Aucun film reconnu sur tes chaînes pour l'instant. Choisis-les dans Réglages › Télévision.", symbole: "tv")
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(affichees) { diffusion in
                            carte(diffusion)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    @ViewBuilder
    private func carte(_ diffusion: Diffusion) -> some View {
        let enCours = diffusion.debut <= .now
        let contenu = ZStack(alignment: .bottomLeading) {
            ImageDistante(url: image(diffusion), coins: 0)
            LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(nomChaine(diffusion.chaine))
                        .font(.caption.weight(.heavy))
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.white, in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(.black)
                    Group {
                        if enCours {
                            Text("En cours").foregroundStyle(.red)
                        } else if Calendar.current.isDateInToday(diffusion.debut) {
                            Text(diffusion.debut, format: .dateTime.hour().minute())
                        } else {
                            Text(diffusion.debut, format: .dateTime.weekday(.abbreviated).day().hour().minute())
                        }
                    }
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                }
                Spacer()
                Text(diffusion.titreGuide).font(.headline).lineLimit(2)
                Text(detail(diffusion))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(12)
            .foregroundStyle(.white)
        }
        .frame(width: 280, height: 158)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

        if let tmdbID = diffusion.tmdbID {
            NavigationLink(value: ReferenceTitre(type: TypeTitre(rawValue: diffusion.typeBrut) ?? .film, tmdbID: tmdbID)) { contenu }
                .buttonStyle(.plain)
        } else {
            contenu
        }
    }

    /// L'image de fond TMDB en priorité, puis l'affiche, puis la vignette du guide.
    private func image(_ diffusion: Diffusion) -> URL? {
        ImageTMDB.url(diffusion.cheminFond, .fond)
            ?? ImageTMDB.url(diffusion.cheminAffiche, .fond)
            ?? diffusion.imageGuide.flatMap(URL.init(string:))
    }

    /// « Film · 2000 · 155 min », « Série · S02E05 · 45 min ».
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

    private func nomChaine(_ identifiant: String) -> String {
        chaines.first { $0.identifiantGuide == identifiant }?.nom ?? identifiant
    }
}

/// « aujourd'hui », « hier », « lun. 14 sept. ».
enum LibelleDate {
    static func jour(_ date: DateTMDB, maintenant: Date = .now) -> String {
        let aujourdhui = DateTMDB(maintenant)
        if date == aujourdhui { return "aujourd'hui" }
        if date == DateTMDB(maintenant.addingTimeInterval(-86_400)) { return "hier" }
        let instant = date.instant(heure: 12)
        return instant.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "fr_CH")))
    }
}

/// Dates affichées sous les nouveautés : l'épisode diffusé dans la période, ou la première diffusion.
enum DatesNouveautes {
    /// `discover` ne dit pas quel épisode est sorti : la fiche de chaque série le donne.
    static func episodes(_ series: [TitreResume], periode: PeriodeTendance, client: TMDBClient) async -> [ReferenceTitre: String] {
        let (debut, fin) = periode.bornes()
        return await withTaskGroup(of: (ReferenceTitre, String?).self) { groupe in
            for titre in series {
                groupe.addTask {
                    guard let serie = try? await client.serie(titre.reference.tmdbID) else { return (titre.reference, nil) }
                    if let episode = serie.episodeNouveau(depuis: debut, jusqua: fin), let date = episode.dateDiffusion {
                        return (titre.reference, "S\(episode.saison)E\(episode.numero) · \(LibelleDate.jour(date))")
                    }
                    if serie.commence(depuis: debut, jusqua: fin), let date = serie.premiereDiffusion {
                        return (titre.reference, "Nouvelle · \(LibelleDate.jour(date))")
                    }
                    return (titre.reference, nil)
                }
            }
            var dates: [ReferenceTitre: String] = [:]
            for await (reference, libelle) in groupe {
                dates[reference] = libelle
            }
            return dates
        }
    }
}
