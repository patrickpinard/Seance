import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Un film ou une série du NAS, avec tous ses fichiers : une seule carte pour les 30 épisodes de Reacher.
struct OeuvreNAS: Identifiable {
    let id: String
    let reference: ReferenceTitre?
    let titre: String
    let annee: Int?
    let cheminAffiche: String?
    let noteMoyenne: Double
    let nombreVotes: Int
    let fichiers: [FichierNAS]

    var qualite: String? {
        fichiers.compactMap { $0.qualite.flatMap(QualiteVideo.init(description:)) }.max()?.description
    }

    var nouveaute: Bool {
        fichiers.contains { $0.dossier == "NEW" }
    }

    /// Le plus récent de ses fichiers, d'après ce que l'analyse a relevé sur le NAS.
    func ajouteLe(_ details: DetailsNAS) -> Date? {
        details.ajout(fichiers.map(\.chemin))
    }

    /// Les genres du titre, relevés au rattachement TMDB.
    func genres(_ details: DetailsNAS) -> [Int] {
        reference.flatMap { details.genres[$0.tmdbID] } ?? []
    }

    /// Regroupe les fichiers reconnus par titre TMDB ; les autres restent seuls.
    static func regrouper(_ fichiers: [FichierNAS]) -> [OeuvreNAS] {
        var groupes: [String: [FichierNAS]] = [:]
        var ordre: [String] = []
        for fichier in fichiers {
            let cle = fichier.reference.map(\.description) ?? fichier.chemin
            if groupes[cle] == nil { ordre.append(cle) }
            groupes[cle, default: []].append(fichier)
        }
        return ordre.compactMap { cle in
            guard let groupe = groupes[cle], let premier = groupe.first else { return nil }
            return OeuvreNAS(id: cle, reference: premier.reference, titre: premier.titre, annee: premier.annee,
                             cheminAffiche: premier.cheminAffiche, noteMoyenne: premier.noteMoyenne,
                             nombreVotes: premier.nombreVotes, fichiers: groupe)
        }
    }
}

/// Comment la bibliothèque se range (6.4, demande de Patrick) : d'un coup d'œil ce qui vient d'arriver, ou tout
/// par année de sortie, ou tout par genre. « Alphabétique » reste le rangement d'origine.
enum RangementNAS: String, CaseIterable, Identifiable {
    case ajout = "Ajouts"
    case alphabetique = "A→Z"
    case annee = "Année"
    case genre = "Genre"

    var id: String { rawValue }

    var symbole: String {
        switch self {
        case .alphabetique: "textformat.abc"
        case .ajout: "clock.arrow.circlepath"
        case .annee: "calendar"
        case .genre: "theatermasks"
        }
    }
}

/// Une tranche de la bibliothèque : « Septembre 2026 », « 2019 », « Action ».
struct TrancheNAS: Identifiable {
    let titre: String
    let oeuvres: [OeuvreNAS]

    var id: String { titre }
}

extension TrancheNAS {
    /// Range la bibliothèque en tranches. Par ajout : le mois où le fichier est arrivé sur le NAS, le plus récent
    /// d'abord — un film peut manquer de date si le NAS ne la donne pas, il va alors dans « Date inconnue ».
    /// Par année : l'année de sortie. Par genre : un titre à plusieurs genres apparaît dans chacun.
    @MainActor
    static func ranger(_ oeuvres: [OeuvreNAS], par rangement: RangementNAS, details: DetailsNAS, noms: [Int: String],
                       calendrier: Calendar = .current) -> [TrancheNAS] {
        switch rangement {
        case .alphabetique:
            return [TrancheNAS(titre: "", oeuvres: oeuvres)]
        case .ajout:
            var parMois: [Date: [OeuvreNAS]] = [:]
            var sansDate: [OeuvreNAS] = []
            for oeuvre in oeuvres {
                guard let date = oeuvre.ajouteLe(details),
                      let mois = calendrier.date(from: calendrier.dateComponents([.year, .month], from: date))
                else { sansDate.append(oeuvre); continue }
                parMois[mois, default: []].append(oeuvre)
            }
            var sections = parMois.sorted { $0.key > $1.key }.map { mois, liste in
                TrancheNAS(titre: Self.nomDuMois(mois), oeuvres: liste.sorted { ($0.ajouteLe(details) ?? .distantPast) > ($1.ajouteLe(details) ?? .distantPast) })
            }
            if !sansDate.isEmpty { sections.append(TrancheNAS(titre: "Date inconnue", oeuvres: sansDate)) }
            return sections
        case .annee:
            var parAnnee: [Int: [OeuvreNAS]] = [:]
            var sansAnnee: [OeuvreNAS] = []
            for oeuvre in oeuvres {
                if let annee = oeuvre.annee { parAnnee[annee, default: []].append(oeuvre) } else { sansAnnee.append(oeuvre) }
            }
            var sections = parAnnee.sorted { $0.key > $1.key }.map { annee, liste in
                TrancheNAS(titre: String(annee), oeuvres: liste)
            }
            if !sansAnnee.isEmpty { sections.append(TrancheNAS(titre: "Année inconnue", oeuvres: sansAnnee)) }
            return sections
        case .genre:
            var parGenre: [Int: [OeuvreNAS]] = [:]
            var sansGenre: [OeuvreNAS] = []
            for oeuvre in oeuvres {
                let genres = oeuvre.genres(details)
                if genres.isEmpty { sansGenre.append(oeuvre) }
                for genre in genres { parGenre[genre, default: []].append(oeuvre) }
            }
            var sections = parGenre.map { genre, liste in
                TrancheNAS(titre: noms[genre] ?? "Genre \(genre)", oeuvres: liste)
            }
            // Le genre le mieux fourni d'abord : c'est ce qu'on regarde le plus.
            sections.sort { ($0.oeuvres.count, $1.titre) > ($1.oeuvres.count, $0.titre) }
            if !sansGenre.isEmpty { sections.append(TrancheNAS(titre: "Sans genre", oeuvres: sansGenre)) }
            return sections
        }
    }

