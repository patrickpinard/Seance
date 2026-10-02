import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Ce que Regarder › NAS montre (8.0) : un rayon à la fois, choisi sous les pastilles.
enum RayonNASTV: String, CaseIterable, Hashable {
    /// Les mêmes rayons que sur l'iPhone (8.4) : NEW, le dossier des nouveautés, y compris.
    case films = "Films", series = "Séries", documentaires = "Documentaires", nouveautes = "Nouveaux", videos = "Vidéos"
    /// 8.4 : les vidéos sans titre TMDB sûr, à identifier — comme la puce « non reconnus » de l'iPhone.
    case nonReconnus = "Non reconnus"
}

/// Regarder › NAS sur la TV (8.0) : Films · Séries · Documentaires · Vidéos, puis le rayon choisi — la bibliothèque en
/// grille, ou les vidéos personnelles en albums, chacune avec sa première image. Des sections : Regarder les empile
/// dans sa page.
struct SectionsNASTV: View {
    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(sort: \FichierNAS.indexeLe, order: .reverse) private var fichiers: [FichierNAS]
    @State private var rayon = DepartTV.rayon
    /// Les genres des titres, écrits par l'analyse du NAS (6.4) : ce qui fait un documentaire (genre 99).
    @State private var details = DetailsNAS()
    /// 8.2.15 : les mêmes rangements que sur l'iPhone — Ajouts, Année, Genre, A→Z —, en sections qu'on ouvre et qu'on
    /// ferme à la télécommande (par genre, fermées au départ).
    @State private var rangement = "Ajouts"
    @State private var sections = SectionsRepliables()
    @State private var aIdentifier: DemandeIdentification?
    private static let rangements = ["Ajouts", "Année", "Genre", "A→Z"]

