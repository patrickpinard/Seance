import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// L'accueil de la TV (maquette « Retenu · Apple TV », 27.09.2026) : une proposition pour ce soir en grand, les
/// nouveautés à côté, puis « Reprendre » et le reste des étagères.
struct AccueilTV: View {
    @Environment(EtatTV.self) private var etat
    @Environment(\.openURL) private var ouvrir
    @Environment(\.modelContext) private var contexte
    @Query(sort: \SelectionSoir.ajouteLe) private var soirees: [SelectionSoir]
    @Query(sort: \FichierNAS.indexeLe, order: .reverse) private var fichiers: [FichierNAS]
    @Query private var suivis: [Suivi]
    /// Seulement ce qui n'est pas encore fini (8.10) : la requête relisait tout le guide à chaque rendu.
    @Query private var diffusions: [Diffusion]
    @Query private var chaines: [Chaine]
    /// Le dernier chargement de TMDB : l'accueil ne le refait pas à chaque retour sur la page (8.10).
    @State private var chargeLe: Date?

    @State private var duMoment: [ApercuTV] = []
    /// Déjà vus, refusés ou « pas intéressé pour l'instant » (8.2.15) : comme sur l'iPhone, plus proposés ici.
    @Query(filter: #Predicate<Suivi> { $0.statutBrut == "exclu" || $0.exclusionLangue || $0.statutBrut == "termine" })
    private var suivisEcartes: [Suivi]
    @AppStorage(PasInteresse.cle) private var pasInteresse = ""
    /// « Pas ce soir » : le titre quitte la proposition jusqu'à demain matin.
    @AppStorage(PasCeSoir.cle) private var pasCeSoir = ""
    /// « Autre chose » : le rang de la proposition montrée parmi celles de ce soir.
    @State private var rang = 0
    /// Le bouton de la proposition qui a le focus (8.6) : gauche sur « Lecture », droite sur « Plus d'infos » font défiler.
    @FocusState private var boutonHero: BoutonHero?
    /// Le sens du dernier défilement, pour que l'image glisse du bon côté.
    @State private var versLaDroite = true
    @State private var dernierDefilement = Date.distantPast
    private enum BoutonHero: Hashable { case lecture, infos }
    /// Combien de propositions défilent (8.6) : le réglage des Préférences de l'iPhone, reçu par la synchronisation.
    @AppStorage(NombrePropositions.cle) private var nombrePropositions = NombrePropositions.parDefaut
    /// Quand rien n'est à reprendre : des suggestions tirées de tes goûts (le classement local du panneau « Suggestions
    /// pour ce soir »), à la place de l'étagère.
    @State private var suggestions: [SuggestionClassee] = []
    private var ecartes: Set<ReferenceTitre> { Set(suivisEcartes.map(\.reference)).union(PasInteresse.references(pasInteresse)) }
    /// « Pas ce genre » (8.7), comme sur l'iPhone : ces genres quittent tout l'accueil.
    @Query(filter: #Predicate<Interet> { $0.poids < 0 }) private var interetsNegatifs: [Interet]
    private var genresEcartes: Set<Int> { Set(interetsNegatifs.compactMap(\.genreID)) }
    /// Tes goûts, pour ranger le top de l'année dans la proposition (8.7).
    @State private var profil: ProfilGouts?
    @State private var top: [ApercuTV] = []
    @State private var configuration = false
    /// Images de fond des titres de la soirée, lues sur TMDB quand le NAS ne les connaît pas.
    @State private var fonds: [ReferenceTitre: String] = [:]

    init() {
        let maintenant = Date.now
        _diffusions = Query(filter: #Predicate<Diffusion> { $0.fin > maintenant }, sort: \Diffusion.debut)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 50) {
                if etat.tmdb == nil {
                    VStack(spacing: 10) {
                        VideTV(symbole: "iphone.and.arrow.forward", titre: "Séance n'est pas encore configurée sur cette TV",
                               message: "Le plus simple : envoie tout depuis ton iPhone — la clé TMDB, ton NAS et tes listes — avec un code à six chiffres.")
                            .padding(.bottom, -90)
                        Button { configuration = true } label: { Label("Configurer depuis mon iPhone", systemImage: "iphone.and.arrow.forward") }
                            .buttonStyle(BoutonTV(principal: true))
                    }
                    .frame(maxWidth: .infinity)
                }
                // 8.9 : les propositions calculées une fois par rendu, et non à chaque usage (bilan de l'Apple TV).
                let toutes = propositions
                let proposition = toutes.isEmpty ? nil : toutes[rang % toutes.count]
                if let proposition { enTete(proposition, toutes: toutes) } else { Color.clear.frame(height: 40) }
                // « Reprendre » sous la proposition — les vidéos du NAS entamées ici ou sur un autre appareil, sauf celle
                // que la proposition montre déjà.
                let reprises = aReprendre.filter { $0.reference != proposition?.reference }
                if !reprises.isEmpty {
                    EtagereTV(titre: "Reprendre", sousTitre: "Là où tu t'es arrêté, ici ou sur un autre appareil") {
                        ForEach(reprises, id: \.fichier.chemin) { reprise in
                            NavigationLink(value: reprise.reference) {
                                CarteLargeTV(surtitre: reprise.position.appareil.map { "Sur ton NAS · \($0)" } ?? "Sur ton NAS",
                                             titre: reprise.fichier.titre,
                                             detail: reprise.position.reste.map { PositionsLecture.reste($0) },
                                             cheminImage: reprise.fichier.cheminFond ?? reprise.fichier.cheminAffiche,
                                             largeur: CarteLargeTV.largeurGrille, progression: reprise.position.fraction)
                            }
                            .buttonStyle(.card)
                            .menuCarteTV(reprise.reference, titre: reprise.fichier.titre, cheminAffiche: reprise.fichier.cheminAffiche,
                                         reprise: reprise.fichier.chemin)
                        }
                    }
                } else if case let idees = suggestionsAMontrer(sauf: proposition?.reference), !idees.isEmpty {
                    EtagereTV(titre: "Suggestions", sousTitre: "D'après tes goûts, pour ce soir") {
                        ForEach(idees) { idee in
                            let titre = idee.candidat.titre
                            NavigationLink(value: titre.reference) {
                                CarteLargeTV(surtitre: nil, titre: titre.titre,
                                             detail: [titre.reference.type == .film ? "Film" : "Série", titre.date.map { String($0.annee) }]
                                                .compactMap { $0 }.joined(separator: " · "),
                                             cheminImage: titre.cheminFond ?? titre.cheminAffiche, largeur: CarteLargeTV.largeurGrille,
                                             reference: titre.reference)
                            }
                            .buttonStyle(.card)
                            .menuCarteTV(titre.reference, titre: titre.titre, cheminAffiche: titre.cheminAffiche)
                        }
                    }
                }
                // Nouveautés (8.6) : en étagère sous « Reprendre », comme Tes souvenirs et le NAS — l'image de la
                // proposition garde toute la largeur.
                let nouveautes = nouveautes(sauf: proposition?.reference)
                if !nouveautes.isEmpty {
                    EtagereTV(titre: "Nouveautés", sousTitre: "Sorties et nouveaux épisodes sur tes plateformes, les plus populaires d'abord",
                              toutVoir: { etat.demandeRegarder = .streaming }) {
                        ForEach(Array(nouveautes.enumerated()), id: \.element.id) { index, apercu in
                            // Le classement par popularité, en grand chiffre à côté de la carte (8.6, comme Netflix) —
                            // hors du bouton, pour que le cadre du focus n'entoure que la carte.
                            HStack(alignment: .bottom, spacing: -18) {
                                if index < 10 {
                                    Text("\(index + 1)")
                                        .font(Theme.chiffreClassementTV)
                                        .foregroundStyle(Theme.fond)
                                        .shadow(color: Theme.texte2, radius: 0, x: 3, y: 3)
                                        .shadow(color: Theme.texte2, radius: 0, x: -3, y: -3)
                                        .offset(y: 34)
                                        .accessibilityHidden(true)
                                }
                                NavigationLink(value: apercu.reference) {
                                    CarteLargeTV(surtitre: origine(apercu.reference), titre: apercu.titre, detail: apercu.sousTitre,
                                                 cheminImage: apercu.cheminFond ?? apercu.cheminAffiche, marque: marque(apercu.reference),
                                                 largeur: CarteLargeTV.largeurGrille, reference: apercu.reference)
                                }
                                .buttonStyle(.card)
                                .menuCarteTV(apercu.reference, titre: apercu.titre, cheminAffiche: apercu.cheminAffiche)
                                .task(id: apercu.reference) { etat.ou.demander(apercu.reference, client: etat.tmdb) }
                            }
                        }
                    }
                }
                // Tes souvenirs (8.1) : les derniers albums de vidéos personnelles, à deux clics.
                RangeeSouvenirsTV()
                // 8.10 : chaque étagère calculée une fois par rendu (elles l'étaient deux fois).
                let nouveautesNAS = nouveautesNAS
                if !nouveautesNAS.isEmpty {
                    EtagereTV(titre: "Nouveaux sur ton NAS", sousTitre: "Prêts à regarder, du plus récent au plus ancien",
                              toutVoir: { etat.demandeRegarder = .nas }) {
                        ForEach(nouveautesNAS, id: \.reference) { oeuvre in
                            NavigationLink(value: oeuvre.reference) {
                                CarteLargeTV(surtitre: oeuvre.origine, titre: oeuvre.titre, detail: oeuvre.detail,
                                             cheminImage: oeuvre.cheminFond ?? oeuvre.cheminAffiche, marque: marque(oeuvre.reference),
                                             largeur: CarteLargeTV.largeurGrille, reference: oeuvre.reference)
                            }
                            .buttonStyle(.card)
                            .menuCarteTV(oeuvre.reference, titre: oeuvre.titre, cheminAffiche: oeuvre.cheminAffiche)
                        }
                    }
                }
                // En ce moment (6.6) : ce qui passe maintenant sur tes chaînes, et le clic lance blue TV sur la chaîne.
                let enDirect = enDirect
                if !enDirect.isEmpty {
                    EtagereTV(titre: "En ce moment sur tes chaînes", sousTitre: "Un clic et blue TV s'ouvre sur la chaîne, en direct",
                              toutVoir: { etat.demandeRegarder = .tele }, largeurCartes: CarteLargeTV.largeur) {
                        ForEach(enDirect) { bloc in
                            let chaine = nomChaine(bloc.premiere.chaine)
                            Button { BlueTVSurTV.ouvrir(bloc.premiere.chaine, nom: chaine, etat: etat, ouvrir: ouvrir) } label: {
                                CarteLargeTV(surtitre: "EN DIRECT · \(chaine.uppercased())", titre: bloc.premiere.titreGuide,
                                             detail: Self.reste(bloc.fin),
                                             cheminImage: bloc.premiere.cheminFond ?? bloc.premiere.cheminAffiche,
                                             lectureEnCoin: true)
                            }
                            .buttonStyle(.card)
                            .accessibilityHint("Ouvre \(chaine) en direct dans blue TV")
                        }
                    }
                }
                let teleCeSoir = teleCeSoir
                if !teleCeSoir.isEmpty {
                    EtagereTV(titre: "Ce soir à la TV", sousTitre: "Films et séries de tes chaînes, à venir",
                              toutVoir: { etat.demandeRegarder = .tele }, largeurCartes: CarteLargeTV.largeur) {
                        ForEach(teleCeSoir) { bloc in
                            let carte = CarteLargeTV(surtitre: bloc.debut <= .now ? "EN DIRECT" : bloc.debut.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_CH"))),
                                                     titre: bloc.premiere.titreGuide, detail: nomChaine(bloc.premiere.chaine),
                                                     cheminImage: bloc.premiere.cheminFond ?? bloc.premiere.cheminAffiche)
                            if let reference = bloc.reference {
                                NavigationLink(value: reference) { carte }.buttonStyle(.card)
                                    .menuCarteTV(reference, titre: bloc.premiere.titreGuide, cheminAffiche: bloc.premiere.cheminAffiche)
                            } else {
                                Button {} label: { carte }.buttonStyle(.card)
                            }
                        }
                    }
                }
                let aVoir = aVoir
                if !aVoir.isEmpty {
                    EtagereTV(titre: "Dans ta liste", sousTitre: "À voir, du plus récent au plus ancien") {
                        ForEach(aVoir) { suivi in
                            NavigationLink(value: suivi.reference) {
                                CarteLargeTV(surtitre: surLeNAS(suivi.reference) ? "Sur ton NAS" : nil, titre: suivi.titre,
                                             detail: suivi.type == .film ? "Film" : "Série", cheminImage: suivi.cheminAffiche,
                                             marque: surLeNAS(suivi.reference) ? "externaldrive.fill" : nil,
                                             largeur: CarteLargeTV.largeurGrille, reference: suivi.reference)
                            }
                            .buttonStyle(.card)
                            .menuCarteTV(suivi.reference, titre: suivi.titre, cheminAffiche: suivi.cheminAffiche)
                        }
                    }
                }
                etagere("Top de l'année", "Les mieux notés sur TMDB depuis un an", top)
            }
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(edges: .top)
        .fullScreenCover(isPresented: $configuration) { ConfigurationTV() }
        .task(id: etat.tmdb == nil) {
            // 8.10 : pas de rechargement à chaque retour sur l'accueil — seulement après une demi-heure.
            if let chargeLe, Date.now.timeIntervalSince(chargeLe) < 30 * 60, !duMoment.isEmpty { return }
            await charger()
            if !duMoment.isEmpty { chargeLe = .now }
        }
        .task(id: aReprendre.count <= 1) {
            guard aReprendre.count <= 1, suggestions.isEmpty else { return }
            await chargerSuggestions()
        }
        // Un genre écarté ou repris (8.7) : tes goûts changent, les suggestions aussi.
        .task(id: genresEcartes) {
            profil = try? ServiceGouts(contexte: contexte).profil()
            guard !suggestions.isEmpty else { return }
            await chargerSuggestions()
        }
    }

    @ViewBuilder
    private func etagere(_ titre: String, _ sousTitre: String, _ tous: [ApercuTV]) -> some View {
        let ecartes = ecartes
        let genres = genresEcartes
        let apercus = tous.filter { !ecartes.contains($0.reference) && genres.isDisjoint(with: $0.genres) }
        if !apercus.isEmpty {
            EtagereTV(titre: titre, sousTitre: sousTitre) {
                ForEach(apercus) { apercu in
                    NavigationLink(value: apercu.reference) {
                        CarteLargeTV(surtitre: nil, titre: apercu.titre, detail: apercu.sousTitre,
                                     cheminImage: apercu.cheminFond ?? apercu.cheminAffiche, marque: marque(apercu.reference),
                                     largeur: CarteLargeTV.largeurGrille, reference: apercu.reference)
                    }
                    .buttonStyle(.card)
                    .menuCarteTV(apercu.reference, titre: apercu.titre, cheminAffiche: apercu.cheminAffiche)
                }
            }
        }
    }

    /// La tête de l'accueil : l'image de la proposition bord à bord, à gauche son titre et ses trois boutons (Reprendre
    /// ou Regarder, Autre chose, Pas ce soir), à droite les nouveautés.
    private func enTete(_ proposition: Proposition, toutes propositions: [Proposition]) -> some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .frame(maxWidth: .infinity)
                // Pleine page (8.6, comme Netflix) : la proposition occupe l'écran, « Reprendre » dépasse en bas.
                // 950 points, pas tout l'écran (8.8, Patrick) : plein écran, la page défilait dès « Lecture », le menu du haut
                // se repliait et haut ne le retrouvait plus. `testHautDepuisLaPropositionRameneAuMenu` le vérifie.
                .frame(height: 950)
                .background(alignment: .top) {
                    // 8.7 : un fond sans texte choisi parmi les images du titre, comme sur l'iPad ; sinon celui d'avant.
                    ImageTV(url: ImageTMDB.url(etat.visuels.visuel(proposition.reference)?.fond, .fondGrand)
                                ?? ImageTMDB.url(proposition.cheminImage, proposition.large ? .fondGrand : .afficheGrande), symboleVide: "")
                        .id(proposition.reference)
                        .transition(.push(from: versLaDroite ? .trailing : .leading))
                        .frame(height: 1080)
                        .overlay {
                            // De la gauche vers le texte, et un voile en bas pour la lisibilité.
                            ZStack {
                                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.35), location: 0.6),
                                                       .init(color: .black.opacity(0.5), location: 1)], startPoint: .top, endPoint: .bottom)
                                LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .leading, endPoint: .center)
                            }
                        }
                        // 8.6 : l'image se fond dans le fond de la page, sans ligne nette sous la proposition.
                        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7),
                                                     .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                        .ignoresSafeArea()
                }
            HStack(alignment: .bottom, spacing: 60) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(proposition.surtitre).font(.system(size: 26, weight: .bold)).foregroundStyle(.white.opacity(0.78))
                    // Le logo du titre, quand TMDB en a un (8.7), comme sur l'iPhone ; sinon son nom.
                    if let logo = ImageTMDB.url(etat.visuels.visuel(proposition.reference)?.logo, .afficheGrande) {
                        AsyncImage(url: logo) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFit().frame(maxWidth: 620, maxHeight: 180, alignment: .leading)
                            } else {
                                Text(proposition.titre).font(.system(size: 76, weight: .heavy)).lineLimit(2)
                            }
                        }
                        .accessibilityElement()
                        .accessibilityLabel(proposition.titre)
                    } else {
                        Text(proposition.titre).font(.system(size: 76, weight: .heavy)).lineLimit(2)
                    }
                    if let detail = proposition.detail {
                        Text(detail).font(.system(size: 26)).foregroundStyle(.white.opacity(0.75))
                    }
                    if let progression = proposition.progression {
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.25))
                            Capsule().fill(.white).frame(width: 420 * progression)
                        }
                        .frame(width: 420, height: 6)
                        .padding(.top, 6)
                        .accessibilityHidden(true)
                    }
                    // 8.6, comme Netflix (demande de Patrick) : « Lecture » et « Plus d'infos », sur une ligne ; « Pas ce soir »
                    // est dans l'appui long.
                    HStack(spacing: 24) {
                        NavigationLink(value: LectureTVDemande(reference: proposition.reference)) {
                            Label(proposition.reprise != nil ? "Reprendre" : "Lecture", systemImage: "play.fill").lineLimit(1).fixedSize()
                        }
                        .buttonStyle(BoutonTV(principal: true))
                        .focused($boutonHero, equals: .lecture)
                        // Rien à gauche de « Lecture » : gauche y fait défiler vers la précédente.
                        .onMoveCommand { if $0 == .left { defiler(de: -1) } }
                        .contextMenu { menu(proposition) }
                        NavigationLink(value: proposition.reference) {
                            Label("Plus d'infos", systemImage: "info.circle").lineLimit(1).fixedSize()
                        }
                        .buttonStyle(BoutonTV())
                        .focused($boutonHero, equals: .infos)
                        // Rien à droite de « Plus d'infos » : droite y fait défiler vers la suivante.
                        .onMoveCommand { if $0 == .right { defiler(de: 1) } }
                        .contextMenu { menu(proposition) }
                    }
                    .padding(.top, 18)
                    // Où l'on en est parmi les propositions : les points, comme sur l'iPhone.
                    if propositions.count > 1 {
                        let montre = rang % propositions.count
                        HStack(spacing: 10) {
                            ForEach(propositions.indices, id: \.self) { index in
                                Capsule().fill(index == montre ? Color.white : Color.white.opacity(0.35))
                                    .frame(width: index == montre ? 34 : 10, height: 10)
                            }
                        }
                        .padding(.top, 18)
                        .accessibilityElement()
                        .accessibilityLabel("Proposition \(montre + 1) sur \(propositions.count)")
                        .accessibilityHint("Gauche sur « Lecture » ou droite sur « Plus d'infos » pour changer")
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: 1050, alignment: .leading)
                .focusSection()
                // En descendant du menu, le focus arrive sur « Lecture », pas sur le bouton le plus proche.
                .defaultFocus($boutonHero, .lecture)
                // Un glissement du doigt sur la télécommande fait défiler (8.6, comme Netflix), quand le focus est sur la
                // proposition ; le bouton choisi reste le même.
                .background {
                    GlissementTelecommande { pas in
                        let bouton = boutonHero
                        defiler(de: pas)
                        // Le glissement a aussi pu déplacer le focus d'un bouton à l'autre : il revient où il était.
                        guard let bouton else { return }
                        Task {
                            try? await Task.sleep(for: .milliseconds(80))
                            boutonHero = bouton
                        }
                    }
                }
                Spacer(minLength: 0)
                // 8.6 (demande de Patrick) : plus de nouveautés à droite, qui cachaient l'image ; elles sont en étagère dessous.
            }
            .padding(.horizontal, MargesTV.bord)
            .padding(.bottom, 40)
        }
        .task(id: proposition.reference) { etat.ou.demander(proposition.reference, client: etat.tmdb) }
        .task(id: propositions.map(\.reference)) { await etat.visuels.charger(propositions.map(\.reference), client: etat.tmdb) }
    }

    /// L'appui long sur la proposition : les mêmes actions que le « ⋯ » de l'iPhone (8.7) — « Pas ce soir », « Pas ce
    /// genre », « Je n'aime pas ».
    @ViewBuilder
    private func menu(_ proposition: Proposition) -> some View {
        Button { PasCeSoir.ecarter(proposition.reference) } label: { Label("Pas ce soir", systemImage: "moon.zzz") }
        let genres = proposition.genres.compactMap { id in GenresParDefaut.noms[id].map { (id: id, nom: $0) } }
        if !genres.isEmpty {
            Menu {
                ForEach(genres, id: \.id) { genre in
                    Button(genre.nom) { try? ServiceGouts(contexte: contexte).ecarterGenre(genre.id, nom: genre.nom) }
                }
            } label: { Label("Pas ce genre", systemImage: "hand.thumbsdown") }
        }
        Button {
            try? ServiceGouts(contexte: contexte).jamais(proposition.reference, titre: proposition.titre, genres: proposition.genres)
        } label: { Label("Je n'aime pas", systemImage: "hand.thumbsdown") }
    }

    /// 8.7 : le top de l'année dans l'ordre de tes goûts, comme sur l'iPhone — la popularité départage.
    private func selonTesGouts(_ apercus: [ApercuTV]) -> [ApercuTV] {
        guard let profil, !profil.estVide else { return apercus }
        func score(_ apercu: ApercuTV, rang: Int) -> Double {
            let affinite = apercu.genres.isEmpty ? 0 : apercu.genres.map(profil.affinite(genre:)).reduce(0, +) / Double(apercu.genres.count)
            return affinite - Double(rang) * 0.02
        }
        return apercus.enumerated()
            .map { (apercu: $0.element, score: score($0.element, rang: $0.offset)) }
            .sorted { $0.score > $1.score }
            .map(\.apercu)
    }

    /// Une proposition pour ce soir : un titre, d'où il vient et le bouton qui le lance.
    private struct Proposition {
        let reference: ReferenceTitre
        let surtitre: String
        let titre: String
        let detail: String?
        let cheminImage: String?
        let large: Bool
        var reprise: PositionLecture?
        /// Pour « Pas ce genre » (8.7).
        var genres: [Int] = []

        var progression: Double? { reprise?.fraction }
        /// « Reprendre à 1:03:12 » pour une vidéo entamée, sinon « Regarder » (la fiche choisit la source).
        var bouton: String { reprise.map { "Reprendre à \(PositionsLecture.horodatage($0.secondes))" } ?? "Regarder" }
    }

    /// Ce que l'accueil peut proposer ce soir, dans l'ordre : la soirée prévue, les vidéos entamées, ta liste sur le NAS,
    /// puis le top de l'année. Les titres écartés, déjà vus ou « pas ce soir » n'y sont pas.
    private var propositions: [Proposition] {
        let ecartes = ecartes.union(PasCeSoir.references(pasCeSoir))
        let genresEcartes = genresEcartes
        let genresConnus = Dictionary(suivis.map { ($0.reference, $0.genres) }, uniquingKeysWith: { premier, _ in premier })
        var vues = Set<ReferenceTitre>()
        var liste: [Proposition] = []
        /// Ce que tu as prévu ou commencé reste proposé ; le reste suit tes « Pas ce genre » (8.7).
        func ajouter(_ proposition: Proposition, choisi: Bool = false) {
            var proposition = proposition
            if proposition.genres.isEmpty { proposition.genres = genresConnus[proposition.reference] ?? [] }
            guard !ecartes.contains(proposition.reference), choisi || genresEcartes.isDisjoint(with: proposition.genres),
                  vues.insert(proposition.reference).inserted else { return }
            liste.append(proposition)
        }
        for prevu in ceSoir {
            let fond = fichiers.first { $0.reference == prevu.reference }?.cheminFond ?? fonds[prevu.reference]
            ajouter(Proposition(reference: prevu.reference, surtitre: ligne("Prévu ce soir", prevu.reference), titre: prevu.titre,
                                detail: prevu.reference.type == .film ? "Film" : "Série", cheminImage: fond ?? prevu.cheminAffiche,
                                large: fond != nil, reprise: repriseDe(prevu.reference)), choisi: true)
        }
        for reprise in aReprendre {
            let fichier = reprise.fichier
            let detail = LibellesProposition.reprise(film: fichier.type == .film, saison: fichier.saison, episode: fichier.episode,
                                                     position: reprise.position)
            ajouter(Proposition(reference: reprise.reference,
                                surtitre: ["Ce soir, pour toi", "Sur ton NAS", fichier.qualite].compactMap { $0 }.joined(separator: " · "),
                                titre: fichier.titre, detail: detail, cheminImage: fichier.cheminFond ?? fichier.cheminAffiche,
                                large: fichier.cheminFond != nil, reprise: reprise.position), choisi: true)
        }
        for suivi in aVoir where surLeNAS(suivi.reference) {
            let fichier = fichiers.first { $0.reference == suivi.reference }
            ajouter(Proposition(reference: suivi.reference,
                                surtitre: ["Ce soir, pour toi", "Sur ton NAS", fichier?.qualite].compactMap { $0 }.joined(separator: " · "),
                                titre: suivi.titre, detail: [suivi.type == .film ? "Film" : "Série", "dans ta liste"].joined(separator: " · "),
                                cheminImage: fichier?.cheminFond ?? suivi.cheminAffiche, large: fichier?.cheminFond != nil))
        }
        // 8.6 : d'après tes goûts, avant le top de l'année, comme sur l'iPhone.
        for idee in suggestions {
            let titre = idee.candidat.titre
            ajouter(Proposition(reference: titre.reference, surtitre: ligne("D'après tes goûts", titre.reference), titre: titre.titre,
                                detail: [titre.reference.type == .film ? "Film" : "Série", titre.date.map { String($0.annee) }]
                                    .compactMap { $0 }.joined(separator: " · "),
                                cheminImage: titre.cheminFond ?? titre.cheminAffiche, large: titre.cheminFond != nil, genres: titre.genres))
        }
        for apercu in selonTesGouts(top) {
            ajouter(Proposition(reference: apercu.reference, surtitre: ligne("Ce soir, pour toi", apercu.reference), titre: apercu.titre,
                                detail: apercu.sousTitre, cheminImage: apercu.cheminFond ?? apercu.cheminAffiche,
                                large: apercu.cheminFond != nil, genres: apercu.genres))
        }
        return Array(liste.prefix(nombrePropositions))
    }

    /// Passe à la proposition précédente ou suivante, l'image glissant dans le sens du geste.
    private func defiler(de pas: Int) {
        // Un glissement sur un bouton du bord arrive aussi comme appui : deux défilements rapprochés n'en font qu'un.
        guard propositions.count > 1, Date.now.timeIntervalSince(dernierDefilement) > 0.4 else { return }
        dernierDefilement = .now
        versLaDroite = pas > 0
        withAnimation(.easeInOut(duration: 0.45)) { rang = (rang + pas + propositions.count) % propositions.count }
    }

    /// La proposition montrée : « Autre chose » passe à la suivante, et revient à la première après la dernière.
    private var proposition: Proposition? {
        let toutes = propositions
        return toutes.isEmpty ? nil : toutes[rang % toutes.count]
    }

    /// Les trois nouveautés du panneau, les plus récentes d'abord, sans les titres écartés ni celui de la proposition.
    private func nouveautes(sauf reference: ReferenceTitre?) -> [ApercuTV] {
        let ecartes = ecartes
        // 8.6 : par popularité, comme sur l'iPhone — les dix premières portent leur rang.
        let genres = genresEcartes
        return Array(duMoment.sorted { $0.popularite > $1.popularite }
            .filter { !ecartes.contains($0.reference) && genres.isDisjoint(with: $0.genres) && $0.reference != reference }.prefix(20))
    }

    /// « Prévu ce soir · Sur ton NAS », « Ce soir, pour toi · Netflix ».
    private func ligne(_ debut: String, _ reference: ReferenceTitre) -> String {
        [debut, origine(reference)].compactMap { $0 }.joined(separator: " · ")
    }

    /// Où il se regarde, comme la ligne d'origine des cartes : le NAS, sinon ta plateforme.
    private func origine(_ reference: ReferenceTitre) -> String? {
        if surLeNAS(reference) { return "Sur ton NAS" }
        for badge in etat.ou.badges(reference) {
            if case .plateforme(_, let nom, _) = badge { return CarteLargeTV.nomCourt(nom) }
        }
        return nil
    }

    private func repriseDe(_ reference: ReferenceTitre) -> PositionLecture? {
        aReprendre.first { $0.reference == reference }?.position
    }


    /// En ce moment : les films et séries qui passent maintenant, sur une chaîne que blue TV connaît (6.6).
    private var enDirect: [BlocDiffusion] {
        let maintenant = Date.now
        return GrilleTele.blocs(diffusions.filter { $0.debut <= maintenant && $0.fin > maintenant })
            .filter { LiensChaines.numero(chaine: $0.premiere.chaine) != nil }
            .sorted { $0.fin < $1.fin }.prefix(12).map { $0 }
    }

    /// Ce soir à la TV : à venir dans la journée TV d'aujourd'hui — ce qui passe déjà est dans « En ce moment ».
    private var teleCeSoir: [BlocDiffusion] {
        let maintenant = Date.now
        let aujourdhui = GrilleTele.jourTele(maintenant)
        return GrilleTele.blocs(diffusions.filter { $0.debut > maintenant })
            .filter { GrilleTele.jourAffiche($0, maintenant: maintenant) == aujourdhui }
            .sorted { $0.debut < $1.debut }.prefix(12).map { $0 }
    }

    /// « Encore 42 min » : ce qu'il reste à voir.
    static func reste(_ fin: Date) -> String {
        let minutes = max(1, Int(fin.timeIntervalSinceNow / 60))
        return minutes >= 60 ? "Encore \(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "Encore \(minutes) min"
    }

    private func nomChaine(_ identifiant: String) -> String {
        NomChaineTV.lire(identifiant, parmi: chaines)
    }

    // MARK: Données

    /// Les vidéos du NAS entamées, la plus récente d'abord, avec leur fichier.
    private var aReprendre: [(fichier: FichierNAS, reference: ReferenceTitre, position: PositionLecture)] {
        etat.positions.enCours.prefix(12).compactMap { entree in
            guard let fichier = fichiers.first(where: { $0.chemin == entree.chemin }), let reference = fichier.reference else { return nil }
            return (fichier, reference, entree.position)
        }
    }

    private var ceSoir: [SelectionSoir] {
        let soiree = ServiceSoiree.soiree()
        return soirees.filter { $0.soiree == soiree }
    }

    private var aVoir: [Suivi] {
        suivis.filter { $0.statut == .aVoir && !$0.masque }.sorted { $0.ajouteLe > $1.ajouteLe }.prefix(20).map { $0 }
    }

    private var nouveautesNAS: [OeuvreTV] { OeuvreTV.regrouper(fichiers).prefix(20).map { $0 } }

    private func surLeNAS(_ reference: ReferenceTitre) -> Bool {
        fichiers.contains { $0.reference == reference }
    }

    /// Sur le NAS d'abord, sinon « dans ta liste ».
    private func marque(_ reference: ReferenceTitre) -> String? {
        if surLeNAS(reference) { return "externaldrive.fill" }
        return suivis.contains { $0.reference == reference } ? "bookmark.fill" : nil
    }

    /// Les suggestions de l'étagère, sans les titres écartés ni celui de la proposition.
    private func suggestionsAMontrer(sauf reference: ReferenceTitre?) -> [SuggestionClassee] {
        let ecartes = ecartes.union(PasCeSoir.references(pasCeSoir))
        return suggestions.filter { !ecartes.contains($0.candidat.reference) && $0.candidat.reference != reference }
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
            .suggerer(demande, candidats: candidats, profil: profil, nomsGenres: GenresParDefaut.noms).suggestions
    }

    private func charger() async {
        guard let client = etat.tmdb else { return }
        async let films = try? client.decouvrirFilms(.duMoment(.film))
        async let series = try? client.decouvrirSeries(.duMoment(.serie))
        async let topFilms = try? client.decouvrirFilms(.top(.film))
        async let topSeries = try? client.decouvrirSeries(.top(.serie))
        duMoment = ApercuTV.meler((await films)?.resultats ?? [], (await series)?.resultats ?? [])
        top = ApercuTV.meler((await topFilms)?.resultats ?? [], (await topSeries)?.resultats ?? [])
        // L'image de fond du premier titre de la soirée, pour la grande image de tête.
        if let prevu = ceSoir.first, fonds[prevu.reference] == nil, !surLeNAS(prevu.reference) {
            switch prevu.reference.type {
            case .film: fonds[prevu.reference] = (try? await client.film(prevu.reference.tmdbID, complements: []))?.cheminFond
            case .serie: fonds[prevu.reference] = (try? await client.serie(prevu.reference.tmdbID))?.cheminFond
            }
        }
    }
}