    static func nomDuMois(_ date: Date) -> String {
        let texte = date.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "fr_CH")))
        return texte.prefix(1).uppercased() + texte.dropFirst()
    }
}

/// Bibliothèque du NAS (EF-72 à EF-79) : films, séries, dossier NEW et vidéos non reconnues.
struct NASView: View {
    enum Rayon: String, CaseIterable, Identifiable {
        case films = "Films"
        case series = "Séries"
        case nouveautes = "NEW"
        /// Les vidéos personnelles, au même rang que Films et Séries (6.3, demande de Patrick) : on filtre ce que
        /// montre la page au lieu de descendre dans une tuile à part. Le rayon s'appelle « Vidéos » depuis la 6.5.
        case perso = "Vidéos"
        /// Pas un rayon mais un entretien : hors du sélecteur, en petite puce sous le résumé.
        case nonReconnus = "Non reconnus"

        var id: String { rawValue }
    }

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(sort: \FichierNAS.titre) private var fichiers: [FichierNAS]
    @Query private var suivis: [Suivi]
    @State private var rayon = Rayon.films
    // 8.2.11 (demande de Patrick) : les derniers arrivés d'abord, par défaut — nouvelle clé, pour que le choix d'avant
    // (A→Z) ne le masque pas.
    @AppStorage("nas.rangement.2") private var rangementBrut = RangementNAS.ajout.rawValue
    private var rangement: RangementNAS { RangementNAS(rawValue: rangementBrut) ?? .alphabetique }
    @State private var recherche = ""
    /// Dates d'ajout et genres, relevés par la dernière analyse (6.4).
    @State private var detailsNAS = DetailsNAS()
    @State private var fichierChoisi: FichierNAS?
    /// Les sections ouvertes ou fermées (8.2.8) : par genre, fermées au départ — une liste de genres à ouvrir.
    @State private var sections = SectionsRepliables()

    @Environment(\.horizontalSizeClass) private var largeurGrille
    /// Affiches plus grandes sur le Mac : 105 points y feraient des timbres-poste.
    private var colonnes: [GridItem] {
        CarteLargeTitre.colonnes
    }

