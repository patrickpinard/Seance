import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Ce que l'accueil montre : tout le catalogue ou seulement tes plateformes, ses sections, et combien de titres.
/// Les plateformes elles-mêmes se cochent à un seul endroit : Réglages › Plateformes.
struct SourcesAccueil: Codable, Hashable {
    /// `nil` : tout le catalogue TMDB ; sinon, seulement tes plateformes. (Une ancienne version y gardait une liste
    /// choisie ici, en double des réglages : seule sa présence compte désormais.)
    var plateformes: [Int]?
    var top10 = true
    var tele = true
    var duMoment = true
    var nas = true
    /// « Dans ta liste, regardable ce soir » : ce que tu voulais voir et qui est sur le NAS, tes plateformes ou la TV.
    var regardable = true
    /// « Documentaires pour toi » : la troisième catégorie, selon les thèmes cochés (EF-154).
    var documentaires = true
    /// Films et séries du classement, chacun : 3, 5 ou 10.
    var nombreTop = 5
    /// Titres de « Nouveautés » : 10, 20 ou 30.
    var nombreDuMoment = 20
    /// Titres du bandeau : 3, 5 ou 8. Plus montré depuis la 8.1 (la proposition du soir l'a remplacé) ; gardé pour relire
    /// les anciens réglages.
    var nombreBandeau = 5
    /// « Ce soir à la TV » montre aussi les séries ; sinon, seulement les films.
    var seriesTele = true
    /// Les propositions du soir en tête de l'accueil (8.5), qu'on fait défiler : 1, 3, 5 ou 8.
    var nombrePropositions = 5

    static let choixTop = [3, 5, 10]
    static let choixDuMoment = [10, 20, 30]
    static let choixBandeau = [3, 5, 8]
    static let choixPropositions = NombrePropositions.choix

    init() {}

    var mesPlateformes: Bool {
        get { plateformes != nil }
        set { plateformes = newValue ? [] : nil }
    }

    var modifiees: Bool {
        self != SourcesAccueil()
    }

    enum CodingKeys: String, CodingKey {
        case plateformes, top10, tele, duMoment, nas, regardable, documentaires, nombreTop, nombreDuMoment, nombreBandeau, seriesTele
        case nombrePropositions
    }

    /// Les réglages d'une version précédente restent valables : ce qui a été ajouté depuis prend sa valeur par défaut.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plateformes = try c.decodeIfPresent([Int].self, forKey: .plateformes)
        top10 = try c.decodeIfPresent(Bool.self, forKey: .top10) ?? true
        tele = try c.decodeIfPresent(Bool.self, forKey: .tele) ?? true
        duMoment = try c.decodeIfPresent(Bool.self, forKey: .duMoment) ?? true
        nas = try c.decodeIfPresent(Bool.self, forKey: .nas) ?? true
        regardable = try c.decodeIfPresent(Bool.self, forKey: .regardable) ?? true
        documentaires = try c.decodeIfPresent(Bool.self, forKey: .documentaires) ?? true
        let top = try c.decodeIfPresent(Int.self, forKey: .nombreTop) ?? 5
        nombreTop = Self.choixTop.contains(top) ? top : 5
        let moment = try c.decodeIfPresent(Int.self, forKey: .nombreDuMoment) ?? 20
        nombreDuMoment = Self.choixDuMoment.contains(moment) ? moment : 20
        let bandeau = try c.decodeIfPresent(Int.self, forKey: .nombreBandeau) ?? 5
        nombreBandeau = Self.choixBandeau.contains(bandeau) ? bandeau : 5
        seriesTele = try c.decodeIfPresent(Bool.self, forKey: .seriesTele) ?? true
        let propositions = try c.decodeIfPresent(Int.self, forKey: .nombrePropositions) ?? 5
        nombrePropositions = Self.choixPropositions.contains(propositions) ? propositions : 5
    }
}

@MainActor
@Observable
final class AccueilModele {
    /// « Nouveautés » : sorties et nouveaux épisodes des trente derniers jours, les plus récents d'abord sur l'accueil (8.2.19).
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

    /// Les premiers de chaque type (3, 5 ou 10), avec affiche et en version regardable (EF-28), sur tes plateformes.
    func chargerTop(client: TMDBClient, plateformes: [Int]?, nombre: Int) async {
        async let films = client.decouvrirFilms(Self.surPlateformes(CriteresDecouverte.top(.film), plateformes))
        async let series = client.decouvrirSeries(Self.surPlateformes(CriteresDecouverte.top(.serie), plateformes))
        func premiers(_ titres: [TitreResume]) -> [TitreResume] {
            Array(Self.affichables(titres).prefix(nombre))
        }
        topFilms = premiers((try? await films.resultats.map(\.titreResume)) ?? [])
        topSeries = premiers((try? await series.resultats.map(\.titreResume)) ?? [])
    }