/// Un titre à montrer sur une étagère, film ou série.
struct ApercuTV: Identifiable, Hashable {
    let reference: ReferenceTitre
    let titre: String
    let sousTitre: String?
    let cheminAffiche: String?
    var cheminFond: String?
    let popularite: Double
    /// Pour ranger les résultats par genre et par année (8.2.15), comme sur l'iPhone.
    var genres: [Int] = []
    var annee: Int?
    /// Sortie ou première diffusion : les Nouveautés se rangent des plus récentes aux plus anciennes (8.2.19).
    var date: DateTMDB?

    var id: ReferenceTitre { reference }

    /// `garderLOrdre` : celui de TMDB (une recherche, un tri choisi) plutôt que la popularité.
    static func meler(_ films: [FilmResume], _ series: [SerieResume], garderLOrdre: Bool = false) -> [ApercuTV] {
        let deFilms = films.map {
            ApercuTV(reference: ReferenceTitre(type: .film, tmdbID: $0.id), titre: $0.titre,
                     sousTitre: ["Film", $0.dateSortie.map { String($0.annee) }].compactMap { $0 }.joined(separator: " · "),
                     cheminAffiche: $0.cheminAffiche, cheminFond: $0.cheminFond, popularite: $0.popularite,
                     genres: $0.genres, annee: $0.dateSortie?.annee, date: $0.dateSortie)
        }
        let deSeries = series.map {
            ApercuTV(reference: ReferenceTitre(type: .serie, tmdbID: $0.id), titre: $0.nom, sousTitre: "Série",
                     cheminAffiche: $0.cheminAffiche, cheminFond: $0.cheminFond, popularite: $0.popularite,
                     genres: $0.genres, annee: $0.premiereDiffusion?.annee, date: $0.premiereDiffusion)
        }
        let tous = (deFilms + deSeries).filter { $0.cheminAffiche != nil }
        return (garderLOrdre ? tous : tous.sorted { $0.popularite > $1.popularite }).prefix(garderLOrdre ? 40 : 24).map { $0 }
    }
}

