import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Bouton « Lire » (EF-74) : ouvre la vidéo dans l'app choisie dans les réglages ; le menu propose
/// l'autre. Infuse et VLC lisent directement sur le NAS, sans copie sur l'iPhone.
struct BoutonLectureNAS: View {
    let fichier: FichierNAS
    var libelle = "Lire"
    var grand = false

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
            .accessibilityLabel(libelle)
        #else
        menu
        #endif
    }

    @ViewBuilder
    private var etiquette: some View {
        if grand {
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
        Menu {
            ForEach(LecteurVideo.allCases) { lecteur in
                Button("Lire avec \(lecteur.nom)", systemImage: "play.fill") { lire(avec: lecteur) }
            }
        } label: {
            etiquette
        } primaryAction: {
            lire(avec: etat.nas.lecteur)
        }
        .accessibilityLabel(libelle)
        .alert("\(absent?.nom ?? "") n'est pas installée", isPresented: Binding { absent != nil } set: { if !$0 { absent = nil } }) {
            if let absent {
                Button("Ouvrir l'App Store") { openURL(absent.appStore) }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Installe-la depuis l'App Store, ou choisis l'autre app dans Réglages › NAS.")
        }
        .alert("Mot de passe du NAS manquant", isPresented: $sansMotDePasse) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("VLC en a besoin pour lire sur le NAS. Enregistre-le dans Réglages › NAS.")
        }
        .alert("Infuse ne connaît pas ce fichier", isPresented: $inconnuDInfuse) {
            Button("Lire avec VLC") { lire(avec: .vlc) }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Infuse ne s'ouvre directement que sur un film ou un épisode reconnu. VLC peut lire le fichier tel quel.")
        }
    }

    private func lire(avec lecteur: LecteurVideo) {
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
                                   conseil: "Vérifie que \(lecteur.nom) est installée, ou choisis l'autre app dans Réglages › NAS.")
            }
        }
    }
}

/// Bloc « Sur ton NAS » de la fiche : la copie d'un film, ou les épisodes d'une série par saison.
struct SectionNASFiche: View {
    @Query private var fichiers: [FichierNAS]
    @State private var saison: Int?

    init(reference: ReferenceTitre) {
        let id = reference.tmdbID
        let type = reference.type.rawValue
        _fichiers = Query(filter: #Predicate<FichierNAS> { $0.tmdbID == id && $0.typeBrut == type }, sort: \FichierNAS.chemin)
    }

    var body: some View {
        if !fichiers.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                TitreSection(titre: "Sur ton NAS") {
                    Image(systemName: "externaldrive.fill").foregroundStyle(Theme.accent)
                }
                if fichiers.contains(where: { $0.episode != nil }) {
                    episodes
                } else {
                    ForEach(fichiers) { fichier in
                        ligne(fichier, titre: fichier.qualite.map { "Copie \($0)" } ?? "Copie sur le NAS")
                    }
                }
            }
        }
    }

    private var saisons: [Int] {
        Set(fichiers.compactMap(\.saison)).sorted()
    }

    @ViewBuilder
    private var episodes: some View {
        let choisie = saison ?? saisons.last
        if saisons.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(saisons, id: \.self) { numero in
                        PuceFiltre(libelle: "Saison \(numero)", active: numero == choisie) { saison = numero }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        let liste = fichiers
            .filter { $0.saison == choisie }
            .sorted { ($0.episode ?? 0) < ($1.episode ?? 0) }
        ForEach(liste) { fichier in
            ligne(fichier, titre: fichier.episode.map { "Épisode \($0)" } ?? fichier.nomFichier)
        }
    }

    private func ligne(_ fichier: FichierNAS, titre: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titre).font(.subheadline.weight(.semibold))
                Text([fichier.qualite, ByteCountFormatter.string(fromByteCount: fichier.tailleOctets, countStyle: .file), fichier.dossier]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            BoutonLectureNAS(fichier: fichier)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 20)
    }
}
