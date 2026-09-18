import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Ce que l'accueil montre : tout le catalogue ou certaines plateformes, et les sections télé et NAS.
struct SourcesAccueil: Codable, Hashable {
    /// `nil` : tout le catalogue TMDB ; sinon, les plateformes choisies.
    var plateformes: [Int]?
    var top10 = true
    var tele = true
    var duMoment = true
    var nas = true

    init() {}

    var filtrees: [Int]? {
        guard let plateformes, !plateformes.isEmpty else { return nil }
        return plateformes.sorted()
    }

    var modifiees: Bool {
        filtrees != nil || !top10 || !tele || !duMoment || !nas
    }

    enum CodingKeys: String, CodingKey {
        case plateformes, top10, tele, duMoment, nas
    }

    /// Les réglages d'une version précédente restent valables : les sections ajoutées depuis sont affichées.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plateformes = try c.decodeIfPresent([Int].self, forKey: .plateformes)
        top10 = try c.decodeIfPresent(Bool.self, forKey: .top10) ?? true
        tele = try c.decodeIfPresent(Bool.self, forKey: .tele) ?? true
        duMoment = try c.decodeIfPresent(Bool.self, forKey: .duMoment) ?? true
        nas = try c.decodeIfPresent(Bool.self, forKey: .nas) ?? true
    }
}

@MainActor
@Observable
final class AccueilModele {
    /// « Du moment » : sorties et nouveaux épisodes des trente derniers jours, les plus populaires d'abord.
    var duMoment: [TitreResume] = []
    /// Pour chaque série du moment : l'épisode diffusé dans le mois, ou sa première diffusion.
    var datesSeries: [ReferenceTitre: String] = [:]
    /// Top 10 : cinq films et cinq séries parmi les mieux notés de l'année.
    var topFilms: [TitreResume] = []
    var topSeries: [TitreResume] = []
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

    /// Films et séries alternés, pour qu'aucun des deux ne masque l'autre.
    static func entrelacer(_ a: [TitreResume], _ b: [TitreResume]) -> [TitreResume] {
        (0..<max(a.count, b.count)).flatMap { i in [i < a.count ? a[i] : nil, i < b.count ? b[i] : nil].compactMap { $0 } }
    }

    /// Sans affiche, une carte ne dit rien ; hors français et anglais, pas de version regardable (EF-28).
    static func affichables(_ titres: [TitreResume]) -> [TitreResume] {
        titres.filter { $0.cheminAffiche != nil && RegleLangue.accepte(langueOriginale: $0.langueOriginale, exclu: false) }
    }

    /// Les cinq premiers de chaque type, avec affiche et en version regardable (EF-28), sur les plateformes choisies.
    func chargerTop(client: TMDBClient, plateformes: [Int]?) async {
        async let films = client.decouvrirFilms(Self.surPlateformes(CriteresDecouverte.top(.film), plateformes))
        async let series = client.decouvrirSeries(Self.surPlateformes(CriteresDecouverte.top(.serie), plateformes))
        func cinq(_ titres: [TitreResume]) -> [TitreResume] {
            Array(Self.affichables(titres).prefix(5))
        }
        topFilms = cinq((try? await films.resultats.map(\.titreResume)) ?? [])
        topSeries = cinq((try? await series.resultats.map(\.titreResume)) ?? [])
    }

    /// « Du moment » (EF-01) : films et séries entrelacés, sur les plateformes choisies ; les vingt premiers.
    func charger(client: TMDBClient, plateformes: [Int]?) async {
        erreur = nil
        do {
            async let films = client.decouvrirFilms(Self.surPlateformes(CriteresDecouverte.duMoment(.film), plateformes))
            async let series = client.decouvrirSeries(Self.surPlateformes(CriteresDecouverte.duMoment(.serie), plateformes))
            let listeFilms = Self.affichables(try await films.resultats.map(\.titreResume))
            let listeSeries = Self.affichables(try await series.resultats.map(\.titreResume))
            let titres = Array(Self.entrelacer(listeFilms, listeSeries).prefix(20))
            datesSeries = await DatesNouveautes.episodes(titres.filter { $0.reference.type == .serie }, client: client)
            duMoment = titres
        } catch is CancellationError {
            return
        } catch {
            erreur = Journal.conseil(error) ?? "TMDB ne répond pas pour l'instant : tire vers le bas pour réessayer."
            erreurDetaillee = error
        }
        charge = true
    }

    /// Sous l'affiche : la date de sortie d'un film, le dernier épisode d'une série.
    func sousTitre(_ titre: TitreResume) -> String? {
        titre.reference.type == .film ? titre.date.map { "Sortie \(LibelleDate.jour($0))" } : datesSeries[titre.reference]
    }
}

/// Écrans ouverts depuis l'accueil, en plus des fiches.
enum DestinationAccueil: Hashable {
    case nas
    case tele
    case duMoment(plateformes: [Int]?)
}

