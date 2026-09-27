import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Ce qui te concerne, en images : tes dernières notes, tes acteurs favoris et suivis, tes goûts. Les chiffres ne sont
/// pas mis en avant : une entrée en bas de page ouvre les statistiques, qui les réunissent tous.
/// Sur l'iPhone, l'engrenage ouvre Réglages, qui n'a pas d'onglet à lui.
enum DestinationProfil: Hashable {
    case acteursSuivis, statistiques
}

struct ProfilView: View {
    /// 7.0 : ouvertes par le portrait, en feuille, et non plus comme un onglet.
    var enFeuille = false
    /// Sur le Mac (8.2.13), une page poussée dans la pile où l'on est — une feuille y devient une fenêtre à part.
    var enPage = false
    @Environment(EtatApp.self) private var etat
    @Environment(\.dismiss) private var fermer
    @Environment(\.horizontalSizeClass) private var classeTaille
    @Environment(\.modelContext) private var contexte
    @Query private var interets: [Interet]
    @Query(sort: \Suivi.ajouteLe, order: .reverse) private var suivis: [Suivi]
    @Query private var visionnages: [Visionnage]
    @Query private var acteursSuivis: [ActeurSuivi]
    @AppStorage(Prenom.cle) private var prenom = ""
    @State private var gouts = false
    /// La rubrique « Tes goûts », repliée au départ.
    @State private var goutsOuverts = false
    /// Les réalisateurs des films vus, gardés sur l'appareil (8.2.11).
    @State private var reserveRealisateurs = ReserveRealisateurs(donnees: UserDefaults.standard.data(forKey: ReserveRealisateurs.cle))
    @State private var chargementRealisateurs = false
    @State private var quiRegarde = false
    /// Le classement des acteurs parcourt tous les visionnages et leurs castings : calculé une fois, puis seulement
    /// quand ce qu'il compte a changé, pas à chaque rendu de la page.
    @State private var favoris: [Classement<ActeurStat>] = []
    /// Portraits des acteurs favoris, lus une fois sur TMDB puis gardés (les acteurs suivis ont déjà le leur).
    @State private var portraits: [String: String] = (UserDefaults.standard.dictionary(forKey: "profil.portraits") as? [String: String]) ?? [:]

    private var notes: [Suivi] {
        Array(suivis.filter { $0.note != nil }.prefix(12))
    }

