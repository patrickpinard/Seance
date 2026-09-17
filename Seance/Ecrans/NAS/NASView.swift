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
        case nonReconnus = "Autres"

        var id: String { rawValue }
    }

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(sort: \FichierNAS.titre) private var fichiers: [FichierNAS]
    @State private var rayon = Rayon.films
    @State private var recherche = ""
    @State private var fichierChoisi: FichierNAS?

    @Environment(\.horizontalSizeClass) private var largeurGrille
    /// Affiches plus grandes sur le Mac : 105 points y feraient des timbres-poste.
    private var colonnes: [GridItem] {
        [GridItem(.adaptive(minimum: largeurGrille == .regular ? 150 : 105), spacing: 12, alignment: .top)]
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
                NavigationLink { ReglagesNASView() } label: {
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
                NavigationLink("Configurer le NAS") { ReglagesNASView() }
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
                Picker("Rayon", selection: $rayon) {
                    ForEach(Rayon.allCases) { rayon in
                        Text(libelle(rayon)).tag(rayon)
                    }
                }
                .pickerStyle(.segmented)

                resume
                if let erreur = etat.nas.erreur {
                    MessageEtat(texte: erreur, ton: .probleme, libelleAction: "Réessayer") { analyser() }
                        .padding(.horizontal, -20)
                }

                if rayon == .nonReconnus {
                    nonReconnus
                } else {
                    let oeuvres = oeuvres(du: rayon)
                    if oeuvres.isEmpty {
                        MessageEtat(texte: recherche.isEmpty ? "Rien dans ce rayon." : "Aucun titre ne correspond à « \(recherche) ».",
                                    symbole: "externaldrive")
                            .padding(.horizontal, -20)
                    }
                    LazyVGrid(columns: colonnes, spacing: 18) {
                        ForEach(oeuvres) { oeuvre in
                            CarteOeuvreNAS(oeuvre: oeuvre)
                        }
                    }
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.immediately)
        .searchable(text: $recherche, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Titre")
        .refreshable { await etat.nas.analyser(contexte: contexte, tmdb: etat.tmdb) }
    }

    private var resume: some View {
        HStack(spacing: 6) {
            let reconnus = fichiers.filter { $0.tmdbID != nil }
            Text("\(Set(reconnus.compactMap(\.reference)).count) titres · \(fichiers.count) vidéos")
            if let date = etat.nas.derniereAnalyse {
                Text("· analysé \(date.formatted(.relative(presentation: .named)))")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
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
    private func libelle(_ rayon: Rayon) -> String {
        let nombre = rayon == .nonReconnus ? fichiers.filter { $0.tmdbID == nil }.count : oeuvres(du: rayon).count
        return nombre == 0 ? rayon.rawValue : "\(rayon.rawValue) \(nombre)"
    }

    private func oeuvres(du rayon: Rayon) -> [OeuvreNAS] {
        let retenus = fichiers.filter { fichier in
            guard fichier.tmdbID != nil, correspond(fichier.titre) else { return false }
            switch rayon {
            case .films: return fichier.type == .film
            case .series: return fichier.type == .serie
            case .nouveautes: return fichier.dossier == "NEW"
            case .nonReconnus: return false
            }
        }
        return OeuvreNAS.regrouper(retenus)
    }

    private func correspond(_ texte: String) -> Bool {
        recherche.isEmpty || texte.localizedStandardContains(recherche)
    }

    private func analyser() {
        Task { await etat.nas.analyser(contexte: contexte, tmdb: etat.tmdb) }
    }
}

/// Affiche, badge de qualité, titre et nombre d'épisodes ; toucher ouvre la fiche.
struct CarteOeuvreNAS: View {
    let oeuvre: OeuvreNAS
    var largeur: CGFloat?

    var body: some View {
        let carte = VStack(alignment: .leading, spacing: 4) {
            ImageDistante(url: ImageTMDB.url(oeuvre.cheminAffiche, .affiche))
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    if let qualite = oeuvre.qualite {
                        Text(qualite)
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if oeuvre.nouveaute {
                        Text("NEW")
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 5))
                            .foregroundStyle(.black)
                            .padding(6)
                    }
                }
            Text(oeuvre.titre)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(sousTitre)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: largeur)

        if let reference = oeuvre.reference {
            NavigationLink(value: reference) { carte }
                .buttonStyle(.plain)
        } else {
            carte
        }
    }

    private var sousTitre: String {
        if oeuvre.reference?.type == .serie {
            let n = oeuvre.fichiers.count
            return "\(n) épisode\(n > 1 ? "s" : "")"
        }
        return oeuvre.annee.map(String.init) ?? " "
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