struct AccueilView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(filter: #Predicate<Abonnement> { $0.actif }, sort: \Abonnement.nom) private var abonnements: [Abonnement]
    @Query(sort: \Diffusion.debut) private var diffusions: [Diffusion]
    @AppStorage("accueil.sources") private var sourcesBrutes = Data()
    @State private var modele = AccueilModele()
    @State private var reglageSources = false
    @State private var chemin = NavigationPath()
    @Query(sort: \SelectionSoir.ajouteLe) private var selections: [SelectionSoir]

    /// « Ce soir : Heat, Reacher », ou la prochaine soirée prévue ; rien quand aucune soirée n'est prévue.
    private var resumeSoiree: String? {
        let jour = ServiceSoiree.soiree()
        let ceSoir = selections.filter { $0.soiree == jour }.map(\.titre)
        if !ceSoir.isEmpty {
            return "Ce soir : " + ceSoir.prefix(2).joined(separator: ", ") + (ceSoir.count > 2 ? " et \(Format.pluriel(ceSoir.count - 2, "autre"))" : "")
        }
        guard let prochaine = selections.filter({ $0.soiree > jour }).min(by: { $0.soiree < $1.soiree }) else { return nil }
        return "\(LibelleSoiree.soiree(prochaine.soiree)) : \(prochaine.titre)"
    }

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
                            async let moment: Void = modele.charger(client: client, plateformes: plateformes)
                            async let top: Void = modele.chargerTop(client: client, plateformes: plateformes)
                            _ = await (moment, top)
                        }
                        .refreshable {
                            async let moment: Void = modele.charger(client: client, plateformes: plateformes)
                            async let top: Void = modele.chargerTop(client: client, plateformes: plateformes)
                            _ = await (moment, top)
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
            .boutonBarreLaterale()
            .destinationsTitres()
            .navigationDestination(for: DestinationAccueil.self) { destination in
                switch destination {
                case .nas: NASView()
                case .tele: ProgrammeTeleView()
                case .duMoment(let plateformes): DuMomentView(plateformes: plateformes)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { reglageSources = true } label: {
                        Label("Personnaliser", systemImage: "slider.horizontal.3")
                            .labelStyle(.titleAndIcon)
                    }
                    .help("Choisir les plateformes et les sections de l'accueil")
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
                // Les cinq premiers du moment qui ont une image de fond.
                BandeauVedette(titres: Array(modele.duMoment.filter { $0.cheminFond != nil }.prefix(5)))

                if let erreur = modele.erreur {
                    MessageEtat(texte: erreur, ton: .probleme, libelleAction: "Réessayer") {
                        guard let client = etat.tmdb else { return }
                        Task {
                            await modele.charger(client: client, plateformes: plateformes)
                            await modele.chargerTop(client: client, plateformes: plateformes)
                        }
                    }
                }

                if let resumeSoiree {
                    Button { etat.ongletDemande = .ceSoir } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "moon.stars.fill").foregroundStyle(Theme.accent)
                            Text(resumeSoiree).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .accessibilityHint("Ouvre Ce soir")
                }

                // Accueil limité à certaines plateformes : c'est dit, et modifiable d'un geste.
                if let plateformes {
                    Button { reglageSources = true } label: {
                        Label("Sur \(nomsPlateformes(plateformes)) seulement · Modifier", systemImage: "play.tv")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Theme.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accentClair)
                    .padding(.horizontal, 20)
                }

                if sources.top10, !modele.topFilms.isEmpty || !modele.topSeries.isEmpty {
                    SectionTop10(films: modele.topFilms, series: modele.topSeries,
                                 plateformes: plateformes.map(nomsPlateformes))
                }

                if sources.tele {
                    SectionTele(diffusions: diffusions, lectureEnCours: etat.teleEnCours) {
                        chemin.append(DestinationAccueil.tele)
                    }
                }

                if sources.duMoment, !modele.duMoment.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        TitreSection(titre: "Du moment") {
                            BoutonToutVoir { chemin.append(DestinationAccueil.duMoment(plateformes: plateformes)) }
                        }
                        Text(plateformes.map { "Sorties et nouveaux épisodes du mois, les plus populaires d'abord · sur \(nomsPlateformes($0))" }
                             ?? "Sorties et nouveaux épisodes du mois, les plus populaires d'abord")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                        Carrousel(titres: modele.duMoment) { modele.sousTitre($0) }
                    }
                }

                if sources.nas {
                    SectionNAS { chemin.append(DestinationAccueil.nas) }
                }

            }
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(edges: .top)
        .overlay {
            if !modele.charge { ProgressView() }
        }
    }

    private func nomsPlateformes(_ ids: [Int]) -> String {
        let noms = abonnements.filter { ids.contains($0.providerID) }.map(\.nom)
        return noms.count > 2 ? "\(noms.count) plateformes" : noms.joined(separator: " et ")
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
                    Text("Plateformes")
                } footer: {
                    Text("Le bandeau, le Top 10 de l'année et « Du moment » ne montrent que ce qui est disponible sur les plateformes choisies.")
                }

                Section {
                    Toggle("Top 10 de l'année", isOn: $sources.top10).tint(Theme.accent)
                    Toggle("Ce soir à la télé", isOn: $sources.tele).tint(Theme.accent)
                    Toggle("Du moment", isOn: $sources.duMoment).tint(Theme.accent)
                    Toggle("Sur ton NAS", isOn: $sources.nas).tint(Theme.accent)
                } header: {
                    Text("Sections de l'accueil")
                } footer: {
                    Text("Le bandeau en haut reprend les cinq premiers titres du moment.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.fond)
            .titreDeFeuille("Personnaliser l'accueil")
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
    @State private var page = 0
    @State private var survolFleche = false

    var body: some View {
        pages
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            // Sur le Mac, les pages ne se glissent pas à la souris : une flèche de chaque côté, en boucle. Pendant
            // le survol d'une flèche, la page du dessous ignore les clics, sinon elle ouvrirait sa fiche.
            #if targetEnvironment(macCatalyst)
            .allowsHitTesting(!survolFleche)
            .overlay(alignment: .leading) {
                if titres.count > 1 {
                    FlecheDefilement(sens: .gauche, survol: $survolFleche) { tourner(-1) }
                        .padding(.leading, 12)
                }
            }
            .overlay(alignment: .trailing) {
                if titres.count > 1 {
                    FlecheDefilement(sens: .droite, survol: $survolFleche) { tourner(1) }
                        .padding(.trailing, 12)
                }
            }
            #endif
            .frame(height: 440)
    }

    private var pages: some View {
        TabView(selection: $page) {
            ForEach(Array(titres.enumerated()), id: \.element.id) { rang, titre in
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
                .tag(rang)
            }
        }
    }

    private func tourner(_ sens: Int) {
        guard !titres.isEmpty else { return }
        withAnimation(.snappy) { page = (page + sens + titres.count) % titres.count }
    }
}

private struct Carrousel: View {
    let titres: [TitreResume]
    /// Ligne sous le titre à la place de l'année, par exemple la date de sortie.
    var sousTitre: (TitreResume) -> String? = { _ in nil }

    var body: some View {
        DefilementHorizontal {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(titres) { titre in
                    NavigationLink(value: titre.reference) {
                        CarteAffiche(titre: titre, sousTitre: sousTitre(titre))
                    }
                    .buttonStyle(.plain)
                    .actionsRapides(titre)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 20)
        }
        .scrollTargetBehavior(.viewAligned)
    }
}

/// Top 10 de l'année : cinq films puis cinq séries, chacun avec son rang en grand.
private struct SectionTop10: View {
    let films: [TitreResume]
    let series: [TitreResume]
    /// « Sur Netflix et Prime Video » quand l'accueil est limité à certaines plateformes.
    let plateformes: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TitreSection("Top 10 de l'année")
            Text(plateformes.map { "Les mieux notés sur TMDB depuis un an · sur \($0)" } ?? "Les mieux notés sur TMDB depuis un an")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            DefilementHorizontal {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(Array(films.enumerated()), id: \.element.id) { rang, titre in
                        carte(titre, rang: rang + 1)
                    }
                    if !films.isEmpty, !series.isEmpty {
                        Rectangle()
                            .fill(.white.opacity(0.12))
                            .frame(width: 1, height: 170)
                            .padding(.horizontal, 6)
                    }
                    ForEach(Array(series.enumerated()), id: \.element.id) { rang, titre in
                        carte(titre, rang: rang + 1)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func carte(_ titre: TitreResume, rang: Int) -> some View {
        NavigationLink(value: titre.reference) {
            HStack(alignment: .bottom, spacing: -14) {
                Text("\(rang)")
                    .font(.system(size: 88, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.degradeAccent)
                    .shadow(color: .black.opacity(0.6), radius: 4)
                    .padding(.bottom, 44)
                    .accessibilityHidden(true)
                CarteAffiche(titre: titre, sousTitre: titre.reference.type == .film ? "Film" : "Série")
            }
        }
        .buttonStyle(.plain)
        .actionsRapides(titre)
        .accessibilityLabel("Numéro \(rang) des \(titre.reference.type == .film ? "films" : "séries") : \(titre.titre)")
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
                DefilementHorizontal {
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
                DefilementHorizontal {
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
    static func episodes(_ series: [TitreResume], client: TMDBClient) async -> [ReferenceTitre: String] {
        let (debut, fin) = CriteresDecouverte.bornesDuMoment()
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