    var body: some View {
        PileSiFeuille(enPage: enPage) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    entete
                    dernieresNotes
                    acteurs
                    realisateurs
                    // Les alertes reçues (8.2.11), pour les revoir après les avoir balayées de l'écran verrouillé.
                    NavigationLink(value: DestinationReglage.alertesRecues) {
                        LigneReglage(titre: "Alertes reçues", symbole: "bell.badge", valeur: "Les revoir, les effacer")
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    sectionGouts
                    // Les chiffres ne s'imposent pas : une seule entrée, en bas, vers la page qui les réunit tous.
                    statistiques
                }
                .padding(.vertical, 16)
                // Toute la largeur, comme les autres pages : bornée à 1180 points, elle laissait deux bandes vides sur le Mac.
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.fond)
            .navigationTitle("Préférences")
            .boutonBarreLaterale(preferences: false, reglages: false)
            .toolbar {
                if enFeuille {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("OK") { fermer() }
                    }
                }
                // Changer de personne (7.0) : le bonhomme du haut ouvre maintenant les Préférences, le choix est ici.
                if ProfilsFamille().aPlusieursProfils {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { quiRegarde = true } label: {
                            Label("Changer de personne", systemImage: "person.2")
                        }
                        .accessibilityIdentifier("quiRegarde")
                    }
                }
                // Sur l'iPhone, Réglages n'a pas d'onglet à lui : l'engrenage l'ouvre.
                if classeTaille == .compact {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: DestinationReglage.reglages) {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Réglages")
                    }
                }
            }
            .task(id: cleFavoris) {
                favoris = acteursFavoris()
                await chargerPortraits()
            }
            .destinationsTitres()
            .navigationDestination(for: DestinationProfil.self) { destination in
                switch destination {
                case .acteursSuivis: ActeursSuivisView()
                case .statistiques: StatistiquesView()
                }
            }
            .navigationDestination(for: TitresAvecActeur.self) { comptes in
                PersonneView(personne: comptes.personne, comptes: comptes)
            }
            .fullScreenCover(isPresented: $quiRegarde) {
                QuiRegardeView { profil in
                    quiRegarde = false
                    // Le choix fait, retour à la page : même si c'est la même personne, les Préférences se referment.
                    etat.preferencesOuvertes = false
                    ConteneurApp.changerDeProfil(vers: profil)
                }
            }
            .sheet(isPresented: $gouts) {
                BienvenueView(mode: .gouts) { gouts = false }
            }
        }
    }

    // MARK: Les sections

    private var entete: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Prenom.salut(Prenom.lire(prenom)))
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(Theme.texte)
            Text("Tes notes, tes acteurs et tes goûts : ce qui guide les suggestions de Séance.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var dernieresNotes: some View {
        VStack(alignment: .leading, spacing: 10) {
            TitreSection("Tes dernières notes")
                .task(id: notes.map(\.reference)) { await etat.decors.charger(notes.map(\.reference), client: etat.tmdb) }
            if notes.isEmpty {
                Text("Note un film ou une série depuis sa fiche : tes notes affinent ce que Séance te propose.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            } else {
                DefilementHorizontal {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(notes) { suivi in
                            NavigationLink(value: suivi.reference) {
                                // Le même format large que le reste de l'app (5.1) : l'image, ta note en ligne orange, où le revoir.
                                CarteLargeTitre(reference: suivi.reference, titre: suivi.titre, cheminAffiche: suivi.cheminAffiche,
                                                accroche: "★ \(suivi.note ?? 0)/10 · ta note")
                                    .frame(width: CarteLargeTitre.largeur)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(suivi.titre), noté \(suivi.note ?? 0) sur 10")
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private var acteurs: some View {
        VStack(alignment: .leading, spacing: 10) {
            TitreSection(titre: "Tes acteurs") {
                NavigationLink(value: DestinationProfil.acteursSuivis) {
                    Text(acteursSuivis.isEmpty ? "Acteurs suivis" : Format.pluriel(acteursSuivis.count, "suivi"))
                        .font(.subheadline.weight(.semibold))
                        .zoneDeToucher()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accentClair)
            }
            if favoris.isEmpty, acteursSuivis.isEmpty {
                Text("Ceux que tu regardes le plus apparaîtront ici. Suis un acteur depuis sa fiche : Séance te prévient de ses nouveaux films.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            } else {
                DefilementHorizontal {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(favoris, id: \.cle) { acteur in
                            let suivi = acteursSuivis.first { $0.personneID == acteur.cle.id }
                            portrait(nom: acteur.cle.nom, id: acteur.cle.id, detail: Format.pluriel(acteur.nombreTitres, "titre"),
                                     chemin: suivi?.cheminPortrait ?? acteur.cle.id.flatMap { portraits[String($0)] },
                                     suivi: suivi != nil, titres: acteur.titres)
                        }
                        // Les acteurs suivis qui ne sont pas encore des favoris.
                        ForEach(acteursSuivis.filter { suivi in !favoris.contains { $0.cle.id == suivi.personneID } }) { acteur in
                            portrait(nom: acteur.nom, id: acteur.personneID, detail: "Suivi", chemin: acteur.cheminPortrait, suivi: true, titres: [])
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    // MARK: Tes réalisateurs (8.2.11)

    /// Les films vus, par leur identifiant TMDB.
    private var filmsVus: Set<Int> {
        Set(visionnages.filter { $0.typeBrut == TypeTitre.film.rawValue }.map(\.tmdbID))
    }

    /// Ceux dont tu as vu au moins deux films, comme les acteurs ; chacun ouvre sa fiche avec tes films de lui.
    @ViewBuilder
    private var realisateurs: some View {
        let classement = reserveRealisateurs.classement(filmsVus: filmsVus)
        VStack(alignment: .leading, spacing: 10) {
            TitreSection("Tes réalisateurs")
            if classement.isEmpty {
                Text(chargementRealisateurs ? "Séance cherche les réalisateurs de tes films…"
                                            : "Ceux dont tu as vu au moins deux films apparaîtront ici.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            } else {
                DefilementHorizontal {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(classement, id: \.realisateur.id) { classe in
                            portrait(nom: classe.realisateur.nom, id: classe.realisateur.id,
                                     detail: Format.pluriel(classe.films.count, "film"),
                                     chemin: classe.realisateur.cheminPortrait, suivi: false,
                                     titres: classe.films.map { ReferenceTitre(type: .film, tmdbID: $0) })
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .task(id: filmsVus.count) { await chargerRealisateurs() }
    }

    /// Les réalisateurs des films vus qu'on ne connaît pas encore : lus sur TMDB, trente films à la fois, puis gardés.
    private func chargerRealisateurs() async {
        guard let tmdb = etat.tmdb else { return }
        let manquants = Array(reserveRealisateurs.manquants(Array(filmsVus)).prefix(30))
        guard !manquants.isEmpty else { return }
        chargementRealisateurs = true
        defer { chargementRealisateurs = false }
        let lus = await withTaskGroup(of: (Int, [ReserveRealisateurs.Realisateur]?).self) { groupe in
            for id in manquants {
                groupe.addTask {
                    guard let fiche = try? await tmdb.film(id, complements: [.casting]) else { return (id, nil) }
                    return (id, (fiche.casting?.realisateurs ?? []).map {
                        ReserveRealisateurs.Realisateur(id: $0.id, nom: $0.nom, cheminPortrait: $0.cheminPortrait)
                    })
                }
            }
            var resultat: [Int: [ReserveRealisateurs.Realisateur]] = [:]
            for await (id, realisateurs) in groupe {
                if let realisateurs { resultat[id] = realisateurs }
            }
            return resultat
        }
        guard !Task.isCancelled else { return }
        var reserve = reserveRealisateurs
        reserve.parFilm.merge(lus) { _, nouveau in nouveau }
        reserveRealisateurs = reserve
        UserDefaults.standard.set(reserve.encoder(), forKey: ReserveRealisateurs.cle)
    }

    @ViewBuilder
    private func portrait(nom: String, id: Int?, detail: String, chemin: String?, suivi: Bool, titres: [ReferenceTitre]) -> some View {
        let contenu = VStack(spacing: 6) {
            ImageDistante(url: ImageTMDB.url(chemin, .portrait), coins: 38, symboleVide: "person.fill")
                .frame(width: 76, height: 76)
                .overlay(alignment: .bottomTrailing) {
                    if suivi {
                        Image(systemName: "bell.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(5)
                            .background(Theme.degradeAccent, in: Circle())
                    }
                }
            Text(nom)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 88)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(nom), \(detail)\(suivi ? ", suivi" : "")")
        .accessibilityAddTraits(.isButton)

        if let id {
            // Un favori ouvre sa fiche avec tes titres où il joue ; un acteur seulement suivi, sa fiche.
            if titres.isEmpty {
                NavigationLink(value: ReferencePersonne(id: id, nom: nom)) { contenu }.buttonStyle(.plain)
            } else {
                NavigationLink(value: TitresAvecActeur(personne: ReferencePersonne(id: id, nom: nom), periode: "depuis le début", titres: titres)) {
                    contenu
                }
                .buttonStyle(.plain)
            }
        } else {
            contenu
        }
    }

    /// Tes goûts (8.2.12, demande de Patrick) : une rubrique qui se replie. Fermée, le nombre de genres et leurs noms ;
    /// ouverte, tous les genres avec une case à cocher — la longue rangée de pastilles prenait toute la page.
    private var sectionGouts: some View {
        let choisis = Set(interets.map(\.libelle))
        return VStack(alignment: .leading, spacing: 10) {
            EnTeteRepliable(titre: "Tes goûts", detail: choisis.isEmpty ? "À choisir" : Format.pluriel(choisis.count, "genre"),
                            ouverte: goutsOuverts) { goutsOuverts.toggle() }
                .padding(.horizontal, 20)
            if !goutsOuverts, !choisis.isEmpty {
                Text(choisis.sorted().joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 20)
            }
            if goutsOuverts {
                VStack(spacing: 0) {
                    ForEach(Array(GoutPropose.catalogue.enumerated()), id: \.element.nom) { rang, gout in
                        if rang > 0 { Divider().padding(.leading, 52) }
                        let coche = choisis.contains(gout.nom)
                        Button { basculer(gout, choisis: choisis) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: coche ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(coche ? Theme.accent : Theme.texte3)
                                    .frame(width: 28)
                                Text(gout.nom).foregroundStyle(Theme.texte)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 46)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(coche ? .isSelected : [])
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.trait))
                .padding(.horizontal, 20)
                .transition(.opacity)
                Button { gouts = true } label: {
                    Label("Noter des films connus", systemImage: "star")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
            }
        }
    }

    /// Coche ou décoche un genre : les intérêts déclarés sont réécrits d'après les cases.
    private func basculer(_ gout: GoutPropose, choisis: Set<String>) {
        var noms = choisis
        if noms.contains(gout.nom) { noms.remove(gout.nom) } else { noms.insert(gout.nom) }
        let interets = GoutPropose.catalogue.filter { noms.contains($0.nom) }
            .map { ServiceGouts.InteretDeclare(libelle: $0.nom, genres: $0.genres, motsCles: $0.motsCles) }
        try? ServiceGouts(contexte: contexte).declarer(interets)
    }

    private var statistiques: some View {
        NavigationLink(value: DestinationProfil.statistiques) {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Theme.degradeAccent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tes statistiques").font(.subheadline.weight(.semibold))
                    Text("Ta collection, tes heures, tes acteurs et genres favoris, ton année en cartes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    // MARK: Données

    /// Les acteurs les plus regardés depuis le début, comptés comme dans les statistiques ;
    /// un acteur vu dans un seul titre n'est pas encore un favori.
    private func acteursFavoris() -> [Classement<ActeurStat>] {
        Array(((try? ServiceStatistiques(contexte: contexte).bilan(annee: nil).acteurs) ?? []).filter { $0.nombreTitres >= 2 }.prefix(10))
    }

    /// Ce dont dépend le classement : les visionnages comptés (pas les « déjà vus avant ») et les suivis, qui portent les castings.
    private var cleFavoris: [Int] {
        [visionnages.count, visionnages.filter(\.anterieur).count, suivis.count]
    }

    /// Le portrait d'un favori n'est écrit nulle part : lu une fois sur TMDB, puis gardé.
    private func chargerPortraits() async {
        guard let tmdb = etat.tmdb else { return }
        let suivisIDs = Set(acteursSuivis.map(\.personneID))
        let manquants = favoris.compactMap(\.cle.id).filter { portraits[String($0)] == nil && !suivisIDs.contains($0) }
        guard !manquants.isEmpty else { return }
        var trouves = portraits
        for id in manquants.prefix(10) {
            if let chemin = try? await tmdb.personne(id).cheminPortrait { trouves[String(id)] = chemin }
        }
        portraits = trouves
        UserDefaults.standard.set(trouves, forKey: "profil.portraits")
    }
}

/// Les acteurs suivis : chacun ouvre sa fiche ; glisser pour ne plus le suivre.
struct ActeursSuivisView: View {
    @Environment(\.modelContext) private var contexte
    @Query(sort: \ActeurSuivi.nom) private var acteurs: [ActeurSuivi]

    var body: some View {
        List {
            if !acteurs.isEmpty {
                BandeauAlertesCoupees()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            if acteurs.isEmpty {
                ContentUnavailableView("Aucun acteur suivi", systemImage: "person.2",
                                       description: Text("Sur la fiche d'un acteur, touche la cloche pour être prévenu de ses nouveaux films."))
                    .listRowBackground(Color.clear)
            }
            ForEach(acteurs) { acteur in
                NavigationLink(value: ReferencePersonne(id: acteur.personneID, nom: acteur.nom)) {
                    HStack(spacing: 12) {
                        ImageDistante(url: ImageTMDB.url(acteur.cheminPortrait, .portrait), coins: 22, symboleVide: "person.fill")
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(acteur.nom)
                            Text("Suivi depuis le \(acteur.suiviLe.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "fr_CH"))))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions {
                    Button("Ne plus suivre", role: .destructive) {
                        try? ServiceActeurs(contexte: contexte).nePlusSuivre(acteur.personneID)
                    }
                }
                // Le Mac n'a pas de glissement : clic droit.
                .contextMenu {
                    Button(role: .destructive) {
                        try? ServiceActeurs(contexte: contexte).nePlusSuivre(acteur.personneID)
                    } label: { Label("Ne plus suivre", systemImage: "bell.slash") }
                }
            }
        }
        .pageReglages("Acteurs suivis")
    }
}