    /// « Nouveautés » (EF-01) : films et séries entrelacés, sur tes plateformes ; les 10, 20 ou 30 premiers.
    func charger(client: TMDBClient, plateformes: [Int]?, nombre: Int) async {
        erreur = nil
        do {
            async let films = client.decouvrirFilms(Self.surPlateformes(CriteresDecouverte.duMoment(.film), plateformes))
            async let series = client.decouvrirSeries(Self.surPlateformes(CriteresDecouverte.duMoment(.serie), plateformes))
            let listeFilms = Self.affichables(try await films.resultats.map(\.titreResume))
            let listeSeries = Self.affichables(try await series.resultats.map(\.titreResume))
            let titres = Array(Self.entrelacer(listeFilms, listeSeries).prefix(nombre))
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
    case documentaires
}

struct AccueilView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(filter: #Predicate<Abonnement> { $0.actif }, sort: \Abonnement.nom) private var abonnements: [Abonnement]
    /// Le guide à partir d'aujourd'hui : les passages d'hier ne servent plus à rien ici.
    @Query private var diffusions: [Diffusion]
    @AppStorage("accueil.sources") private var sourcesBrutes = Data()
    @Environment(\.horizontalSizeClass) private var classe
    /// Les fichiers du NAS : ce qui s'y trouve, et les vidéos entamées de la proposition du soir.
    @Query private var fichiersNAS: [FichierNAS]
    /// « Pas ce soir » (8.1) : le titre quitte la proposition jusqu'à demain matin.
    @AppStorage(PasCeSoir.cle) private var pasCeSoir = ""
    /// « Autre chose » : le rang de la proposition montrée.
    @State private var rang = 0
    /// Quand rien n'est à reprendre : des suggestions tirées de tes goûts, à la place de « Reprendre ».
    @State private var suggestions: [TitreResume] = []
    /// La largeur de la page : le panneau des nouveautés ne tient à droite de la proposition qu'à partir de 1000 points
    /// (l'iPad en paysage, le Mac) ; en dessous, elles passent en carrousel, comme sur l'iPhone.
    @State private var largeurPage: CGFloat = 0
    private var panneauADroite: Bool { classe == .regular && largeurPage >= 1000 }
    @State private var modele = AccueilModele()
    @State private var reglageSources = false
    @State private var chemin = NavigationPath()
    @Query(sort: \SelectionSoir.ajouteLe) private var selections: [SelectionSoir]
    /// Ce que tu veux voir ou es en train de regarder, les plus récents d'abord : l'accueil n'en montre qu'une poignée.
    @Query private var regardables: [Suivi]
    /// « Je n'aime pas », « ni VF ni sous-titres » : ces titres ne sont plus proposés, l'accueil compris.
    @Query private var refuses: [Suivi]
    /// Les rendez-vous de tes titres, sur huit jours : l'accueil résume ceux d'aujourd'hui, « À venir » les montre tous.
    @Query private var echeances: [Echeance]

    /// Les quatre requêtes ci-dessus sont bornées ici : sans cela, l'accueil relisait tout le guide TV, toutes
    /// les listes et toutes les échéances à chaque affichage, pour n'en montrer que quelques lignes.
    init() {
        let jour = Calendar.current.startOfDay(for: .now)
        let horizon = jour.addingTimeInterval(8 * 86_400)
        _diffusions = Query(filter: #Predicate<Diffusion> { $0.fin > jour }, sort: \Diffusion.debut)
        _echeances = Query(filter: #Predicate<Echeance> { $0.date >= jour && $0.date < horizon }, sort: \Echeance.date)
        // 8.2.11 : les titres déjà vus (terminés) non plus — « Reacher » revenait dans les Nouveautés.
        _refuses = Query(filter: #Predicate<Suivi> { $0.statutBrut == "exclu" || $0.exclusionLangue || $0.statutBrut == "termine" },
                         sort: \Suivi.ajouteLe)
        var candidats = FetchDescriptor<Suivi>(
            predicate: #Predicate { ($0.statutBrut == "aVoir" || $0.statutBrut == "enCours") && !$0.masque },
            sortBy: [SortDescriptor(\Suivi.ajouteLe, order: .reverse)]
        )
        candidats.fetchLimit = 40
        _regardables = Query(candidats)
    }

    /// « Je n'aime pas », « ni VF ni sous-titres » : ces titres ne sont plus proposés, l'accueil compris.
    private var ecartes: Set<ReferenceTitre> {
        Set(refuses.map(\.reference)).union(PasInteresse.references(pasInteresse))
    }

    /// « Pas intéressé pour l'instant » (8.2.11).
    @AppStorage(PasInteresse.cle) private var pasInteresse = ""
    /// « Pas ce genre » (8.7) : les genres écartés depuis la proposition, qui quittent tout l'accueil.
    @Query(filter: #Predicate<Interet> { $0.poids < 0 }) private var interetsNegatifs: [Interet]
    private var genresEcartes: Set<Int> { Set(interetsNegatifs.compactMap(\.genreID)) }
    /// Tes goûts, pour ranger le top de l'année dans la proposition (8.7).
    @State private var profil: ProfilGouts?

    private func proposables(_ titres: [TitreResume]) -> [TitreResume] {
        let ecartes = ecartes
        let genres = genresEcartes
        guard !ecartes.isEmpty || !genres.isEmpty else { return titres }
        return titres.filter { !ecartes.contains($0.reference) && genres.isDisjoint(with: $0.genres) }
    }

    /// 8.7 (demande de Patrick) : le top de l'année dans l'ordre de tes goûts — un genre que tu aimes remonte, un genre
    /// que tu évites descend ; la popularité départage.
    private func selonTesGouts(_ titres: [TitreResume]) -> [TitreResume] {
        guard let profil, !profil.estVide else { return titres }
        func score(_ titre: TitreResume, rang: Int) -> Double {
            let affinite = titre.genres.isEmpty ? 0 : titre.genres.map(profil.affinite(genre:)).reduce(0, +) / Double(titre.genres.count)
            return affinite - Double(rang) * 0.02
        }
        return titres.enumerated()
            .map { (titre: $0.element, score: score($0.element, rang: $0.offset)) }
            .sorted { $0.score > $1.score }
            .map(\.titre)
    }

    /// Ce que tu veux voir ou es en train de regarder : on demande pour chacun où il se regarde (réponse gardée 12 h).
    private var candidatsRegardables: [Suivi] { regardables }

    /// « Ce soir : Heat, Reacher », ou la prochaine soirée prévue ; rien quand aucune soirée n'est prévue.
    /// « Aujourd'hui » : ce qui sort ou passe ce jour pour tes titres, en quelques lignes ; le détail est dans Mes listes › À venir.
    @ViewBuilder
    private var aujourdhui: some View {
        let calendrier = Calendar.current
        var vues = Set<String>()
        let duJour = echeances.filter { calendrier.isDateInToday($0.date) && vues.insert("\($0.reference)|\($0.libelle)").inserted }
        if !duJour.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                TitreSection(titre: "Aujourd'hui") {
                    BoutonToutVoir {
                        etat.listeDemandee = .aVenir
                        etat.ongletDemande = .listes
                    }
                }
                Text(resumeDuJour(duJour)).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20)
                // Les mêmes grandes cartes que le reste de l'accueil : l'image, ce qui se passe en orange (« Sur M6 à 21:05 »,
                // « Nouvel épisode S02E04 »), le titre. La liste serrée de la 5.1 se lisait mal.
                DefilementHorizontal {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(Array(duJour.prefix(12).enumerated()), id: \.offset) { _, echeance in
                            NavigationLink(value: echeance.reference) {
                                CarteLargeTitre(reference: echeance.reference, titre: echeance.titre, cheminAffiche: echeance.cheminAffiche,
                                                accroche: echeance.libelle, ouApresAccroche: echeance.nature != .tele)
                                    .frame(width: CarteLargeTitre.largeur)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .task(id: duJour.map(\.reference)) { await etat.decors.charger(duJour.map(\.reference), client: etat.tmdb) }
            }
        }
    }

    /// « 3 rendez-vous aujourd'hui : 2 passages à la TV, 1 nouvel épisode ».
    private func resumeDuJour(_ echeances: [Echeance]) -> String {
        let tele = echeances.filter { $0.nature == .tele }.count
        let autres = echeances.count - tele
        let morceaux = [tele > 0 ? Format.pluriel(tele, "passage à la TV", "passages à la TV") : nil,
                        autres > 0 ? Format.pluriel(autres, "sortie ou épisode", "sorties ou épisodes") : nil].compactMap { $0 }
        return "Pour tes titres : " + morceaux.joined(separator: ", ")
    }

    private var sources: SourcesAccueil {
        (try? JSONDecoder().decode(SourcesAccueil.self, from: sourcesBrutes)) ?? SourcesAccueil()
    }

    /// « Seulement sur mes plateformes » : celles cochées dans Réglages › Plateformes ; aucune cochée, tout le catalogue.
    private var plateformes: [Int]? {
        guard sources.mesPlateformes, !abonnements.isEmpty else { return nil }
        return abonnements.map(\.providerID).sorted()
    }

    /// Ce qui oblige à relire TMDB quand il change.
    private struct CleChargement: Hashable {
        let plateformes: [Int]?
        let top: Int
        let duMoment: Int
    }

    private var cleChargement: CleChargement {
        CleChargement(plateformes: plateformes, top: sources.nombreTop, duMoment: sources.nombreDuMoment)
    }

    private func charger(_ client: TMDBClient) async {
        async let moment: Void = modele.charger(client: client, plateformes: plateformes, nombre: sources.nombreDuMoment)
        async let top: Void = modele.chargerTop(client: client, plateformes: plateformes, nombre: sources.nombreTop)
        _ = await (moment, top)
        if sources.documentaires {
            await etat.documentaires.charger(client: client, plateformes: plateformes)
        }
        // Les grandes cartes sont lourdes en image : les charger en avance évite la case grise au défilement.
        let titres = modele.duMoment + modele.topFilms + modele.topSeries
        CacheImages.partage.precharger(titres.compactMap { ImageTMDB.url($0.cheminFond ?? $0.cheminAffiche, .fond) })
    }

    var body: some View {
        NavigationStack(path: $chemin) {
            Group {
                if let client = etat.tmdb {
                    contenu
                        .task(id: cleChargement) { await charger(client) }
                        .refreshable { await charger(client) }
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
            .task(id: reprisesAccueil.isEmpty) {
                guard reprisesAccueil.isEmpty, suggestions.isEmpty else { return }
                await chargerSuggestions()
            }
            // Un genre écarté ou repris (8.7) : tes goûts changent, les suggestions aussi.
            .task(id: genresEcartes) {
                profil = try? ServiceGouts(contexte: contexte).profil()
                guard !suggestions.isEmpty else { return }
                await chargerSuggestions()
            }
            .task(id: candidatsRegardables.map(\.reference)) {
                guard sources.regardable else { return }
                for suivi in candidatsRegardables { etat.ou.demander(suivi.reference, client: etat.tmdb) }
            }
            .destinationsTitres()
            // « Voir la fiche » du menu d'un titre l'ouvre ici même (8.2.15).
            .environment(\.ouvrirFiche) { chemin.append($0) }
            .destinationsAccueil()
            // Charte 8.0 : en haut, le portrait et la roue seulement. Personnaliser l'accueil se fait dans
            // Réglages › Accueil.
            .sheet(isPresented: $reglageSources) {
                ReglageSourcesAccueil(sources: Binding {
                    sources
                } set: { nouvelles in
                    sourcesBrutes = (try? JSONEncoder().encode(nouvelles)) ?? Data()
                }, abonnements: abonnements)
            }
        }
        // Sur le Mac (8.2.13), les Préférences demandées par le menu s'ouvrent en page ici.
        .onChange(of: etat.preferencesEnPage) { _, _ in chemin.append(PagePreferences()) }
        .onChange(of: etat.reglagesEnPage) { _, _ in chemin.append(PageReglagesMac()) }
        .onChange(of: etat.ficheDemandee, initial: true) { _, reference in
            guard let reference else { return }
            chemin.append(reference)
            etat.ficheDemandee = nil
        }
    }

    private var contenu: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                let toutes = propositions
                let proposition = proposition
                if let proposition {
                    // 8.5 : les propositions en carrousel — on les fait glisser ; un toucher sur l'image ou le titre ouvre la fiche.
                    EnTeteAccueil(propositions: toutes,
                                  rang: Binding { toutes.isEmpty ? 0 : rang % toutes.count } set: { rang = $0 },
                                  nouveautes: panneauADroite && sources.duMoment ? Array(nouveautes(sauf: proposition.reference).prefix(3)) : [],
                                  ligneNouveaute: { modele.sousTitre($0) },
                                  voirFiche: { chemin.append($0) },
                                  toutesLesNouveautes: { chemin.append(DestinationAccueil.duMoment(plateformes: plateformes)) })
                } else {
                    // La place du portrait et de la roue, que la proposition recouvre d'ordinaire.
                    Color.clear.frame(height: 90)
                }

                if let erreur = modele.erreur {
                    MessageEtat(texte: erreur, ton: .probleme, libelleAction: "Réessayer") {
                        guard let client = etat.tmdb else { return }
                        Task { await charger(client) }
                    }
                }

                // Sur l'iPhone (maquette « Retenu · iPhone ») et l'iPad en portrait, les nouveautés en carrousel sous la
                // proposition ; sur un écran large, elles sont à sa droite.
                if !panneauADroite || proposition == nil, sources.duMoment {
                    let titres = nouveautes(sauf: proposition?.reference)
                    if !titres.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            TitreSection(titre: "Nouveautés") {
                                BoutonToutVoir { chemin.append(DestinationAccueil.duMoment(plateformes: plateformes)) }
                            }
                            Carrousel(titres: titres, numerote: true) { modele.sousTitre($0) }
                        }
                    }
                }

                SectionReprendre(sauf: proposition?.reference, suggestions: suggestions)

                // Tes souvenirs (8.1), comme sur l'Apple TV : les derniers albums de vidéos personnelles.
                SectionSouvenirs()

                aujourdhui

                if sources.regardable {
                    // Sur le NAS, sur tes plateformes ou à la TV ce soir : le badge « où regarder » le sait déjà.
                    let regardables = candidatsRegardables.filter { etat.ou.badge($0.reference) != nil }
                    if !regardables.isEmpty {
                        SectionRegardable(suivis: regardables)
                    }
                }

                if sources.top10, !modele.topFilms.isEmpty || !modele.topSeries.isEmpty {
                    SectionTop10(films: proposables(modele.topFilms), series: proposables(modele.topSeries), nombre: sources.nombreTop,
                                 plateformes: plateformes.map(nomsPlateformes))
                }

                if sources.tele {
                    SectionTele(diffusions: sources.seriesTele ? diffusions : diffusions.filter { $0.typeBrut == TypeTitre.film.rawValue },
                                lectureEnCours: etat.teleEnCours) {
                        // 7.0 : le programme a son entrée dans le menu.
                        etat.ongletDemande = .tele
                    }
                }

                if sources.documentaires, !etat.documentaires.films.isEmpty || !etat.documentaires.series.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        TitreSection(titre: "Documentaires") {
                            BoutonToutVoir { chemin.append(DestinationAccueil.documentaires) }
                        }
                        // 8.2.19 : les plus récents d'abord — 2026, puis 2025… Le NAS garde l'ordre de ses arrivées.
                        Carrousel(titres: proposables(etat.documentaires.films + etat.documentaires.series).recentsDAbord(\.date)) { _ in nil }
                    }
                }

                if sources.nas {
                    SectionNAS { etat.ongletDemande = .nas }
                }

            }
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(edges: .top)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { largeurPage = $0 }
        .overlay {
            if !modele.charge { ProgressView() }
        }
    }

    // MARK: La proposition du soir (8.1)

    /// Les vidéos du NAS entamées, la plus récente d'abord. Le Mac garde le lecteur d'Apple, sans reprise.
    private var reprisesAccueil: [(fichier: FichierNAS, position: PositionLecture)] {
        #if targetEnvironment(macCatalyst)
        return []
        #else
        return etat.nas.positions.enCours.prefix(10).compactMap { entree in
            fichiersNAS.first { $0.chemin == entree.chemin && $0.reference != nil }.map { ($0, entree.position) }
        }
        #endif
    }

    /// Ce que l'accueil peut proposer ce soir, dans l'ordre : la soirée prévue, les vidéos entamées, ta liste sur le
    /// NAS, puis le top de l'année — comme sur l'Apple TV. Les titres écartés, vus ou « pas ce soir » n'y sont pas.
    private var propositions: [PropositionSoir] {
        let ecartes = ecartes.union(PasCeSoir.references(pasCeSoir))
        let genresEcartes = genresEcartes
        let surLeNAS = Set(fichiersNAS.compactMap(\.reference))
        let reprises = reprisesAccueil
        let genresConnus = Dictionary(regardables.map { ($0.reference, $0.genres) }, uniquingKeysWith: { premier, _ in premier })
        var vues = Set<ReferenceTitre>()
        var liste: [PropositionSoir] = []
        /// Ce que tu as prévu ou commencé reste proposé ; le reste suit tes « Pas ce genre » (8.7).
        func ajouter(_ proposition: PropositionSoir, choisi: Bool = false) {
            var proposition = proposition
            if proposition.genres.isEmpty { proposition.genres = genresConnus[proposition.reference] ?? [] }
            guard !ecartes.contains(proposition.reference), choisi || genresEcartes.isDisjoint(with: proposition.genres),
                  vues.insert(proposition.reference).inserted else { return }
            liste.append(proposition)
        }
        func ligne(_ debut: String, _ reference: ReferenceTitre) -> String {
            let ou = surLeNAS.contains(reference) ? "Sur ton NAS"
                : etat.ou.badges(reference).first { if case .plateforme = $0 { true } else { false } }.map(BadgeOu.libelle)
            return [debut, ou].compactMap { $0 }.joined(separator: " · ")
        }
        let soiree = ServiceSoiree.soiree()
        for prevu in selections where prevu.soiree == soiree {
            ajouter(PropositionSoir(reference: prevu.reference, surtitre: ligne("Prévu ce soir", prevu.reference), titre: prevu.titre,
                                    detail: prevu.reference.type == .film ? "Film" : "Série",
                                    cheminFond: fichiersNAS.first { $0.reference == prevu.reference }?.cheminFond,
                                    cheminAffiche: prevu.cheminAffiche, reprise: reprises.first { $0.fichier.reference == prevu.reference }),
                    choisi: true)
        }
        for reprise in reprises {
            guard let reference = reprise.fichier.reference else { continue }
            ajouter(PropositionSoir(reference: reference,
                                    surtitre: ["Ce soir, pour toi", "Sur ton NAS", reprise.fichier.qualite].compactMap { $0 }.joined(separator: " · "),
                                    titre: reprise.fichier.titre,
                                    detail: LibellesProposition.reprise(film: reprise.fichier.type == .film, saison: reprise.fichier.saison,
                                                                        episode: reprise.fichier.episode, position: reprise.position),
                                    cheminFond: reprise.fichier.cheminFond, cheminAffiche: reprise.fichier.cheminAffiche, reprise: reprise),
                    choisi: true)
        }
        for suivi in regardables where surLeNAS.contains(suivi.reference) {
            let fichier = fichiersNAS.first { $0.reference == suivi.reference }
            ajouter(PropositionSoir(reference: suivi.reference,
                                    surtitre: ["Ce soir, pour toi", "Sur ton NAS", fichier?.qualite].compactMap { $0 }.joined(separator: " · "),
                                    titre: suivi.titre, detail: [suivi.type == .film ? "Film" : "Série", "dans ta liste"].joined(separator: " · "),
                                    cheminFond: fichier?.cheminFond, cheminAffiche: suivi.cheminAffiche, genres: suivi.genres))
        }
        // 8.5 : d'après tes goûts, avant le top de l'année.
        for titre in proposables(suggestions) {
            ajouter(PropositionSoir(reference: titre.reference, surtitre: ligne("D'après tes goûts", titre.reference), titre: titre.titre,
                                    detail: [titre.reference.type == .film ? "Film" : "Série", titre.date.map { String($0.annee) }]
                                        .compactMap { $0 }.joined(separator: " · "),
                                    cheminFond: titre.cheminFond, cheminAffiche: titre.cheminAffiche, genres: titre.genres))
        }
        for titre in selonTesGouts(proposables(Array(zip(modele.topFilms, modele.topSeries).flatMap { [$0, $1] }))) {
            ajouter(PropositionSoir(reference: titre.reference, surtitre: ligne("Ce soir, pour toi", titre.reference), titre: titre.titre,
                                    detail: [titre.reference.type == .film ? "Film" : "Série", titre.date.map { String($0.annee) }]
                                        .compactMap { $0 }.joined(separator: " · "),
                                    cheminFond: titre.cheminFond, cheminAffiche: titre.cheminAffiche, genres: titre.genres))
        }
        return Array(liste.prefix(sources.nombrePropositions))
    }

    /// La proposition montrée : « Autre chose » passe à la suivante, et revient à la première après la dernière.
    private var proposition: PropositionSoir? {
        let toutes = propositions
        return toutes.isEmpty ? nil : toutes[rang % toutes.count]
    }

    /// Les nouveautés, les plus récentes d'abord, sans les titres écartés ni celui de la proposition.
    /// 8.6 (demande de Patrick) : par popularité, l'ordre de TMDB, et numérotées de 1 à 10 comme sur Netflix.
    private func nouveautes(sauf reference: ReferenceTitre?) -> [TitreResume] {
        proposables(modele.duMoment).filter { $0.reference != reference }
    }

    /// Le même classement que « Suggestions pour ce soir » : ton profil de goûts, sans Claude, douze titres.
    private func chargerSuggestions() async {
        guard let tmdb = etat.tmdb else { return }
        let demande = DemandeCeSoir()
        let gouts = ServiceGouts(contexte: contexte)
        guard let profil = try? gouts.profil(), let exclusions = try? gouts.contexteCandidats(),
              let candidats = try? await CollecteurCandidats(client: tmdb).candidats(pour: demande, profil: profil, contexte: exclusions)
        else { return }
        suggestions = await ServiceRecommandation(claude: nil, nombre: 12)
            .suggerer(demande, candidats: candidats, profil: profil, nomsGenres: GenresParDefaut.noms).suggestions.map(\.candidat.titre)
    }

    private func nomsPlateformes(_ ids: [Int]) -> String {
        let noms = abonnements.filter { ids.contains($0.providerID) }.map(\.nom)
        return noms.count > 2 ? "\(noms.count) plateformes" : noms.joined(separator: " et ")
    }

}

/// Feuille « Sources » de l'accueil : plateformes affichées, télévision et NAS.
struct ReglageSourcesAccueil: View {
    @Binding var sources: SourcesAccueil
    let abonnements: [Abonnement]
    /// En page dans les Réglages (8.2.3), plutôt qu'en feuille.
    var enPage = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PileSiFeuille(enPage: enPage) {
            Form {
                // Les plateformes se cochent à un seul endroit, Réglages › Plateformes : ici, on choisit seulement de s'y limiter.
                Section {
                    Toggle("Seulement sur mes plateformes", isOn: $sources.mesPlateformes)
                        .tint(Theme.accent)
                        .disabled(abonnements.isEmpty)
                } header: {
                    Text("Catalogue")
                } footer: {
                    if abonnements.isEmpty {
                        Text("Coche d'abord tes abonnements dans Réglages › Plateformes : l'accueil montre tout le catalogue en attendant.")
                    } else if sources.mesPlateformes {
                        Text("Le bandeau, le Top et « Nouveautés » ne montrent que ce qui est disponible sur \(abonnements.map(\.nom).formatted(.list(type: .and).locale(Locale(identifier: "fr_CH")))). Tes plateformes se cochent dans Réglages › Plateformes.")
                    } else {
                        Text("L'accueil montre tout le catalogue ; le badge en coin d'affiche dit ce qui est sur tes plateformes.")
                    }
                }

                Section {
                    Toggle("Regardable ce soir, dans ta liste", isOn: $sources.regardable).tint(Theme.accent)
                    Toggle("Top de l'année", isOn: $sources.top10).tint(Theme.accent)
                    Toggle("Ce soir à la TV", isOn: $sources.tele).tint(Theme.accent)
                    Toggle("Nouveautés", isOn: $sources.duMoment).tint(Theme.accent)
                    Toggle("Documentaires", isOn: $sources.documentaires).tint(Theme.accent)
                    Toggle("Sur ton NAS", isOn: $sources.nas).tint(Theme.accent)
                } header: {
                    Text("Sections de l'accueil")
                } footer: {
                    Text("Les documentaires ont leurs propres thèmes : ils se choisissent sur la page Documentaires.")
                }

                Section {
                    choix("Propositions du soir", valeur: $sources.nombrePropositions, parmi: SourcesAccueil.choixPropositions)
                        // 8.6 : le nombre voyage à part, jusqu'à l'Apple TV qui ne lit pas ces réglages-là.
                        .onChange(of: sources.nombrePropositions) { _, nombre in
                            UserDefaults.standard.set(nombre, forKey: NombrePropositions.cle)
                        }
                    if sources.top10 {
                        choix("Top : films et séries, chacun", valeur: $sources.nombreTop, parmi: SourcesAccueil.choixTop)
                    }
                    if sources.duMoment {
                        choix("Nouveautés", valeur: $sources.nombreDuMoment, parmi: SourcesAccueil.choixDuMoment)
                    }
                    if sources.tele {
                        Toggle("Les séries aussi, à la TV", isOn: $sources.seriesTele).tint(Theme.accent)
                    }
                } header: {
                    Text("Combien de titres")
                } footer: {
                    Text("Moins de titres, c'est un accueil qui se lit d'un coup d'œil ; plus, c'est davantage de choix.")
                }

                if sources.modifiees {
                    Section {
                        Button("Revenir aux réglages d'origine") { sources = SourcesAccueil() }
                            .tint(Theme.accentClair)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.fond)
            .titre("Personnaliser l'accueil", enPage: enPage)
            .toolbar {
                if !enPage { ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                } }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.fond)
    }

    /// « Nouveautés   10 | 20 | 30 » : le libellé à gauche, les valeurs en segments à droite.
    private func choix(_ libelle: String, valeur: Binding<Int>, parmi valeurs: [Int]) -> some View {
        LabeledContent(libelle) {
            Picker(libelle, selection: valeur) {
                ForEach(valeurs, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 170)
        }
    }
}

/// « Dans ta liste, regardable ce soir » : les titres que tu voulais voir et qui sont sous la main, en affiches.
/// « Reprendre » (8.0) : les vidéos du NAS entamées ici ou sur un autre appareil, avec leur barre de progression.
/// Le ▶︎ repart là où l'on s'était arrêté.
private struct SectionReprendre: View {
    /// La vidéo que la proposition du soir montre déjà.
    var sauf: ReferenceTitre?
    /// Rien à reprendre (8.1) : des suggestions d'après tes goûts à la place.
    var suggestions: [TitreResume] = []

    @Environment(EtatApp.self) private var etat
    @Query private var fichiers: [FichierNAS]
    @AppStorage(PasCeSoir.cle) private var pasCeSoir = ""

    private var reprises: [(fichier: FichierNAS, position: PositionLecture)] {
        #if targetEnvironment(macCatalyst)
        return []
        #else
        return etat.nas.positions.enCours.prefix(10).compactMap { entree in
            fichiers.first { $0.chemin == entree.chemin && $0.reference != nil }.map { ($0, entree.position) }
        }
        .filter { $0.fichier.reference != sauf }
        #endif
    }

    var body: some View {
        let liste = reprises
        if liste.isEmpty {
            let ecartes = PasCeSoir.references(pasCeSoir)
            let idees = suggestions.filter { $0.reference != sauf && !ecartes.contains($0.reference) }
            if !idees.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    TitreSection("Suggestions")
                    Carrousel(titres: idees)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                TitreSection("Reprendre")
                DefilementHorizontal {
                    LazyHStack(spacing: 14) {
                        ForEach(liste, id: \.fichier.chemin) { reprise in
                            if let reference = reprise.fichier.reference {
                                NavigationLink(value: reference) {
                                    CarteLargeTitre(reference: reference, titre: reprise.fichier.titre, cheminFond: reprise.fichier.cheminFond,
                                                    cheminAffiche: reprise.fichier.cheminAffiche,
                                                    accroche: ["Sur ton NAS", reprise.position.appareil].compactMap { $0 }.joined(separator: " · "),
                                                    faits: reprise.position.reste.map { [PositionsLecture.reste($0)] } ?? [],
                                                    ouApresAccroche: false, progression: reprise.position.fraction)
                                        .frame(width: CarteLargeTitre.largeur)
                                }
                                .buttonStyle(.plain)
                                // Appui long (charte 8.0) : sortir un film de « Reprendre » sans le relancer.
                                .contextMenu {
                                    Button(role: .destructive) {
                                        withAnimation { etat.nas.oublierPosition(reprise.fichier.chemin) }
                                    } label: { Label("Retirer de Reprendre", systemImage: "xmark.circle") }
                                }
                                .accessibilityAction(named: "Retirer de Reprendre") { etat.nas.oublierPosition(reprise.fichier.chemin) }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
}

private struct SectionRegardable: View {
    let suivis: [Suivi]

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TitreSection("Regardable ce soir, dans ta liste")
                .task(id: suivis.map(\.reference)) {
                    await etat.decors.charger(suivis.map(\.reference), client: etat.tmdb)
                    CacheImages.partage.precharger(suivis.compactMap {
                        ImageTMDB.url(etat.decors.decor($0.reference)?.fond ?? $0.cheminAffiche, .fond)
                    })
                }
            Text("Sur ton NAS, sur tes plateformes ou à la TV ce soir")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            DefilementHorizontal {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(suivis) { suivi in
                        NavigationLink(value: suivi.reference) {
                            CarteLargeTitre(reference: suivi.reference, titre: suivi.titre, cheminAffiche: suivi.cheminAffiche,
                                            faits: suivi.note.map { ["★ \($0)/10"] } ?? [])
                                .frame(width: CarteLargeTitre.largeur)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                try? ServiceSoiree(contexte: contexte).retenir(suivi.reference, titre: suivi.titre, cheminAffiche: suivi.cheminAffiche)
                                etat.confirmer("« \(suivi.titre) » ajouté à ta soirée", symbole: "moon.stars.fill")
                            } label: { Label("Ajouter à ma soirée", systemImage: "moon.stars") }
                            Button {
                                etat.titreADater = TitreChoisi(reference: suivi.reference, titre: suivi.titre, cheminAffiche: suivi.cheminAffiche)
                            } label: { Label("Prévoir pour une soirée…", systemImage: "calendar") }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

private struct Carrousel: View {
    let titres: [TitreResume]
    /// Un grand chiffre à gauche des dix premières cartes (8.6, comme Netflix) : le classement par popularité.
    var numerote = false
    /// Ligne sous le titre à la place de l'année, par exemple la date de sortie.
    var sousTitre: (TitreResume) -> String? = { _ in nil }

    var body: some View {
        DefilementHorizontal {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(Array(titres.enumerated()), id: \.element.id) { index, titre in
                    NavigationLink(value: titre.reference) {
                        HStack(alignment: .bottom, spacing: -12) {
                            if numerote, index < 10 {
                                Text("\(index + 1)")
                                    .font(Theme.chiffreClassement)
                                    .foregroundStyle(Theme.fond)
                                    .shadow(color: Theme.texte2, radius: 0, x: 1.5, y: 1.5)
                                    .shadow(color: Theme.texte2, radius: 0, x: -1.5, y: -1.5)
                                    .offset(y: 14)
                                    .accessibilityHidden(true)
                            }
                            CarteLargeTitre(titre, accroche: sousTitre(titre)).frame(width: CarteLargeTitre.largeur)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(numerote && index < 10 ? "Numéro \(index + 1) : \(titre.titre)" : titre.titre)
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
    /// Films et séries du classement, chacun : 3, 5 ou 10.
    let nombre: Int
    /// « Sur Netflix et Prime Video » quand l'accueil est limité à tes plateformes.
    let plateformes: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TitreSection("Top \(nombre * 2) de l'année")
            Text("Les \(nombre) films et les \(nombre) séries les mieux notés sur TMDB depuis un an" + (plateformes.map { " · sur \($0)" } ?? ""))
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
                            .fill(Theme.trait)
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
            CarteLargeTitre(titre, accroche: "N° \(rang) des \(titre.reference.type == .film ? "films" : "séries")", rang: rang)
                .frame(width: CarteLargeTitre.largeur)
        }
        .buttonStyle(.plain)
        .actionsRapides(titre)
        .accessibilityLabel("Numéro \(rang) des \(titre.reference.type == .film ? "films" : "séries") : \(titre.titre)")
    }
}

/// Aperçu du NAS (8.2.17) : les derniers fichiers arrivés d'abord, d'après leur date sur le NAS (`DetailsNAS`) — et non
/// plus le dossier NEW puis les mieux notés.
private struct SectionNAS: View {
    let toutVoir: () -> Void
    @Query(filter: #Predicate<FichierNAS> { $0.tmdbID != nil }, sort: \FichierNAS.indexeLe, order: .reverse)
    private var fichiers: [FichierNAS]
    @State private var details = DetailsNAS()

    var body: some View {
        let apercu = Array(OeuvreNAS.regrouper(fichiers)
            .sorted { ($0.ajouteLe(details) ?? .distantPast) > ($1.ajouteLe(details) ?? .distantPast) }
            .prefix(15))
        if !apercu.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                // La seule porte vers la bibliothèque depuis l'accueil : le bouton NAS de la barre a été retiré.
                TitreSection(titre: "Sur ton NAS") {
                    BoutonToutVoir(action: toutVoir).accessibilityIdentifier("boutonNAS")
                }
                DefilementHorizontal {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(apercu) { oeuvre in
                            let carte = CarteLargeTitre(reference: oeuvre.reference, titre: oeuvre.titre, cheminFond: oeuvre.fichiers.first?.cheminFond,
                                                        cheminAffiche: oeuvre.cheminAffiche,
                                                        accroche: [oeuvre.nouveaute ? "Nouveau" : nil, oeuvre.qualite,
                                                                   oeuvre.fichiers.count > 1 ? "\(oeuvre.fichiers.count) fichiers" : nil].compactMap { $0 }.joined(separator: " · "),
                                                        faits: [oeuvre.annee.map(String.init), oeuvre.nombreVotes > 0 ? "\(Int((oeuvre.noteMoyenne * 10).rounded())) %" : nil].compactMap { $0 })
                                .frame(width: CarteLargeTitre.largeur)
                            if let reference = oeuvre.reference {
                                NavigationLink(value: reference) { carte }.buttonStyle(.plain)
                            } else {
                                carte
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .task(id: fichiers.count) {
                details = UserDefaults.standard.data(forKey: DetailsNAS.cle).flatMap(DetailsNAS.decoder) ?? DetailsNAS()
            }
        }
    }
}

/// UX-19 : grandes cartes de ce qui passe ce soir ; quand la soirée est vide ou passée,
/// les prochains films de la semaine. Les épisodes qui s'enchaînent ne font qu'une carte.
private struct SectionTele: View {
    let diffusions: [Diffusion]
    let lectureEnCours: Bool
    let toutVoir: () -> Void
    @Environment(EtatApp.self) private var etat
    @Query private var chaines: [Chaine]
    @Query private var suivis: [Suivi]

    /// EF-46 : ce qui commence entre 20 h et 23 h aujourd'hui et n'est pas terminé ; les films d'abord.
    private func ceSoir(_ blocs: [BlocDiffusion], maintenant: Date) -> [BlocDiffusion] {
        let jour = DateTMDB(maintenant)
        let debut = jour.instant(heure: 20)
        let fin = jour.instant(heure: 23)
        return blocs
            .filter { $0.debut >= debut && $0.debut <= fin && $0.fin > maintenant }
            .sorted { ($0.estFilm ? 0 : 1, $0.debut) < ($1.estFilm ? 0 : 1, $1.debut) }
    }

    /// Les séries passent tous les jours : la suite de la semaine ne montre que les films.
    private func prochainement(_ blocs: [BlocDiffusion], maintenant: Date) -> [BlocDiffusion] {
        Array(blocs.filter { $0.debut > maintenant && $0.estFilm }.prefix(12))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { horloge in
            section(maintenant: horloge.date)
        }
        .task { await etat.alertes.actualiserRappelsTele() }
    }

    private func section(maintenant: Date) -> some View {
        let blocs = GrilleTele.blocs(diffusions.filter { $0.fin > maintenant })
        let soir = ceSoir(blocs, maintenant: maintenant)
        let affichees = soir.isEmpty ? prochainement(blocs, maintenant: maintenant) : soir
        let marques = MarqueListe.marques(suivis)
        return VStack(alignment: .leading, spacing: 12) {
            TitreSection(titre: soir.isEmpty ? "Prochainement à la TV" : "Ce soir à la TV") {
                if lectureEnCours {
                    ProgressView().controlSize(.small)
                }
                if !diffusions.isEmpty {
                    BoutonToutVoir(action: toutVoir)
                }
            }
            if !affichees.isEmpty {
                Text(resume(affichees, ceSoir: !soir.isEmpty))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }
            if affichees.isEmpty {
                if lectureEnCours {
                    MessageEtat(texte: "Lecture des programmes de tes chaînes…", ton: .attente)
                } else {
                    MessageEtat(texte: "Aucun film reconnu sur tes chaînes pour l'instant. Choisis-les dans Réglages › TV.", symbole: "tv")
                }
            } else {
                DefilementHorizontal {
                    LazyHStack(spacing: 14) {
                        ForEach(affichees) { bloc in
                            CarteDiffusion(bloc: bloc, chaine: nomChaine(bloc.premiere.chaine), marque: bloc.reference.flatMap { marques[$0] },
                                           maintenant: maintenant, jourVisible: true)
                                .frame(width: 310)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    /// « 3 films et 2 séries sur tes chaînes, dès 20 h », « Les prochains films sur tes chaînes ».
    private func resume(_ blocs: [BlocDiffusion], ceSoir: Bool) -> String {
        guard ceSoir else { return "Les prochains films sur tes chaînes" }
        let films = blocs.filter(\.estFilm).count
        let series = blocs.count - films
        let morceaux = [films > 0 ? Format.pluriel(films, "film") : nil, series > 0 ? Format.pluriel(series, "série") : nil].compactMap { $0 }
        return morceaux.joined(separator: " et ") + " sur tes chaînes, dès 20 h"
    }

    private func nomChaine(_ identifiant: String) -> String {
        NomChaine.lire(identifiant, parmi: chaines)
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
