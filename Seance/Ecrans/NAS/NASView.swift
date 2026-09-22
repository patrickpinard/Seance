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

/// Bibliothèque du NAS (EF-72 à EF-79) : films, séries, dossier NEW et vidéos non reconnues.
struct NASView: View {
    enum Rayon: String, CaseIterable, Identifiable {
        case films = "Films"
        case series = "Séries"
        case nouveautes = "NEW"
        /// Les vidéos personnelles, au même rang que Films et Séries (6.3, demande de Patrick) : on filtre ce que
        /// montre la page au lieu de descendre dans une tuile à part.
        case perso = "Perso"
        /// Pas un rayon mais un entretien : hors du sélecteur, en petite puce sous le résumé.
        case nonReconnus = "Non reconnus"

        var id: String { rawValue }
    }

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(sort: \FichierNAS.titre) private var fichiers: [FichierNAS]
    @Query private var suivis: [Suivi]
    @State private var rayon = Rayon.films
    @State private var recherche = ""
    @State private var fichierChoisi: FichierNAS?

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
        .navigationTitle("Sur ton NAS")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if etat.nas.enCours {
                    ProgressView()
                } else if etat.nas.estConfigure {
                    Button("Analyser", systemImage: "arrow.clockwise") { analyser() }
                }
                NavigationLink(value: DestinationReglage.nas) {
                    Label("Réglages du NAS", systemImage: "gearshape")
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
                        LazyVGrid(columns: CarteLargeTitre.colonnes, spacing: 14) {
                            ForEach(oeuvres) { oeuvre in
                                CarteLargeNAS(oeuvre: oeuvre, decor: oeuvre.reference.flatMap(etat.decors.decor),
                                              marque: oeuvre.reference.flatMap { marques[$0] })
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.immediately)
        // Les images de fond des nouveautés, pour leurs grandes cartes.
        .task(id: referencesNouveautes) { await etat.decors.charger(referencesNouveautes, client: etat.tmdb) }
        .searchable(text: $recherche, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Titre")
        .refreshable { await etat.nas.analyser(contexte: contexte, tmdb: etat.tmdb) }
    }

    private var resume: some View {
        HStack(spacing: 8) {
            let reconnus = fichiers.filter { $0.tmdbID != nil }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Set(reconnus.compactMap(\.reference)).count) titres · \(fichiers.count) vidéos")
                if let date = etat.nas.derniereAnalyse {
                    Text("Analysé \(date.formatted(.relative(presentation: .named)))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            // « Non reconnus » est un travail d'entretien, pas un rayon : une petite puce suffit (6.3).
            let restent = compte(.nonReconnus)
            if restent > 0 || rayon == .nonReconnus {
                PuceFiltre(libelle: rayon == .nonReconnus ? "Revenir aux titres" : "\(restent) non reconnus",
                           active: rayon == .nonReconnus) {
                    rayon = rayon == .nonReconnus ? (rayonsMontres.first ?? .films) : .nonReconnus
                }
                .font(.caption)
            }
        }
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
        // « Perso » dit le nombre de souvenirs, pas un nombre de titres TMDB.
        if rayon == .perso { return etat.videosPerso.albums.isEmpty ? "Perso" : "Perso \(etat.videosPerso.albums.count)" }
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

/// Un titre du NAS en grande carte 16/9, le format unique de l'app : son image, « NEW » s'il vient d'arriver,
/// la qualité, « Sur ton NAS », et si tu l'as dans ta liste ou déjà vu.
struct CarteLargeNAS: View {
    let oeuvre: OeuvreNAS
    let decor: EtatDecors.Decor?
    let marque: MarqueListe?

    var body: some View {
        let carte = Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                // L'analyse du NAS garde déjà l'image de fond ; le cache de décors ne sert que si elle manque.
                ImageDistante(url: ImageTMDB.url(oeuvre.fichiers.compactMap(\.cheminFond).first ?? decor?.fond, .fond)
                              ?? ImageTMDB.url(oeuvre.cheminAffiche, .fond), coins: 0)
            }
            .overlay {
                LinearGradient(stops: [.init(color: .black.opacity(0.45), location: 0), .init(color: .clear, location: 0.35),
                                       .init(color: .black.opacity(0.92), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    if oeuvre.nouveaute {
                        Text("NEW")
                            .font(.caption2.weight(.black))
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(Theme.degradeAccent, in: Capsule())
                            .foregroundStyle(.black)
                    }
                    Spacer(minLength: 4)
                    if let qualite = oeuvre.qualite {
                        Text(qualite)
                            .font(.caption2.weight(.black))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.black.opacity(0.65), in: Capsule())
                    }
                }
                .padding(12)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Sur ton NAS", systemImage: "externaldrive.fill")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.green)
                    Text(oeuvre.titre)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 7) {
                        PastilleType(film: oeuvre.reference?.type != .serie)
                        Text(oeuvre.detail)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)
                        if marque == .dansTaListe {
                            Label("Dans ta liste", systemImage: "bookmark.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Theme.accentClair)
                        } else if marque == .dejaVu {
                            Label("Déjà vu", systemImage: "eye.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                .padding(12)
            }
            .foregroundStyle(.white)
            .surImage()
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(marque == .dansTaListe ? AnyShapeStyle(Theme.degradeAccent) : AnyShapeStyle(.white.opacity(0.1)),
                                  lineWidth: marque == .dansTaListe ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([oeuvre.titre, "nouveau sur ton NAS", oeuvre.detail, oeuvre.qualite].compactMap { $0 }.joined(separator: ", "))

        if let reference = oeuvre.reference {
            NavigationLink(value: reference) { carte }
                .buttonStyle(.plain)
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
