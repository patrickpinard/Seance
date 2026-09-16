import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

@MainActor
@Observable
final class AccueilModele {
    var tendancesJour: [TitreResume] = []
    var tendancesSemaine: [TitreResume] = []
    var nouveautes: [TitreResume] = []
    /// Nouveaux films et séries avec un épisode récent, du jour ou de la semaine.
    var nouveauxFilms: [TitreResume] = []
    var nouvellesSeries: [TitreResume] = []
    /// Pour chaque série : l'épisode diffusé dans la période, ou sa première diffusion.
    var datesSeries: [ReferenceTitre: String] = [:]
    var nouveautesChargees = false
    var erreur: String?
    var charge = false

    func chargerNouveautes(client: TMDBClient, periode: PeriodeTendance) async {
        async let films = client.decouvrirFilms(CriteresDecouverte.nouveautes(.film, periode: periode))
        async let series = client.decouvrirSeries(CriteresDecouverte.nouveautes(.serie, periode: periode))
        // Sans affiche, une carte ne dit rien ; hors français et anglais, pas de version regardable (EF-28).
        func retenir(_ titres: [TitreResume]) -> [TitreResume] {
            titres.filter { $0.cheminAffiche != nil && RegleLangue.accepte(langueOriginale: $0.langueOriginale, exclu: false) }
        }
        nouveauxFilms = retenir((try? await films.resultats.map(\.titreResume)) ?? [])
        let seriesRetenues = retenir((try? await series.resultats.map(\.titreResume)) ?? [])
        datesSeries = await Self.datesDesEpisodes(seriesRetenues, periode: periode, client: client)
        nouvellesSeries = seriesRetenues
        nouveautesChargees = true
    }

