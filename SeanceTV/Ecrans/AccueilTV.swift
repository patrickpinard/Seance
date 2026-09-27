import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// L'accueil de la TV : la soirée d'abord, puis ce qui se regarde tout de suite (le NAS), puis de quoi choisir.
struct AccueilTV: View {
    @Environment(EtatTV.self) private var etat
    @Environment(\.openURL) private var ouvrir
    @Environment(\.modelContext) private var contexte
    @Query(sort: \SelectionSoir.ajouteLe) private var soirees: [SelectionSoir]
    @Query(sort: \FichierNAS.indexeLe, order: .reverse) private var fichiers: [FichierNAS]
    @Query private var suivis: [Suivi]
    @Query(sort: \Diffusion.debut) private var diffusions: [Diffusion]
    @Query private var chaines: [Chaine]

    @State private var duMoment: [ApercuTV] = []
    /// Déjà vus, refusés ou « pas intéressé pour l'instant » (8.2.15) : comme sur l'iPhone, plus proposés ici.
    @Query(filter: #Predicate<Suivi> { $0.statutBrut == "exclu" || $0.exclusionLangue || $0.statutBrut == "termine" })
    private var suivisEcartes: [Suivi]
    @AppStorage(PasInteresse.cle) private var pasInteresse = ""
    private var ecartes: Set<ReferenceTitre> { Set(suivisEcartes.map(\.reference)).union(PasInteresse.references(pasInteresse)) }
    @State private var top: [ApercuTV] = []
    @State private var configuration = false
    /// Images de fond des titres de la soirée, lues sur TMDB quand le NAS ne les connaît pas.
    @State private var fonds: [ReferenceTitre: String] = [:]

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
                if let vedette { enTete(vedette) } else { Color.clear.frame(height: 40) }
                // 8.0 : « Reprendre » d'abord — les vidéos du NAS entamées ici ou sur un autre appareil. La soirée, elle,
                // est dans Regarder.
                if !aReprendre.isEmpty {
                    EtagereTV(titre: "Reprendre", sousTitre: "Là où tu t'es arrêté, ici ou sur un autre appareil") {
                        ForEach(aReprendre, id: \.fichier.chemin) { reprise in
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
                }
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
                etagere("Nouveautés", "Sorties et nouveaux épisodes du mois, les plus populaires d'abord", duMoment)
                etagere("Top de l'année", "Les mieux notés sur TMDB depuis un an", top)
            }
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(edges: .top)
        .fullScreenCover(isPresented: $configuration) { ConfigurationTV() }
        .task(id: etat.tmdb == nil) { await charger() }
    }

    @ViewBuilder
    private func etagere(_ titre: String, _ sousTitre: String, _ tous: [ApercuTV]) -> some View {
        let ecartes = ecartes
        let apercus = tous.filter { !ecartes.contains($0.reference) }
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

    /// La grande image de tête : ta soirée si tu en as prévu une, sinon le titre du moment.
    private func enTete(_ vedette: Vedette) -> some View {
        // Maquette 8.0, n° 2 : l'image couvre tout l'écran, bord à bord, sous le menu ; la première rangée (« Reprendre »)
        // vient mordre sur son bas.
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 700)
                .background(alignment: .top) {
                    ImageTV(url: ImageTMDB.url(vedette.cheminImage, vedette.large ? .fondGrand : .afficheGrande), symboleVide: "")
                        .frame(height: 1080)
                        .overlay {
                            // Deux dégradés : du bas vers le titre, et de la gauche vers le texte.
                            ZStack {
                                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.35), location: 0.55),
                                                       .init(color: Theme.fond.opacity(0.9), location: 1)], startPoint: .top, endPoint: .bottom)
                                LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .leading, endPoint: .center)
                            }
                        }
                        .ignoresSafeArea()
                }
            VStack(alignment: .leading, spacing: 12) {
                Text(vedette.surtitre).font(.system(size: 26, weight: .bold)).foregroundStyle(.white.opacity(0.78))
                Text(vedette.titre).font(.system(size: 76, weight: .heavy)).lineLimit(2)
                if let detail = vedette.detail {
                    Text(detail).font(.system(size: 26)).foregroundStyle(.white.opacity(0.75))
                }
                HStack(spacing: 20) {
                    NavigationLink(value: LectureTVDemande(reference: vedette.reference)) { Label("Regarder", systemImage: "play.fill") }
                    NavigationLink(value: vedette.reference) { Label("Voir la fiche", systemImage: "info.circle") }
                }
                .buttonStyle(BoutonTV())
                .padding(.top, 10)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: 1100, alignment: .leading)
            .padding(.horizontal, MargesTV.bord)
            .padding(.bottom, 40)
        }
        .focusSection()
    }

    private struct Vedette {
        let reference: ReferenceTitre
        let surtitre: String
        let titre: String
        let detail: String?
        let cheminImage: String?
        let large: Bool
        var surLeNAS = false
    }

    private var vedette: Vedette? {
        if let prevu = ceSoir.first {
            let fond = fichiers.first { $0.reference == prevu.reference }?.cheminFond ?? fonds[prevu.reference]
            return Vedette(reference: prevu.reference, surtitre: ceSoir.count > 1 ? "Ce soir · \(ceSoir.count) titres prévus" : "Ce soir",
                           titre: prevu.titre, detail: prevu.reference.type == .film ? "Film" : "Série", cheminImage: fond ?? prevu.cheminAffiche, large: fond != nil,
                           surLeNAS: surLeNAS(prevu.reference))
        }
        guard let premier = duMoment.first else { return nil }
        return Vedette(reference: premier.reference, surtitre: "Nouveauté", titre: premier.titre, detail: premier.sousTitre,
                       cheminImage: premier.cheminFond ?? premier.cheminAffiche, large: premier.cheminFond != nil)
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

    var id: ReferenceTitre { reference }

    /// `garderLOrdre` : celui de TMDB (une recherche, un tri choisi) plutôt que la popularité.
    static func meler(_ films: [FilmResume], _ series: [SerieResume], garderLOrdre: Bool = false) -> [ApercuTV] {
        let deFilms = films.map {
            ApercuTV(reference: ReferenceTitre(type: .film, tmdbID: $0.id), titre: $0.titre,
                     sousTitre: ["Film", $0.dateSortie.map { String($0.annee) }].compactMap { $0 }.joined(separator: " · "),
                     cheminAffiche: $0.cheminAffiche, cheminFond: $0.cheminFond, popularite: $0.popularite,
                     genres: $0.genres, annee: $0.dateSortie?.annee)
        }
        let deSeries = series.map {
            ApercuTV(reference: ReferenceTitre(type: .serie, tmdbID: $0.id), titre: $0.nom, sousTitre: "Série",
                     cheminAffiche: $0.cheminAffiche, cheminFond: $0.cheminFond, popularite: $0.popularite,
                     genres: $0.genres, annee: $0.premiereDiffusion?.annee)
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
    static func regrouper(_ fichiers: [FichierNAS]) -> [OeuvreTV] {
        var parTitre: [ReferenceTitre: [FichierNAS]] = [:]
        for fichier in fichiers {
            guard let reference = fichier.reference else { continue }
            parTitre[reference, default: []].append(fichier)
        }
        return parTitre.map { reference, siens in
            let recent = siens.max { $0.indexeLe < $1.indexeLe } ?? siens[0]
            return OeuvreTV(reference: reference, titre: recent.titre, cheminAffiche: recent.cheminAffiche,
                            cheminFond: siens.compactMap(\.cheminFond).first, fichiers: siens.count,
                            qualite: recent.qualite, indexeLe: recent.indexeLe)
        }
        .sorted { ($0.indexeLe, $0.titre) > ($1.indexeLe, $1.titre) }
    }
}
