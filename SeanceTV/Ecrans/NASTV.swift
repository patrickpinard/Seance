import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// La bibliothèque du NAS sur la TV : ce qui se regarde tout de suite, films et séries.
struct NASTV: View {
    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(sort: \FichierNAS.indexeLe, order: .reverse) private var fichiers: [FichierNAS]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 50) {
                if etat.videosPerso.actif {
                    NavigationLink(value: DossierVideosTV()) {
                        TuileTV(titre: "Vidéos personnelles", symbole: "video.fill",
                                valeur: etat.videosPerso.videos.isEmpty ? "Tes films de famille" : "\(etat.videosPerso.videos.count) vidéos")
                    }
                    .buttonStyle(.card)
                    .padding(.horizontal, MargesTV.bord)
                    .focusSection()
                }
                if !etat.nasPret, fichiers.isEmpty {
                    VideTV(symbole: "externaldrive.badge.questionmark", titre: "NAS à configurer",
                           message: "Dans l'onglet Réglages : l'adresse, le partage, les dossiers, ton compte et son mot de passe. Séance lira alors tes films et tes séries.")
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
                etagere("Films", oeuvres.filter { $0.reference.type == .film })
                etagere("Séries", oeuvres.filter { $0.reference.type == .serie })
            }
            .padding(.vertical, 40)
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
                    ForEach(oeuvres, id: \.reference) { oeuvre in
                        NavigationLink(value: oeuvre.reference) {
                            CarteLargeTV(surtitre: oeuvre.qualite, titre: oeuvre.titre, detail: oeuvre.detail,
                                         cheminImage: oeuvre.cheminFond ?? oeuvre.cheminAffiche,
                                         marque: "externaldrive.fill", largeur: CarteLargeTV.largeurGrille, reference: oeuvre.reference)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, MargesTV.bord)
                .padding(.vertical, 20)
            }
            .focusSection()
        }
    }
}