    var body: some View {
        Group {
            if fichiers.isEmpty {
                vide
            } else {
                bibliotheque
            }
        }
        .background(Theme.fond)
        .titrePage("Sur ton NAS")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // Charte 8.0 : une seule roue dentée par page, celle du haut (Réglages). Les gestes propres au NAS passent
            // par « ⋯ ».
            ToolbarItemGroup(placement: .topBarTrailing) {
                if etat.nas.enCours {
                    ProgressView()
                } else {
                    Menu {
                        if etat.nas.estConfigure {
                            Button("Analyser le NAS maintenant", systemImage: "arrow.clockwise") { analyser() }
                        }
                        NavigationLink(value: DestinationReglage.nas) {
                            Label("Réglages du NAS", systemImage: "externaldrive")
                        }
                    } label: {
                        Label("Plus", systemImage: "ellipsis")
                    }
                }
            }
        }
        .sheet(item: $fichierChoisi) { fichier in
            FeuilleFichierNAS(fichier: fichier)
                .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private var vide: some View {
        if etat.nas.enCours {
            ProgressView("Analyse du NAS…")
        } else if !etat.nas.estConfigure {
            ContentUnavailableView {
                Label("NAS à configurer", systemImage: "externaldrive.badge.questionmark")
            } description: {
                Text("Indique l'adresse, le partage et le mot de passe de ton NAS pour voir les films déjà téléchargés.")
            } actions: {
                NavigationLink("Configurer le NAS", value: DestinationReglage.nas)
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView {
                Label("Bibliothèque vide", systemImage: "externaldrive")
            } description: {
                Text(etat.nas.erreur ?? "Lance une analyse pour lister les films et séries du NAS.")
            } actions: {
                Button("Analyser le NAS") { analyser() }
                    .buttonStyle(.borderedProminent)
                    .disabled(etat.tmdb == nil)
            }
        }
    }

    private var bibliotheque: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SelecteurCases(selection: $rayon, cases: rayonsMontres.map { .init(valeur: $0, nom: libelle($0)) })

                resume
                if let erreur = etat.nas.erreur {
                    MessageEtat(texte: erreur, ton: .probleme, libelleAction: "Réessayer") { analyser() }
                        .padding(.horizontal, -20)
                }

                if rayon == .nonReconnus {
                    nonReconnus
                } else if rayon == .perso {
                    VideosPersoView(dossier: DossierVideosPerso(), integree: true)
                        .padding(.horizontal, -20)
                } else {
                    let oeuvres = oeuvres(du: rayon)
                    let marques = MarqueListe.marques(suivis)
                    if oeuvres.isEmpty {
                        MessageEtat(texte: recherche.isEmpty ? "Rien dans ce rayon." : "Aucun titre ne correspond à « \(recherche) ».",
                                    symbole: "externaldrive")
                            .padding(.horizontal, -20)
                    }
                    if rayon == .nouveautes {
                        // Le dossier NEW tout en grandes cartes : peu de titres, ceux qu'on vient chercher.
                        LazyVGrid(columns: CarteLargeTitre.colonnes, spacing: 14) {
                            ForEach(oeuvres) { oeuvre in
                                CarteLargeNAS(oeuvre: oeuvre, decor: oeuvre.reference.flatMap(etat.decors.decor),
                                                  marque: oeuvre.reference.flatMap { marques[$0] })
                            }
                        }
                    } else {
                        let nouvelles = recherche.isEmpty ? oeuvres.filter(\.nouveaute) : []
                        if !nouvelles.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Nouveaux sur ton NAS", systemImage: "sparkles")
                                    .font(.title3.weight(.bold))
                                    .labelStyle(EtiquetteSection())
                                DefilementHorizontal {
                                    LazyHStack(spacing: 14) {
                                        ForEach(nouvelles) { oeuvre in
                                            CarteLargeNAS(oeuvre: oeuvre, decor: oeuvre.reference.flatMap(etat.decors.decor),
                                                              marque: oeuvre.reference.flatMap { marques[$0] })
                                                .frame(width: 310)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                                .padding(.horizontal, -20)
                            }
                            Text(rayon == .films ? "Tous les films" : "Toutes les séries")
                                .font(.title3.weight(.bold))
                                .padding(.top, 6)
                        }
                        if rangement == .alphabetique {
                            LazyVGrid(columns: CarteLargeTitre.colonnes, spacing: 14) {
                                ForEach(oeuvres) { oeuvre in
                                    CarteLargeNAS(oeuvre: oeuvre, decor: oeuvre.reference.flatMap(etat.decors.decor),
                                                  marque: oeuvre.reference.flatMap { marques[$0] })
                                }
                            }
                        } else {
                            // Rangé par ajout, par année ou par genre : une section par tranche, la plus récente d'abord.
                            // Chaque section s'ouvre et se ferme (8.2.8) ; « Tout ouvrir » / « Tout fermer » en tête.
                            let tranches = TrancheNAS.ranger(oeuvres, par: rangement, details: detailsNAS, noms: etat.nomsGenres)
                            let titres = tranches.map(\.titre)
                            HStack {
                                Spacer()
                                let toutes = sections.toutesOuvertes(titres)
                                Button(toutes ? "Tout fermer" : "Tout ouvrir") {
                                    withAnimation(.snappy) { sections.toutes(ouvertes: !toutes, titres: titres) }
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(minHeight: 44)
                            }
                            ForEach(tranches) { section in
                                VStack(alignment: .leading, spacing: 10) {
                                    EnTeteRepliable(titre: section.titre, detail: Format.pluriel(section.oeuvres.count, "titre"),
                                                    ouverte: sections.ouverte(section.titre)) { sections.basculer(section.titre) }
                                    if sections.ouverte(section.titre) {
                                        LazyVGrid(columns: CarteLargeTitre.colonnes, spacing: 14) {
                                            ForEach(section.oeuvres) { oeuvre in
                                                CarteLargeNAS(oeuvre: oeuvre, decor: oeuvre.reference.flatMap(etat.decors.decor),
                                                              marque: oeuvre.reference.flatMap { marques[$0] })
                                            }
                                        }
                                        .transition(.opacity)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.immediately)
        // Par genre, les sections partent fermées ; par année ou par ajout, ouvertes.
        .onChange(of: rangementBrut, initial: true) { _, _ in
            sections = SectionsRepliables(ouvertesParDefaut: rangement != .genre)
        }
        // Les images de fond des nouveautés, pour leurs grandes cartes.
        .task(id: referencesNouveautes) { await etat.decors.charger(referencesNouveautes, client: etat.tmdb) }
        .searchable(text: $recherche, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Titre")
        .refreshable { await etat.nas.analyser(contexte: contexte, tmdb: etat.tmdb) }
        .task(id: etat.nas.derniereAnalyse) {
            detailsNAS = UserDefaults.standard.data(forKey: DetailsNAS.cle).flatMap(DetailsNAS.decoder) ?? DetailsNAS()
        }
    }

    /// Une seule ligne (8.2.7, demande de Patrick) : le rangement en pastilles — A→Z, ajouts, année, genre —, et à côté
    /// le nombre de vidéos non reconnues. Les comptes (titres, vidéos, date d'analyse) ont quitté la page.
    private var resume: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if rayon == .films || rayon == .series {
                    ForEach(RangementNAS.allCases) { mode in
                        PuceFiltre(libelle: mode.rawValue, active: rangement == mode) { rangementBrut = mode.rawValue }
                            .accessibilityLabel("Ranger par \(mode.rawValue)")
                    }
                }
                let restent = compte(.nonReconnus)
                if restent > 0 || rayon == .nonReconnus {
                    if rayon != .nonReconnus { Divider().frame(height: 22).padding(.horizontal, 2) }
                    PuceFiltre(libelle: rayon == .nonReconnus ? "Revenir aux titres" : "\(restent) non reconnu\(restent > 1 ? "s" : "")",
                               active: rayon == .nonReconnus) {
                        rayon = rayon == .nonReconnus ? (rayonsMontres.first ?? .films) : .nonReconnus
                    }
                }
            }
        }
        .scrollClipDisabled()
    }

    private var nonReconnus: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            let liste = fichiers.filter { $0.tmdbID == nil && correspond($0.titre + " " + $0.nomFichier) }
            if liste.isEmpty {
                Text("Toutes les vidéos sont reconnues.").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Vidéos sans titre TMDB sûr : renomme-les « Titre (Année) » pour les faire reconnaître.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(liste) { fichier in
                Button { fichierChoisi = fichier } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "film").foregroundStyle(.secondary).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fichier.nomFichier).font(.subheadline).lineLimit(2)
                            Text("\(fichier.dossier) · \(ByteCountFormatter.string(fromByteCount: fichier.tailleOctets, countStyle: .file))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(Theme.accent)
                    }
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// « Séries 15 » : le nombre de titres du rayon, pour voir d'un coup d'œil ce que l'analyse a trouvé.
    /// Les rayons qui ont quelque chose, plus celui qu'on regarde : un dossier supprimé sur le NAS sort du menu
    /// dès l'analyse suivante, au lieu d'y laisser une case vide.
    /// Les cases du sélecteur : les rayons qui ont quelque chose, « Non reconnus » à part (il a sa puce).
    private var rayonsMontres: [Rayon] {
        let pleins = Rayon.allCases.filter { $0 != .nonReconnus && compte($0) > 0 }
        return pleins.isEmpty ? [.films] : pleins
    }

    private func compte(_ rayon: Rayon) -> Int {
        switch rayon {
        case .nonReconnus: fichiers.filter { $0.tmdbID == nil }.count
        // L'option décochée, le rayon n'existe pas ; cochée mais pas encore lue, il s'affiche quand même.
        case .perso: etat.videosPerso.actif ? max(etat.videosPerso.albums.count, 1) : 0
        default: oeuvres(du: rayon).count
        }
    }

    private func libelle(_ rayon: Rayon) -> String {
        // « Vidéos » dit le nombre de souvenirs, pas un nombre de titres TMDB.
        if rayon == .perso { return etat.videosPerso.albums.isEmpty ? "Vidéos" : "Vidéos \(etat.videosPerso.albums.count)" }
        let nombre = compte(rayon)
        return nombre == 0 ? rayon.rawValue : "\(rayon.rawValue) \(nombre)"
    }

    private func oeuvres(du rayon: Rayon) -> [OeuvreNAS] {
        let retenus = fichiers.filter { fichier in
            guard fichier.tmdbID != nil, correspond(fichier.titre) else { return false }
            switch rayon {
            case .films: return fichier.type == .film
            case .series: return fichier.type == .serie
            case .nouveautes: return fichier.dossier == "NEW"
            case .perso, .nonReconnus: return false
            }
        }
        return OeuvreNAS.regrouper(retenus)
    }

    /// Les nouveautés dont l'analyse n'a pas gardé l'image de fond.
    private var referencesNouveautes: [ReferenceTitre] {
        Array(Set(fichiers.filter { $0.dossier == "NEW" && $0.cheminFond == nil }.compactMap(\.reference))).sorted { $0.tmdbID < $1.tmdbID }
    }

    private func correspond(_ texte: String) -> Bool {
        recherche.isEmpty || texte.localizedStandardContains(recherche)
    }

    private func analyser() {
        Task { await etat.nas.analyser(contexte: contexte, tmdb: etat.tmdb) }
    }
}


extension OeuvreNAS {
    /// La ligne orange de la carte : ce que le NAS en dit — « Sur ton NAS · 4K ».
    var accroche: String {
        ["Sur ton NAS", nouveaute ? "NEW" : nil, qualite].compactMap { $0 }.joined(separator: " · ")
    }

    /// Sous le titre : le type, l'année, la note, le nombre d'épisodes.
    var faits: [String] {
        var morceaux: [String] = []
        if reference?.type == .serie { morceaux.append(Format.pluriel(fichiers.count, "épisode")) }
        if let annee { morceaux.append(String(annee)) }
        if nombreVotes > 0 {
            morceaux.append("★ " + noteMoyenne.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_CH"))))
        }
        return morceaux
    }

    /// « 12 épisodes », « 2019 · ★ 7,8 ».
    var detail: String {
        if reference?.type == .serie {
            return Format.pluriel(fichiers.count, "épisode")
        }
        let note = nombreVotes > 0 ? "★ " + noteMoyenne.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_CH"))) : nil
        let morceaux = [annee.map(String.init), note].compactMap { $0 }
        return morceaux.isEmpty ? " " : morceaux.joined(separator: " · ")
    }
}

/// Un titre du NAS en grande carte 16/9 : la carte commune de l'app (6.4), donc le ▶︎ qui lance le film et les
/// logos « où regarder ». Jusqu'ici cette page dessinait ses propres cartes, sans bouton de lecture : sur la page
/// même du NAS, un film ne se lançait pas (parcours du 23 septembre).
struct CarteLargeNAS: View {
    let oeuvre: OeuvreNAS
    let decor: EtatDecors.Decor?
    let marque: MarqueListe?

    var body: some View {
        let carte = CarteLargeTitre(
            reference: oeuvre.reference,
            titre: oeuvre.titre,
            cheminFond: oeuvre.fichiers.compactMap(\.cheminFond).first ?? decor?.fond,
            cheminAffiche: oeuvre.cheminAffiche,
            accroche: oeuvre.accroche,
            faits: oeuvre.faits,
            symboleCoin: marque == .dansTaListe ? "bookmark.fill" : (marque == .dejaVu ? "eye.fill" : nil),
            // L'accroche dit déjà le NAS et la qualité : inutile de répéter la source derrière.
            ouApresAccroche: false
        )
        if let reference = oeuvre.reference {
            NavigationLink(value: reference) { carte }
                .buttonStyle(.plain)
                .menuSoiree(TitreChoisi(reference: reference, titre: oeuvre.titre, cheminAffiche: oeuvre.cheminAffiche))
        } else {
            carte
        }
    }
}

/// Feuille d'une vidéo non reconnue : son nom, son dossier et la lecture.
private struct FeuilleFichierNAS: View {
    let fichier: FichierNAS

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(fichier.nomFichier).font(.headline)
            LabeledContent("Dossier", value: fichier.dossier)
            LabeledContent("Taille", value: ByteCountFormatter.string(fromByteCount: fichier.tailleOctets, countStyle: .file))
            if let qualite = fichier.qualite {
                LabeledContent("Qualité", value: qualite)
            }
            BoutonLectureNAS(fichier: fichier, grand: true)
            Spacer()
        }
        .padding(24)
        .presentationBackground(Theme.fond)
    }
}