/// Une œuvre du NAS : un film, ou une série et tous ses épisodes présents.
struct OeuvreTV: Hashable {
    let reference: ReferenceTitre
    let titre: String
    let cheminAffiche: String?
    /// La grande image du titre, pour la carte 16/9 ; l'analyse du NAS la garde avec le fichier.
    var cheminFond: String?
    let fichiers: Int
    let qualite: String?
    let indexeLe: Date

    /// Charte 8.0 : la ligne d'origine dit où et en quelle qualité, la ligne de faits dit quoi — sans redite.
    var origine: String { ["Sur ton NAS", qualite].compactMap { $0 }.joined(separator: " · ") }

    var detail: String {
        if reference.type == .serie { return fichiers > 1 ? "Série · \(fichiers) épisodes" : "Série · 1 épisode" }
        return "Film"
    }

    /// Du plus récemment arrivé au plus ancien ; les fichiers non reconnus par TMDB n'ont pas de fiche et sont laissés.
    /// 8.2.17 : « arrivé » veut dire la date du fichier sur le NAS (`DetailsNAS`), et non celle de l'analyse, refaite
    /// pour tous les fichiers à chaque passage.
    ///
    /// 8.9 (bilan de l'Apple TV) : la page NAS et l'accueil l'appelaient plus de dix fois par affichage, en relisant
    /// chaque fois les détails du NAS. Les derniers résultats sont gardés, par contenu : la même liste de fichiers et
    /// les mêmes détails rendent aussitôt le même regroupement.
    @MainActor
    static func regrouper(_ fichiers: [FichierNAS]) -> [OeuvreTV] {
        let brut = UserDefaults.standard.data(forKey: DetailsNAS.cle)
        var empreinte = Hasher()
        empreinte.combine(brut)
        for fichier in fichiers {
            empreinte.combine(fichier.chemin)
            empreinte.combine(fichier.tmdbID)
            empreinte.combine(fichier.cheminAffiche)
        }
        let cle = empreinte.finalize()
        if let connues = memoire[cle] { return connues }
        let oeuvres = regrouper(fichiers, details: brut.flatMap(DetailsNAS.decoder) ?? DetailsNAS())
        if memoire.count >= 12 { memoire.removeAll() }
        memoire[cle] = oeuvres
        return oeuvres
    }

