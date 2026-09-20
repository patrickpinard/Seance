import SeanceKit
import SwiftUI

/// Les vidéos personnelles sur la TV (EF-159) : les dossiers du NAS en tuiles, les vidéos en lignes, le plus récent d'abord.
struct VideosPersoTV: View {
    var chemin = ""

    @Environment(EtatTV.self) private var etat
    @Environment(\.openURL) private var ouvrir

    var body: some View {
        let arbre = etat.videosPerso.arbre
        let dossiers = arbre.dossiers(dans: chemin)
        let videos = arbre.videos(dans: chemin)
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                Text(chemin.isEmpty ? "Vidéos personnelles" : (chemin as NSString).lastPathComponent).font(.system(size: 58, weight: .heavy))
                if dossiers.isEmpty, videos.isEmpty {
                    VideTV(symbole: "video", titre: etat.videosPerso.enCours ? "Lecture de tes vidéos…" : "Aucune vidéo ici",
                           message: etat.videosPerso.erreur ?? "Ce dossier ne contient pas de vidéo, ou le NAS n'a pas encore été lu.")
                }
                if !dossiers.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(476), spacing: 40, alignment: .top), count: 3), spacing: 40) {
                        ForEach(dossiers) { sous in
                            NavigationLink(value: DossierVideosTV(chemin: sous.chemin)) {
                                TuileTV(titre: sous.nom, symbole: "folder.fill",
                                        valeur: [sous.nombre > 1 ? "\(sous.nombre) vidéos" : "1 vidéo", sous.plusRecente.map(Self.date)].compactMap { $0 }.joined(separator: " · "))
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .focusSection()
                }
                if !videos.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(videos) { video in
                            Button { lire(video) } label: {
                                HStack(spacing: 24) {
                                    Image(systemName: "play.fill").font(.system(size: 28))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(video.nom).font(.system(size: 30, weight: .semibold)).lineLimit(1)
                                        Text([video.modifieLe.map(Self.date), video.taille > 0 ? ByteCountFormatter.string(fromByteCount: video.taille, countStyle: .file) : nil]
                                            .compactMap { $0 }.joined(separator: " · ")).font(.system(size: 23)).opacity(0.7)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 24)
                                .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                            }
                            .buttonStyle(LigneTV())
                        }
                    }
                    .padding(20)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .focusSection()
                }
            }
            .padding(.horizontal, MargesTV.bord)
            .padding(.vertical, 40)
        }
        .task { await etat.videosPerso.lire(films: etat.nas) }
    }

    private func lire(_ video: VideoPerso) {
        guard let lien = etat.videosPerso.lien(pour: video, films: etat.nas) else {
            return etat.dire("Le mot de passe de cet accès manque : vois Réglages › Vidéos personnelles.")
        }
        ouvrir(lien) { accepte in
            if !accepte { etat.dire("Tes vidéos personnelles se lisent avec VLC : installe-le sur cette Apple TV.") }
        }
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "fr_CH")))
    }
}

struct DossierVideosTV: Hashable {
    var chemin = ""
}

/// Réglages › Vidéos personnelles, sur la TV : la même case à cocher et le même accès à part que sur l'iPhone.
struct PageVideosPersoTV: View {
    @Environment(EtatTV.self) private var etat
    @State private var actif = false
    @State private var hote = ""
    @State private var partage = ""
    @State private var dossiers = ""
    @State private var utilisateur = ""
    @State private var motDePasse = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Toggle("Inclure mes vidéos personnelles", isOn: $actif)
                    .onChange(of: actif) { _, coche in
                        if coche, hote.isEmpty { remplir(ReglagesVideosPerso.depuis(etat.nas).acces) }
                        enregistrer()
                    }
            } footer: {
                Text("Tes films de famille, rangés sur ton NAS à part de ta bibliothèque. Décochée, cette option ne montre rien et ne lit rien. Ces vidéos restent privées : leurs noms ne partent vers aucun service.")
            }
            if actif {
                Section {
                    TextField("Adresse du serveur", text: $hote)
                    TextField("Partage (video)", text: $partage)
                    TextField("Dossiers, séparés par des virgules (vide : tout le partage)", text: $dossiers)
                    TextField("Compte", text: $utilisateur)
                    SecureField(etat.videosPerso.aSonMotDePasse ? "Mot de passe (déjà enregistré)" : memeCompte ? "Mot de passe (celui des films)" : "Mot de passe", text: $motDePasse)
                    Button(etat.videosPerso.enCours ? "Lecture du NAS…" : "Enregistrer et lire le NAS") { tester() }
                        .disabled(etat.videosPerso.enCours || hote.isEmpty || partage.isEmpty || utilisateur.isEmpty)
                    if let message { Text(message).foregroundStyle(.secondary) }
                } header: {
                    Text("Où sont-elles ?")
                } footer: {
                    Text((memeCompte ? "Même serveur et même compte que tes films : leur mot de passe sert ici aussi. " : "Autre serveur ou autre compte : donne son mot de passe. ")
                         + "Elles se lisent avec VLC : Infuse n'ouvre par lien que les titres de sa bibliothèque.")
                }
            }
        }
        .navigationTitle("Vidéos personnelles")
        .onAppear {
            actif = etat.videosPerso.reglages.actif
            if etat.videosPerso.reglages.estComplet || actif { remplir(etat.videosPerso.reglages.acces) }
        }
    }

    private var saisis: ReglagesVideosPerso {
        let liste = dossiers.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return ReglagesVideosPerso(actif: actif, acces: ReglagesNAS(hote: hote.trimmingCharacters(in: .whitespaces), partage: partage.trimmingCharacters(in: .whitespaces),
                                                                  dossiers: liste, utilisateur: utilisateur.trimmingCharacters(in: .whitespaces)))
    }
    private var memeCompte: Bool { saisis.partageLeCompte(de: etat.nas) }

    private func remplir(_ acces: ReglagesNAS) {
        hote = acces.hote; partage = acces.partage; utilisateur = acces.utilisateur
        dossiers = acces.dossiers.joined(separator: ", ")
    }

    private func enregistrer() {
        etat.videosPerso.enregistrer(saisis, motDePasse: motDePasse)
        motDePasse = ""
    }

    private func tester() {
        enregistrer()
        message = nil
        Task {
            await etat.videosPerso.lire(films: etat.nas, force: true)
            let nombre = etat.videosPerso.videos.count
            message = etat.videosPerso.erreur ?? (nombre == 0 ? "Connexion réussie, mais aucune vidéo trouvée dans ce partage." : "\(nombre) vidéo\(nombre > 1 ? "s" : "") trouvée\(nombre > 1 ? "s" : "").")
        }
    }
}
