import SeanceKit
import SwiftUI

/// Les vidéos personnelles sur la TV (EF-159), en albums de souvenirs comme sur l'iPhone (6.2) : un dossier d'événement
/// est un album, une vidéo seule se lance d'un clic ; rangés par année, en grandes cartes à icône. Les couvertures se
/// choisissent sur l'iPhone, l'iPad ou le Mac, et arrivent ici par la synchronisation.
struct VideosPersoTV: View {
    var chemin = ""

    @Environment(EtatTV.self) private var etat
    @Environment(\.openURL) private var ouvrir

    private let colonnes = Array(repeating: GridItem(.fixed(CarteLargeTV.largeurGrille), spacing: 40, alignment: .top), count: 3)

    var body: some View {
        let albums = etat.videosPerso.albums
        let album = albums.first { $0.id == chemin }
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                Text(chemin.isEmpty ? "Vidéos personnelles" : album?.titre ?? (chemin as NSString).lastPathComponent)
                    .font(.system(size: 58, weight: .heavy))
                if albums.isEmpty {
                    VideTV(symbole: "video", titre: etat.videosPerso.enCours ? "Lecture de tes vidéos…" : "Aucune vidéo pour l'instant",
                           message: etat.videosPerso.erreur ?? "Le NAS n'a pas encore été lu, ou ses dossiers de vidéos sont vides.")
                }
                if chemin.isEmpty {
                    ForEach(ArbreVideosPerso.parAnnee(albums), id: \.titre) { section in
                        VStack(alignment: .leading, spacing: 18) {
                            Text(section.titre).font(.system(size: 38, weight: .bold))
                            LazyVGrid(columns: colonnes, alignment: .leading, spacing: 40) {
                                ForEach(section.albums) { carte($0) }
                            }
                        }
                        .focusSection()
                    }
                } else if let album {
                    Text([album.periode, album.videos.count > 1 ? "\(album.videos.count) vidéos" : "1 vidéo"]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 28)).foregroundStyle(.secondary)
                    LazyVGrid(columns: colonnes, alignment: .leading, spacing: 40) {
                        ForEach(album.videos) { video in
                            let choisie = etat.videosPerso.couvertures.couverture(video.chemin)
                            Button { lire(video) } label: {
                                CarteLargeTV(surtitre: (choisie?.date ?? video.modifieLe).map(Self.date), titre: choisie?.titre ?? video.nom,
                                             detail: Self.taille(video.taille), cheminImage: nil, largeur: CarteLargeTV.largeurGrille,
                                             icone: ArbreVideosPerso.symbole(de: video, dans: album, couvertures: etat.videosPerso.couvertures),
                                             lectureEnCoin: true)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .focusSection()
                }
            }
            .padding(.horizontal, MargesTV.bord)
            .padding(.vertical, 40)
        }
        .task { await etat.videosPerso.lire(films: etat.nas) }
    }

    /// Un album s'ouvre ; une vidéo seule se lance d'un clic.
    @ViewBuilder
    private func carte(_ album: AlbumSouvenirs) -> some View {
        let carte = CarteLargeTV(surtitre: album.periode, titre: album.titre,
                                 detail: album.estVideoSeule ? Self.taille(album.taille) : (album.videos.count > 1 ? "Album · \(album.videos.count) vidéos" : "Album · 1 vidéo"),
                                 cheminImage: nil, largeur: CarteLargeTV.largeurGrille, icone: album.symbole, lectureEnCoin: album.estVideoSeule)
        if album.estVideoSeule, let video = album.videos.first {
            Button { lire(video) } label: { carte }.buttonStyle(.card)
        } else {
            NavigationLink(value: DossierVideosTV(chemin: album.id)) { carte }.buttonStyle(.card)
        }
    }

    /// L'app choisie dans Réglages › Lecture, puis l'autre si elle ne s'ouvre pas (6.2).
    private func lire(_ video: VideoPerso) {
        let prefere = etat.lecteur
        let autre: LecteurVideo = prefere == .vlc ? .infuse : .vlc
        func essayer(_ lecteurs: [LecteurVideo]) {
            guard let lecteur = lecteurs.first else {
                return etat.dire("Ni Infuse ni VLC n'ont pu ouvrir cette vidéo : installe VLC sur l'Apple TV, il lit tous les formats.")
            }
            guard let lien = etat.videosPerso.lien(pour: video, films: etat.nas, lecteur: lecteur) else {
                return etat.dire("Le mot de passe de cet accès manque : vois Réglages › Vidéos personnelles.")
            }
            ouvrir(lien) { accepte in
                if !accepte { essayer(Array(lecteurs.dropFirst())) }
            }
        }
        essayer([prefere, autre])
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "fr_CH")))
    }

    static func taille(_ octets: Int64) -> String? {
        octets > 0 ? ByteCountFormatter.string(fromByteCount: octets, countStyle: .file) : nil
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
                         + "Elles s'ouvrent dans le lecteur choisi dans Réglages › Lecture ; n'ayant pas de fiche TMDB, elles passent par leur adresse.")
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
