import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Bouton « Lire » (EF-74) : ouvre la vidéo dans l'app choisie dans Réglages › Lecture, et seulement dans celle-là —
/// ni second bouton, ni menu, ni appui long (demande de Patrick, 20 septembre 2026). Infuse et VLC lisent directement
/// sur le NAS, sans copie sur l'iPhone.
struct BoutonLectureNAS: View {
    let fichier: FichierNAS
    var libelle = "Lire"
    var grand = false
    /// Une ligne entière (un épisode, une copie du film) : la toucher n'importe où lance la lecture.
    var ligne: (titre: String, detail: String)?
    /// Une pastille « où regarder » (page Ce soir) : « Lire sur le NAS », du même dessin que les autres pastilles.
    var pastille = false

    @Environment(EtatApp.self) private var etat
    @Environment(\.openURL) private var openURL
    @State private var absent: LecteurVideo?
    @State private var sansMotDePasse = false
    @State private var inconnuDInfuse = false

    var body: some View {
        #if targetEnvironment(macCatalyst)
        // Sur Mac, un seul choix : le lecteur vidéo par défaut de macOS.
        Button { lire(avec: etat.nas.lecteur) } label: { etiquette }
            .buttonStyle(.plain)
            .accessibilityLabel(ligne.map { "Lire \($0.titre)" } ?? libelle)
        #else
        menu
        #endif
    }

    @ViewBuilder
    private var etiquette: some View {
        if pastille {
            PastilleOuRegarder(symbole: "play.fill", texte: libelle, principale: true)
        } else if let ligne {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ligne.titre).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                    Text(ligne.detail).font(.caption).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                RondIcone(symbole: "play.fill", principal: true, taille: 38)
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else if grand {
            Label(libelle, systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundStyle(.black)
                .background(Theme.degradeAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            RondIcone(symbole: "play.fill", principal: true, taille: 38)
        }
    }

    private var menu: some View {
        Button { lire(avec: etat.nas.lecteur) } label: { etiquette }
        .buttonStyle(.plain)
        .accessibilityLabel(ligne.map { "Lire \($0.titre) avec \(etat.nas.nomLecteur)" } ?? libelle)
        .alert("\(absent?.nom ?? "") n'est pas installée", isPresented: Binding { absent != nil } set: { if !$0 { absent = nil } }) {
            if let absent {
                Button("Ouvrir l'App Store") { openURL(absent.appStore) }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Installe-la depuis l'App Store, ou choisis l'autre app dans Réglages › Lecture.")
        }
        .alert("Mot de passe du NAS manquant", isPresented: $sansMotDePasse) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("VLC en a besoin pour lire sur le NAS. Enregistre-le dans Réglages › NAS.")
        }
        .alert("Infuse ne connaît pas ce fichier", isPresented: $inconnuDInfuse) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Infuse ne s'ouvre directement que sur un film ou un épisode reconnu. VLC, lui, lit le fichier tel quel : tu peux le choisir dans Réglages › Lecture.")
        }
    }

    private func lire(avec lecteur: LecteurVideo) {
        // Dans Séance, par le moteur de VLC (6.6) : sur l'iPad, VLC ouvert de l'extérieur restait bloqué.
        // Sauf si Réglages › Lecture a choisi Infuse.
        #if !targetEnvironment(macCatalyst)
        if etat.nas.dansSeance {
            guard etat.nas.motDePasse != nil else {
                sansMotDePasse = true
                return
            }
            etat.lire(fichier)
            etat.nas.noterLecture(fichier)
            return
        }
        #endif
        let lien: URL
        switch etat.nas.lien(pour: fichier, avec: lecteur) {
        case .pret(let pret):
            lien = pret
        case .motDePasseManquant:
            sansMotDePasse = true
            etat.journal.noter(.lecture, "La lecture n'a pas pu démarrer : mot de passe du NAS manquant.", conseil: "Enregistre-le dans Réglages › NAS.")
            return
        case .titreInconnu:
            inconnuDInfuse = true
            return
        }
        openURL(lien) { acceptee in
            if acceptee {
                etat.nas.noterLecture(fichier)
            } else {
                absent = lecteur
                etat.journal.noter(.lecture, "\(lecteur.nom) n'a pas pu ouvrir la vidéo.",
                                   conseil: "Vérifie que \(lecteur.nom) est installée, ou choisis l'autre app dans Réglages › Lecture.")
            }
        }
    }
}

/// Bloc « Sur ton NAS » de la fiche. Pour un film : sa ou ses copies, à lancer d'un toucher. Pour une série : ce que le
/// NAS contient, saison par saison — les épisodes se lancent depuis la liste « Épisodes », qui est la seule de la fiche.
struct SectionNASFiche: View {
    @Query private var fichiers: [FichierNAS]
    @State private var tousVisibles = false

