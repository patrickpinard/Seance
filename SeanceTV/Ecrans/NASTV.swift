import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Ce que Regarder › NAS montre (8.0) : un rayon à la fois, choisi sous les pastilles.
enum RayonNASTV: String, CaseIterable, Hashable {
    case films = "Films", series = "Séries", documentaires = "Documentaires", videos = "Vidéos"
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
    /// Maquette 8.0, n° 10 : « Ajouts » range par mois d'arrivée, en rangées ; A→Z en grille.
    @State private var parAjouts = true

    private var rayons: [RayonNASTV] {
        RayonNASTV.allCases.filter { rayon in
            switch rayon {
            case .videos: etat.videosPerso.actif
            default: true
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
                HStack {
                    SelecteurTV(selection: $rayon, cases: rayons.map { ($0, nom($0)) }, symbole: symbole)
                    if rayon != .videos {
                        Button { parAjouts.toggle() } label: {
                            Label(parAjouts ? "Ajouts" : "A→Z", systemImage: "arrow.up.arrow.down")
                        }
                        .buttonStyle(LienTV())
                        .padding(.trailing, MargesTV.bord)
                    }
                }
                if rayon == .videos {
                    VideosPersoTV(integree: true)
                } else {
                    bibliotheque
                }
        }
        .onAppear {
            details = UserDefaults.standard.data(forKey: DetailsNAS.cle).flatMap(DetailsNAS.decoder) ?? DetailsNAS()
        }
    }

    private func nom(_ rayon: RayonNASTV) -> String {
        let nombre = rayon == .videos ? etat.videosPerso.videos.count : oeuvres(rayon).count
        return nombre > 0 ? "\(rayon.rawValue) · \(nombre)" : rayon.rawValue
    }

    private func symbole(_ rayon: RayonNASTV) -> String? {
        switch rayon {
        case .films: "film"
        case .series: "tv"
        case .documentaires: "globe.europe.africa"
        case .videos: "video"
        }
    }

    /// Un documentaire se range dans son rayon, pas dans Films ou Séries.
    private func oeuvres(_ rayon: RayonNASTV) -> [OeuvreTV] {
        let documentaire = { (oeuvre: OeuvreTV) in details.genres[oeuvre.reference.tmdbID]?.contains(99) == true }
        switch rayon {
        case .films: return oeuvres.filter { $0.reference.type == .film && !documentaire($0) }
        case .series: return oeuvres.filter { $0.reference.type == .serie && !documentaire($0) }
        case .documentaires: return oeuvres.filter(documentaire)
        case .videos: return []
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
                if parAjouts {
                    ForEach(parMois(oeuvres(rayon)), id: \.titre) { mois in
                        EtagereTV(titre: mois.titre) {
                            ForEach(mois.oeuvres, id: \.reference) { oeuvre in carte(oeuvre, largeur: CarteLargeTV.largeurGrille) }
                        }
                    }
                } else {
                    etagere(rayon.rawValue, oeuvres(rayon))
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

    /// Par mois d'arrivée sur le NAS (la date du fichier, lue à l'analyse), du plus récent au plus ancien.
    private func parMois(_ liste: [OeuvreTV]) -> [(titre: String, oeuvres: [OeuvreTV])] {
        let calendrier = Calendar.current
        let anneeCourante = calendrier.component(.year, from: .now)
        let datees = liste.map { oeuvre -> (OeuvreTV, Date) in
            let chemins = fichiers.filter { $0.reference == oeuvre.reference }.map(\.chemin)
            return (oeuvre, details.ajout(chemins) ?? oeuvre.indexeLe)
        }
        .sorted { $0.1 > $1.1 }
        var groupes: [(titre: String, oeuvres: [OeuvreTV])] = []
        for (oeuvre, date) in datees {
            let format = calendrier.component(.year, from: date) == anneeCourante ? "LLLL" : "LLLL yyyy"
            let formateur = DateFormatter()
            formateur.locale = Locale(identifier: "fr_CH")
            formateur.dateFormat = format
            let titre = formateur.string(from: date).capitalized(with: Locale(identifier: "fr_CH"))
            if groupes.last?.titre == titre { groupes[groupes.count - 1].oeuvres.append(oeuvre) } else { groupes.append((titre, [oeuvre])) }
        }
        return groupes
    }
}