    @MainActor private static var memoire: [Int: [OeuvreTV]] = [:]

    private static func regrouper(_ fichiers: [FichierNAS], details: DetailsNAS) -> [OeuvreTV] {
        func arrivee(_ fichier: FichierNAS) -> Date { details.ajouts[fichier.chemin] ?? fichier.indexeLe }
        var parTitre: [ReferenceTitre: [FichierNAS]] = [:]
        for fichier in fichiers {
            guard let reference = fichier.reference else { continue }
            parTitre[reference, default: []].append(fichier)
        }
        return parTitre.map { reference, siens in
            let recent = siens.max { arrivee($0) < arrivee($1) } ?? siens[0]
            return OeuvreTV(reference: reference, titre: recent.titre, cheminAffiche: recent.cheminAffiche,
                            cheminFond: siens.compactMap(\.cheminFond).first, fichiers: siens.count,
                            qualite: recent.qualite, indexeLe: arrivee(recent))
        }
        .sorted { ($0.indexeLe, $0.titre) > ($1.indexeLe, $1.titre) }
    }
}

/// Une ligne du panneau Nouveautés : grise au repos, blanche à texte noir et soulevée au focus, comme les boutons.
struct LigneNouveauteTV: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Corps(configuration: configuration)
    }

    private struct Corps: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var aLeFocus

        var body: some View {
            configuration.label
                .foregroundStyle(aLeFocus ? .black : .white)
                .padding(14)
                .background(aLeFocus ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.eleve.opacity(0.88)),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(aLeFocus ? 0.45 : 0), radius: 18, y: 10)
                .scaleEffect(aLeFocus ? 1.05 : (configuration.isPressed ? 0.97 : 1))
                .animation(.easeOut(duration: 0.15), value: aLeFocus)
        }
    }
}