    init(reference: ReferenceTitre) {
        let id = reference.tmdbID
        let type = reference.type.rawValue
        _fichiers = Query(filter: #Predicate<FichierNAS> { $0.tmdbID == id && $0.typeBrut == type }, sort: \FichierNAS.chemin)
    }

    private var numerotes: [FichierNAS] {
        fichiers.filter { $0.saison != nil && $0.episode != nil }
    }

    var body: some View {
        if !fichiers.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                TitreSection(titre: "Sur ton NAS") {
                    Image(systemName: "externaldrive.fill").foregroundStyle(Theme.accent)
                }
                if numerotes.isEmpty {
                    ForEach(fichiers) { fichier in
                        ligne(fichier, titre: fichier.qualite.map { "Copie \($0)" } ?? "Copie sur le NAS")
                    }
                } else {
                    resumeParSaison
                    // Les vidéos sans numéro d'épisode ne sont pas dans la liste « Épisodes » : elles se lancent d'ici.
                    ForEach(fichiers.filter { $0.saison == nil || $0.episode == nil }) { fichier in
                        ligne(fichier, titre: fichier.nomFichier)
                    }
                }
            }
        }
    }

    /// « Saison 1 · épisodes 1 à 8 · 1080p », une ligne par saison présente sur le NAS.
    private var resumeParSaison: some View {
        let parSaison = Dictionary(grouping: numerotes) { $0.saison ?? 0 }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(parSaison.keys.sorted(), id: \.self) { saison in
                let episodes = Set((parSaison[saison] ?? []).compactMap(\.episode)).sorted()
                let qualite = (parSaison[saison] ?? []).compactMap { $0.qualite.flatMap(QualiteVideo.init(description:)) }.max()?.description
                HStack(spacing: 10) {
                    Text("Saison \(saison)")
                        .font(.subheadline.weight(.bold))
                    Text([Self.plage(episodes), qualite].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
            Label("Lance un épisode avec ▶︎ dans la liste « Épisodes » ci-dessous.", systemImage: "play.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 20)
    }

    /// « épisodes 1 à 8 », « épisodes 1, 2 et 5 », « épisode 3 ».
    static func plage(_ episodes: [Int]) -> String {
        guard let premier = episodes.first, let dernier = episodes.last else { return "" }
        if episodes.count == 1 { return "épisode \(premier)" }
        if dernier - premier + 1 == episodes.count { return "épisodes \(premier) à \(dernier)" }
        if episodes.count <= 6 { return "épisodes " + episodes.map(String.init).formatted(.list(type: .and).locale(Locale(identifier: "fr_CH"))) }
        return "\(episodes.count) épisodes, du \(premier) au \(dernier)"
    }

    /// Toute la ligne lance la lecture, pas seulement la pastille ▶︎ : c'est elle qu'on vise du doigt.
    private func ligne(_ fichier: FichierNAS, titre: String) -> some View {
        let detail = [fichier.qualite, ByteCountFormatter.string(fromByteCount: fichier.tailleOctets, countStyle: .file), fichier.dossier]
            .compactMap { $0 }.joined(separator: " · ")
        return BoutonLectureNAS(fichier: fichier, ligne: (titre, detail))
            .padding(.horizontal, 20)
    }
}