    /// 8.7, comme sur l'iPhone : les rayons qui ont quelque chose, plus celui qu'on regarde ; « Non reconnus » est un
    /// bouton au bout de la ligne des rangements, pas un rayon.
    private var rayons: [RayonNASTV] {
        let pleins = RayonNASTV.allCases.filter { choix in
            switch choix {
            case .videos: etat.videosPerso.actif
            case .nonReconnus: false
            default: !oeuvres(choix).isEmpty || choix == rayon
            }
        }
        return pleins.isEmpty ? [.films] : pleins
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
                SelecteurTV(selection: $rayon, cases: rayons.map { ($0, nom($0)) }, symbole: symbole)
                if rayon != .videos {
                    HStack(spacing: 14) {
                        if rayon != .nonReconnus {
                            ForEach(Self.rangements, id: \.self) { mode in
                                Button(mode) {
                                    rangement = mode
                                    sections = SectionsRepliables(ouvertesParDefaut: mode != "Genre")
                                }
                                .buttonStyle(BoutonTV(principal: rangement == mode, hauteur: 60))
                            }
                        }
                        // Comme la puce de l'iPhone : « 1 non reconnu », ou « Revenir aux titres ».
                        if !nonReconnus.isEmpty || rayon == .nonReconnus {
                            Button(rayon == .nonReconnus ? "Revenir aux titres"
                                   : nonReconnus.count > 1 ? "\(nonReconnus.count) non reconnus" : "1 non reconnu") {
                                rayon = rayon == .nonReconnus ? .films : .nonReconnus
                            }
                            .buttonStyle(BoutonTV(principal: rayon == .nonReconnus, hauteur: 60))
                            .padding(.leading, 20)
                        }
                    }
                    .padding(.horizontal, MargesTV.bord)
                    .focusSection()
                }
                if rayon == .videos {
                    VideosPersoTV(integree: true)
                } else if rayon == .nonReconnus {
                    listeNonReconnus
                } else {
                    bibliotheque
                }
        }
        .fullScreenCover(item: $aIdentifier) { demande in IdentificationTV(demande: demande) }
        .onAppear {
            details = UserDefaults.standard.data(forKey: DetailsNAS.cle).flatMap(DetailsNAS.decoder) ?? DetailsNAS()
        }
    }

    private func nom(_ rayon: RayonNASTV) -> String {
        // « Vidéos » compte les albums de souvenirs, comme sur l'iPhone.
        let nombre = rayon == .videos ? etat.videosPerso.albums.count : rayon == .nonReconnus ? nonReconnus.count : oeuvres(rayon).count
        return nombre > 0 ? "\(rayon.rawValue) · \(nombre)" : rayon.rawValue
    }

    private func symbole(_ rayon: RayonNASTV) -> String? {
        switch rayon {
        case .films: "film"
        case .series: "tv"
        case .documentaires: "globe.europe.africa"
        case .nouveautes: "sparkles"
        case .videos: "video"
        case .nonReconnus: "questionmark.square.dashed"
        }
    }

    /// Un documentaire se range dans son rayon, pas dans Films ou Séries.
    private func oeuvres(_ rayon: RayonNASTV) -> [OeuvreTV] {
        let documentaire = { (oeuvre: OeuvreTV) in details.genres[oeuvre.reference.tmdbID]?.contains(99) == true }
        switch rayon {
        case .films: return oeuvres.filter { $0.reference.type == .film && !documentaire($0) }
        case .series: return oeuvres.filter { $0.reference.type == .serie && !documentaire($0) }
        case .documentaires: return oeuvres.filter(documentaire)
        case .nouveautes: return OeuvreTV.regrouper(fichiers.filter { $0.dossier == "NEW" })
        case .videos, .nonReconnus: return []
        }
    }

    /// Les vidéos sans titre TMDB sûr (8.4) : chacune s'identifie parmi ce que TMDB propose.
    private var nonReconnus: [FichierNAS] {
        fichiers.filter { $0.tmdbID == nil }.sorted { $0.nomFichier.localizedStandardCompare($1.nomFichier) == .orderedAscending }
    }

    @ViewBuilder
    private var listeNonReconnus: some View {
        if nonReconnus.isEmpty {
            VideTV(symbole: "checkmark.seal", titre: "Toutes les vidéos sont reconnues", message: "Rien à identifier sur ton NAS.")
        } else {
            SectionTV(explication: "Séance ne rattache une vidéo à TMDB que sans aucun doute : même titre, même année. Choisis le bon titre parmi ses propositions ; il vaudra sur tous tes appareils.") {
                ForEach(nonReconnus) { fichier in
                    LigneTVReglage(titre: fichier.nomFichier,
                                   detail: "\(fichier.dossier) · \(ByteCountFormatter.string(fromByteCount: fichier.tailleOctets, countStyle: .file))",
                                   symbole: "questionmark.square.dashed", desactive: etat.tmdb == nil,
                                   action: { aIdentifier = .nas(chemin: fichier.chemin) }) { BoutTV(forme: .valeur("Identifier")) }
                }
            }
            .padding(.horizontal, MargesTV.bord)
        }
    }

    @ViewBuilder
    private var bibliotheque: some View {
                if !etat.nasPret, fichiers.isEmpty {
                    VideTV(symbole: "externaldrive.badge.questionmark", titre: "NAS à configurer",
                           message: "Dans les Réglages (la roue, en haut) : l'adresse, le partage, les dossiers, ton compte et son mot de passe. Séance lira alors tes films et tes séries.")
                } else if etat.analyseEnCours, fichiers.isEmpty {
                    VStack(spacing: 24) {
                        ProgressView()
                        Text("Lecture du NAS…").font(.system(size: 30)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 160)
                } else if let erreur = etat.erreurNAS, fichiers.isEmpty {
                    VideTV(symbole: "wifi.exclamationmark", titre: "Le NAS ne répond pas", message: erreur)
                } else if oeuvres.isEmpty {
                    VideTV(symbole: "externaldrive", titre: "Bibliothèque vide",
                           message: "Aucune vidéo reconnue dans les dossiers choisis. Vérifie-les dans Réglages.")
                }
                if !oeuvres.isEmpty, oeuvres(rayon).isEmpty {
                    VideTV(symbole: symbole(rayon) ?? "externaldrive", titre: "Aucun titre dans ce rayon",
                           message: rayon == .documentaires ? "Les documentaires se reconnaissent à leur genre sur TMDB, lu à chaque analyse du NAS." : "Rien de reconnu ici sur ton NAS pour l'instant.")
                }
                if rangement == "A→Z" {
                    etagere(rayon.rawValue, oeuvres(rayon).sorted { $0.titre.localizedCaseInsensitiveCompare($1.titre) == .orderedAscending })
                } else {
                    ForEach(tranches(oeuvres(rayon)), id: \.titre) { tranche in
                        VStack(alignment: .leading, spacing: 18) {
                            Button { withAnimation(.snappy) { sections.basculer(tranche.titre) } } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "chevron.right")
                                        .rotationEffect(.degrees(sections.ouverte(tranche.titre) ? 90 : 0))
                                    Text(tranche.titre).font(.system(size: 38, weight: .bold))
                                    Text("\(tranche.oeuvres.count) titre\(tranche.oeuvres.count > 1 ? "s" : "")")
                                        .font(.system(size: 26)).foregroundStyle(Theme.texte2)
                                }
                            }
                            .buttonStyle(LienTV())
                            .padding(.horizontal, MargesTV.bord)
                            if sections.ouverte(tranche.titre) {
                                EtagereTV(titre: "") {
                                    ForEach(tranche.oeuvres, id: \.reference) { oeuvre in carte(oeuvre, largeur: CarteLargeTV.largeurGrille) }
                                }
                            }
                        }
                        .focusSection()
                    }
                }
    }

    private var oeuvres: [OeuvreTV] { OeuvreTV.regrouper(fichiers) }

    @ViewBuilder
    private func etagere(_ titre: String, _ oeuvres: [OeuvreTV]) -> some View {
        if !oeuvres.isEmpty {
            // Une grille plutôt qu'une rangée : la bibliothèque compte des centaines de titres.
            VStack(alignment: .leading, spacing: 18) {
                Text("\(titre) · \(oeuvres.count)").font(.system(size: 38, weight: .bold)).padding(.horizontal, MargesTV.bord)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(CarteLargeTV.largeurGrille), spacing: 40, alignment: .top), count: 3), spacing: 50) {
                    ForEach(oeuvres, id: \.reference) { oeuvre in carte(oeuvre, largeur: CarteLargeTV.largeurGrille) }
                }
                .padding(.horizontal, MargesTV.bord)
                .padding(.vertical, 20)
            }
            .focusSection()
        }
    }

    private func carte(_ oeuvre: OeuvreTV, largeur: CGFloat) -> some View {
        NavigationLink(value: oeuvre.reference) {
            CarteLargeTV(surtitre: oeuvre.origine, titre: oeuvre.titre, detail: oeuvre.detail,
                         cheminImage: oeuvre.cheminFond ?? oeuvre.cheminAffiche,
                         largeur: largeur, lectureEnCoin: true, reference: oeuvre.reference)
        }
        .buttonStyle(.card)
        .menuCarteTV(oeuvre.reference, titre: oeuvre.titre, cheminAffiche: oeuvre.cheminAffiche)
    }

    /// Les sections du rangement choisi : par mois d'arrivée, par année de sortie (la plus récente d'abord), par genre.
    private func tranches(_ liste: [OeuvreTV]) -> [(titre: String, oeuvres: [OeuvreTV])] {
        switch rangement {
        case "Année":
            let annees = Dictionary(grouping: liste) { oeuvre in
                fichiers.first { $0.reference == oeuvre.reference && $0.annee != nil }?.annee
            }
            return annees.keys.sorted { ($0 ?? 0) > ($1 ?? 0) }.map { ($0.map(String.init) ?? "Année inconnue", annees[$0] ?? []) }
        case "Genre":
            let noms = Dictionary((GenresParDefaut.films + GenresParDefaut.series).map { ($0.id, $0.nom) }, uniquingKeysWith: { premier, _ in premier })
            var parGenre: [String: [OeuvreTV]] = [:]
            for oeuvre in liste {
                let genres = details.genres[oeuvre.reference.tmdbID] ?? []
                if genres.isEmpty { parGenre["Autres", default: []].append(oeuvre) }
                for genre in genres { parGenre[noms[genre] ?? "Autres", default: []].append(oeuvre) }
            }
            return parGenre.keys.sorted { $0 == "Autres" ? false : $1 == "Autres" ? true : $0 < $1 }.map { ($0, parGenre[$0] ?? []) }
        default:
            return parMois(liste)
        }
    }

    /// Par mois d'arrivée sur le NAS (la date du fichier, lue à l'analyse), du plus récent au plus ancien.
    private static let moisSeul = formateur("LLLL")
    private static let moisEtAnnee = formateur("LLLL yyyy")

    private static func formateur(_ format: String) -> DateFormatter {
        let formateur = DateFormatter()
        formateur.locale = Locale(identifier: "fr_CH")
        formateur.dateFormat = format
        return formateur
    }

    private func parMois(_ liste: [OeuvreTV]) -> [(titre: String, oeuvres: [OeuvreTV])] {
        let calendrier = Calendar.current
        let anneeCourante = calendrier.component(.year, from: .now)
        // 8.9 : les chemins de chaque titre en un seul passage (un filtre par œuvre coûtait au carré du nombre de
        // fichiers), et deux formats de date gardés au lieu d'un par œuvre.
        let cheminsParTitre = Dictionary(grouping: fichiers.filter { $0.reference != nil }) { $0.reference! }.mapValues { $0.map(\.chemin) }
        let datees = liste.map { oeuvre -> (OeuvreTV, Date) in
            (oeuvre, details.ajout(cheminsParTitre[oeuvre.reference] ?? []) ?? oeuvre.indexeLe)
        }
        .sorted { $0.1 > $1.1 }
        var groupes: [(titre: String, oeuvres: [OeuvreTV])] = []
        for (oeuvre, date) in datees {
            let formateur = calendrier.component(.year, from: date) == anneeCourante ? Self.moisSeul : Self.moisEtAnnee
            let titre = formateur.string(from: date).capitalized(with: Locale(identifier: "fr_CH"))
            if groupes.last?.titre == titre { groupes[groupes.count - 1].oeuvres.append(oeuvre) } else { groupes.append((titre, [oeuvre])) }
        }
        return groupes
    }
}
