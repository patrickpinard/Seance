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
    /// Titres du bandeau : 3, 5 ou 8.
    var nombreBandeau = 5
    /// « Ce soir à la TV » montre aussi les séries ; sinon, seulement les films.
    var seriesTele = true

    static let choixTop = [3, 5, 10]
    static let choixDuMoment = [10, 20, 30]
    static let choixBandeau = [3, 5, 8]

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
    }
}

@MainActor
@Observable
final class AccueilModele {
    /// « Nouveautés » : sorties et nouveaux épisodes des trente derniers jours, les plus populaires d'abord.
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
    @AppStorage(Prenom.cle) private var prenomBrut = ""
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
        _refuses = Query(filter: #Predicate<Suivi> { $0.statutBrut == "exclu" || $0.exclusionLangue }, sort: \Suivi.ajouteLe)
        var candidats = FetchDescriptor<Suivi>(
            predicate: #Predicate { ($0.statutBrut == "aVoir" || $0.statutBrut == "enCours") && !$0.masque },
            sortBy: [SortDescriptor(\Suivi.ajouteLe, order: .reverse)]
        )
        candidats.fetchLimit = 40
        _regardables = Query(candidats)
    }

    /// « Je n'aime pas », « ni VF ni sous-titres » : ces titres ne sont plus proposés, l'accueil compris.
    private var ecartes: Set<ReferenceTitre> {
        Set(refuses.map(\.reference))
    }

    private func proposables(_ titres: [TitreResume]) -> [TitreResume] {
        let ecartes = ecartes
        return ecartes.isEmpty ? titres : titres.filter { !ecartes.contains($0.reference) }
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

    private var resumeSoiree: String? {
        let jour = ServiceSoiree.soiree()
        let ceSoir = selections.filter { $0.soiree == jour }.map(\.titre)
        if !ceSoir.isEmpty {
            return "Ce soir : " + ceSoir.prefix(2).joined(separator: ", ") + (ceSoir.count > 2 ? " et \(Format.pluriel(ceSoir.count - 2, "autre"))" : "")
        }
        if let passee = selections.filter({ $0.soiree < jour }).max(by: { $0.soiree < $1.soiree }) {
            return "\(passee.soiree == ServiceSoiree.soiree(Date.now.addingTimeInterval(-86_400)) ? "Hier soir" : "L'autre soir") : \(passee.titre) — regardé ?"
        }
        guard let prochaine = selections.filter({ $0.soiree > jour }).min(by: { $0.soiree < $1.soiree }) else { return nil }
        return "\(LibelleSoiree.soiree(prochaine.soiree)) : \(prochaine.titre)"
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
            .task(id: candidatsRegardables.map(\.reference)) {
                guard sources.regardable else { return }
                for suivi in candidatsRegardables { etat.ou.demander(suivi.reference, client: etat.tmdb) }
            }
            .destinationsTitres()
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
        .onChange(of: etat.ficheDemandee, initial: true) { _, reference in
            guard let reference else { return }
            chemin.append(reference)
            etat.ficheDemandee = nil
        }
    }

    private var contenu: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Les premiers du moment qui ont une image de fond : 3, 5 ou 8.
                BandeauVedette(titres: Array(proposables(modele.duMoment).filter { $0.cheminFond != nil }.prefix(sources.nombreBandeau)))

                if let erreur = modele.erreur {
                    MessageEtat(texte: erreur, ton: .probleme, libelleAction: "Réessayer") {
                        guard let client = etat.tmdb else { return }
                        Task { await charger(client) }
                    }
                }

                if let prenom = Prenom.lire(prenomBrut) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Prenom.salut(prenom))
                            .font(.title2.weight(.heavy))
                            .foregroundStyle(Theme.texte)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, -14)
                    .accessibilityElement(children: .combine)
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
                    .accessibilityHint("Ouvre Regarder")
                }

                SectionReprendre()

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

                if sources.duMoment, !modele.duMoment.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        TitreSection(titre: "Nouveautés") {
                            BoutonToutVoir { chemin.append(DestinationAccueil.duMoment(plateformes: plateformes)) }
                        }
                        Carrousel(titres: proposables(modele.duMoment)) { modele.sousTitre($0) }
                    }
                }

                if sources.documentaires, !etat.documentaires.films.isEmpty || !etat.documentaires.series.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        TitreSection(titre: "Documentaires") {
                            BoutonToutVoir { chemin.append(DestinationAccueil.documentaires) }
                        }
                        Carrousel(titres: proposables(etat.documentaires.films + etat.documentaires.series)) { _ in nil }
                    }
                }

                if sources.nas {
                    SectionNAS { etat.ongletDemande = .nas }
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
                    choix("Bandeau du haut", valeur: $sources.nombreBandeau, parmi: SourcesAccueil.choixBandeau)
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
    @Environment(EtatApp.self) private var etat
    @Query private var fichiers: [FichierNAS]

    private var reprises: [(fichier: FichierNAS, position: PositionLecture)] {
        #if targetEnvironment(macCatalyst)
        return []
        #else
        return etat.nas.positions.enCours.prefix(10).compactMap { entree in
            fichiers.first { $0.chemin == entree.chemin && $0.reference != nil }.map { ($0, entree.position) }
        }
        #endif
    }

    var body: some View {
        let liste = reprises
        if !liste.isEmpty {
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
                                .font(.largeTitle.weight(.heavy))
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
                        CarteLargeTitre(titre, accroche: sousTitre(titre)).frame(width: CarteLargeTitre.largeur)
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