    /// `discover` ne dit pas quel épisode est sorti : la fiche de chaque série le donne.
    private static func datesDesEpisodes(_ series: [TitreResume], periode: PeriodeTendance, client: TMDBClient) async -> [ReferenceTitre: String] {
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

    /// EF-01, EF-28 : tendances, et nouveautés des 30 derniers jours sur les plateformes cochées.
    func charger(client: TMDBClient, abonnements: [Int]) async {
        erreur = nil
        do {
            var criteres = CriteresDecouverte()
            criteres.fournisseurs = abonnements
            criteres.monetisations = [.abonnement]
            criteres.sortieDepuis = DateTMDB(Date.now.addingTimeInterval(-30 * 86_400))
            criteres.genresInclus = [28]

            async let jour = client.tendances(.jour)
            async let semaine = client.tendances(.semaine)
            async let films: [TitreResume] = abonnements.isEmpty ? [] : client.decouvrirFilms(criteres).resultats.map(\.titreResume)

            tendancesJour = try await jour
            tendancesSemaine = try await semaine
            nouveautes = try await films.filter {
                RegleLangue.accepte(langueOriginale: $0.langueOriginale, exclu: false)
            }
        } catch {
            erreur = error.localizedDescription
        }
        charge = true
    }
}

/// Écrans ouverts depuis l'accueil, en plus des fiches.
enum DestinationAccueil: Hashable {
    case nas
}

struct AccueilView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(filter: #Predicate<Abonnement> { $0.actif }, sort: \Abonnement.nom) private var abonnements: [Abonnement]
    @Query(sort: \Diffusion.debut) private var diffusions: [Diffusion]
    @State private var modele = AccueilModele()
    @State private var semaine = false
    @State private var periodeNouveautes = PeriodeTendance.jour
    @State private var plateformeChoisie: Int?
    /// EF-62 : les tendances et les nouveautés reclassées selon les goûts, sans réseau ni Claude.
    @State private var pourToi: [SuggestionClassee] = []
    @State private var chemin = NavigationPath()

    var body: some View {
        NavigationStack(path: $chemin) {
            Group {
                if let client = etat.tmdb {
                    contenu
                        .task(id: plateformesRetenues) {
                            await modele.charger(client: client, abonnements: plateformesRetenues)
                            rafraichirPourToi()
                        }
                        .task(id: periodeNouveautes) {
                            await modele.chargerNouveautes(client: client, periode: periodeNouveautes)
                        }
                        .refreshable {
                            await modele.charger(client: client, abonnements: plateformesRetenues)
                            await modele.chargerNouveautes(client: client, periode: periodeNouveautes)
                            rafraichirPourToi()
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
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        chemin.append(DestinationAccueil.nas)
                    } label: {
                        Label("NAS", systemImage: "externaldrive.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityIdentifier("boutonNAS")
                }
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
            VStack(alignment: .leading, spacing: 26) {
                BandeauVedette(titres: Array(modele.tendancesSemaine.prefix(5)))

                if !abonnements.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            PuceFiltre(libelle: "Tout", active: plateformeChoisie == nil) { plateformeChoisie = nil }
                            ForEach(abonnements) { abonnement in
                                PuceFiltre(libelle: abonnement.nom, active: plateformeChoisie == abonnement.providerID) {
                                    plateformeChoisie = abonnement.providerID
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                if !pourToi.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        TitreSection(titre: "Pour toi") {
                            Text("d'après tes goûts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        CarrouselExplique(suggestions: pourToi)
                    }
                }

                SectionTele(diffusions: diffusions, lectureEnCours: etat.teleEnCours)

                SectionNouveautes(modele: modele, periode: $periodeNouveautes)

                SectionNAS { chemin.append(DestinationAccueil.nas) }

                VStack(alignment: .leading, spacing: 12) {
                    TitreSection(titre: "Tendances") {
                        Picker("Période", selection: $semaine) {
                            Text("Aujourd'hui").tag(false)
                            Text("Semaine").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }
                    Carrousel(titres: semaine ? modele.tendancesSemaine : modele.tendancesJour)
                }

                if !modele.nouveautes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        TitreSection("Action sur tes plateformes")
                        Carrousel(titres: modele.nouveautes)
                    }
                }

                if let erreur = modele.erreur {
                    Label(erreur, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(edges: .top)
        .overlay {
            if !modele.charge { ProgressView() }
        }
    }

    /// Le même classement que « Ce soir », appliqué à ce qui est déjà affiché : aucun appel
    /// supplémentaire à TMDB, et rien qui sorte de l'iPhone.
    private func rafraichirPourToi() {
        let gouts = ServiceGouts(contexte: contexte)
        guard let profil = try? gouts.profil(), !profil.estVide,
              let exclusions = try? gouts.contexteCandidats()
        else {
            pourToi = []
            return
        }
        var vues = Set<ReferenceTitre>()
        let candidats = (modele.nouveautes + modele.tendancesSemaine + modele.tendancesJour)
            .filter { vues.insert($0.reference).inserted }
            .filter { !exclusions.dejaVus.contains($0.reference) && !exclusions.exclus.contains($0.reference) }
            .filter { RegleLangue.accepte(langueOriginale: $0.langueOriginale, exclu: false) }
            .map { CandidatSuggestion(titre: $0) }
        pourToi = Array(ClassementLocal.classer(candidats, profil: profil, nomsGenres: etat.nomsGenres).prefix(12))
    }

    /// UX-18 : la puce choisie restreint les nouveautés à une plateforme.
    private var plateformesRetenues: [Int] {
        plateformeChoisie.map { [$0] } ?? abonnements.map(\.providerID)
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
                    Button("Tout voir", action: toutVoir)
                        .font(.subheadline.weight(.semibold))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TitreSection(titre: "Nouveautés") {
                Picker("Période", selection: $periode) {
                    Text("Aujourd'hui").tag(PeriodeTendance.jour)
                    Text("Semaine").tag(PeriodeTendance.semaine)
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
            }
            if modele.nouveautesChargees && modele.nouveauxFilms.isEmpty && modele.nouvellesSeries.isEmpty {
                Text(periode == .jour ? "Rien de neuf aujourd'hui : regarde la semaine." : "Aucune nouveauté cette semaine.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
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
            }
            if affichees.isEmpty {
                Text(lectureEnCours
                     ? "Lecture des programmes de tes chaînes…"
                     : "Aucun film reconnu sur tes chaînes. Choisis-les dans Moi › Télévision.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
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
