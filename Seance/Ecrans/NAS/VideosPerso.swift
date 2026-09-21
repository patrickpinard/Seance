import SeanceKit
import SwiftUI

/// Un dossier de vidéos personnelles, comme destination de navigation (par valeur).
struct DossierVideosPerso: Hashable {
    var chemin = ""
}

/// Les vidéos personnelles (EF-159) : on parcourt les dossiers tels qu'ils sont sur le NAS, le plus récent d'abord.
struct VideosPersoView: View {
    let dossier: DossierVideosPerso

    @Environment(EtatApp.self) private var etat
    @Environment(\.openURL) private var ouvrir
    @State private var illisible: VideoPerso?
    /// La vidéo ouverte dans le lecteur de Séance (Réglages › Vidéos personnelles).
    @State private var aLire: VideoPerso?

    var body: some View {
        let arbre = etat.videosPerso.arbre
        let dossiers = arbre.dossiers(dans: dossier.chemin)
        let videos = arbre.videos(dans: dossier.chemin)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let erreur = etat.videosPerso.erreur {
                    MessageEtat(texte: erreur, ton: .probleme, libelleAction: "Réessayer") { relire(force: true) }
                }
                if dossiers.isEmpty, videos.isEmpty {
                    if etat.videosPerso.enCours {
                        ProgressView("Lecture de tes vidéos…").frame(maxWidth: .infinity).padding(.top, 60)
                    } else if etat.videosPerso.aConfigurer(films: etat.nas.reglages) {
                        EtatVide(symbole: "video.badge.ellipsis", titre: "Accès à terminer",
                                 message: "Il manque l'adresse, le partage ou le mot de passe de tes vidéos personnelles.",
                                 libelleAction: "Ouvrir le réglage", symboleAction: "gearshape") { etat.ongletDemande = .reglages }
                            .padding(.horizontal, 20)
                    } else {
                        EtatVide(symbole: "video", titre: "Aucune vidéo ici",
                                 message: "Ce dossier ne contient pas de vidéo, ou le NAS n'a pas encore été lu.",
                                 libelleAction: "Relire le NAS", symboleAction: "arrow.clockwise") { relire(force: true) }
                            .padding(.horizontal, 20)
                    }
                }
                if !dossiers.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 158, maximum: 320), spacing: 12, alignment: .top)], spacing: 12) {
                        ForEach(dossiers) { sous in
                            NavigationLink(value: DossierVideosPerso(chemin: sous.chemin)) {
                                TuileReglage(titre: sous.nom, symbole: "folder.fill",
                                             valeur: [Format.pluriel(sous.nombre, "vidéo"), sous.plusRecente.map(Self.date)].compactMap { $0 }.joined(separator: " · "))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                if !videos.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(videos) { video in
                            Button { lire(video) } label: { ligne(video) }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 16)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.fond)
        .navigationTitle(dossier.chemin.isEmpty ? "Vidéos personnelles" : (dossier.chemin as NSString).lastPathComponent)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { relire(force: true) } label: { Label("Relire le NAS", systemImage: "arrow.clockwise") }
                    .disabled(etat.videosPerso.enCours)
            }
        }
        .task { await etat.videosPerso.lire(films: etat.nas.reglages) }
        .alert("\(etat.nas.lecteur.nom) n'a pas ouvert cette vidéo", isPresented: Binding { illisible != nil } set: { if !$0 { illisible = nil } }) {
            if let video = illisible, !LecteurIntegre.lisible(video.chemin) {
                Button("Ouvrir dans VLC") {
                    guard let lien = etat.videosPerso.lien(pour: video, films: etat.nas.reglages, lecteur: .vlc) else { return }
                    ouvrir(lien)
                }
            }
            Button("Ouvrir l'App Store") { ouvrir(etat.nas.lecteur.appStore) }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Vérifie qu'elle est installée, et que le mot de passe de l'accès est enregistré dans Réglages › Vidéos personnelles. Une vidéo de famille n'a pas de fiche TMDB : Infuse doit la lire par son adresse, ce qu'il ne sait peut-être pas faire — dans ce cas, choisis VLC dans Réglages › Lecture.")
        }
        .fullScreenCover(item: $aLire) { video in
            LecteurIntegre(video: video, acces: etat.videosPerso.reglages.acces,
                           motDePasse: etat.videosPerso.motDePasse(films: etat.nas.reglages) ?? "") { _ in
                // Format que le lecteur d'iOS ne sait pas ouvrir : l'écran d'appel proposera VLC.
                illisible = video
            }
        }
    }

    private func ligne(_ video: VideoPerso) -> some View {
        HStack(spacing: 12) {
            RondIcone(symbole: "play.fill", principal: true, taille: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(video.nom).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                Text([video.modifieLe.map(Self.date), Self.taille(video.taille)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(minHeight: 44)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lire \(video.nom)")
        .accessibilityAddTraits(.isButton)
    }

    private func relire(force: Bool) {
        Task { await etat.videosPerso.lire(films: etat.nas.reglages, force: force) }
    }

    private func lire(_ video: VideoPerso) {
        // Dans Séance : la vidéo reste sur le NAS et se lit ici même, sans passer la main à une autre app.
        // Un format qu'AVFoundation ne lit pas (.avi, .mkv, .wmv) part directement dans VLC : inutile d'ouvrir
        // un lecteur pour lui annoncer qu'il ne sait pas lire.
        if etat.videosPerso.reglages.lecteurIntegre, LecteurIntegre.lisible(video.chemin),
           etat.videosPerso.motDePasse(films: etat.nas.reglages) != nil {
            aLire = video
            return
        }
        guard let lien = etat.videosPerso.lien(pour: video, films: etat.nas.reglages, lecteur: etat.nas.lecteur) else { illisible = video; return }
        ouvrir(lien) { accepte in if !accepte { illisible = video } }
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "fr_CH")))
    }

    static func taille(_ octets: Int64) -> String? {
        octets > 0 ? ByteCountFormatter.string(fromByteCount: octets, countStyle: .file) : nil
    }
}

/// Réglages › Vidéos personnelles (EF-157) : une case à cocher, puis un accès à part — le même NAS et un autre partage
/// le plus souvent, un autre serveur si on veut.
struct ReglagesVideosPersoView: View {
    @Environment(EtatApp.self) private var etat
    @State private var actif = false
    @State private var lecteurIntegre = true
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
                        // Première fois : on part du NAS des films, il n'y a souvent que le partage à vérifier.
                        if coche, hote.isEmpty { remplir(ReglagesVideosPerso.depuis(etat.nas.reglages).acces) }
                        enregistrer()
                    }
            } footer: {
                Text("Tes films de famille, rangés sur ton NAS à part de ta bibliothèque. Décochée, cette option ne montre rien et ne lit rien. Ces vidéos restent privées : leurs noms ne partent vers aucun service, et elles n'entrent ni dans tes statistiques ni dans tes goûts.")
            }
            if actif {
                Section {
                    TextField("Adresse du serveur", text: $hote).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Partage (video)", text: $partage).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Dossiers, séparés par des virgules (vide : tout le partage)", text: $dossiers).autocorrectionDisabled()
                    TextField("Compte", text: $utilisateur).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(libelleMotDePasse, text: $motDePasse)
                } header: {
                    Text("Où sont-elles ?")
                } footer: {
                    Text(memeCompte ? "Même serveur et même compte que tes films : leur mot de passe sert ici aussi, inutile de le retaper."
                                    : "Autre serveur ou autre compte : donne son mot de passe. Il reste dans le trousseau de cet appareil.")
                }
                Section {
                    Button { tester() } label: {
                        HStack {
                            Text(etat.videosPerso.enCours ? "Lecture du NAS…" : "Enregistrer et lire le NAS")
                            if etat.videosPerso.enCours { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(etat.videosPerso.enCours || hote.isEmpty || partage.isEmpty || utilisateur.isEmpty)
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    if !etat.videosPerso.videos.isEmpty {
                        NavigationLink(value: DossierVideosPerso()) { Label("Voir mes vidéos", systemImage: "video.fill") }
                    }
                } footer: {
                    Text("Une vidéo de famille n'a pas de fiche TMDB : les lecteurs extérieurs doivent la lire par son adresse, ce qu'ils ne font pas toujours.")
                }
                Section {
                    Toggle("Lire dans Séance", isOn: $lecteurIntegre)
                        .onChange(of: lecteurIntegre) { enregistrer() }
                } footer: {
                    Text(lecteurIntegre
                         ? "La vidéo reste sur le NAS et se lit ici même, sans passer par une autre app. Formats lus : MP4, MOV, M4V — ce que filme un iPhone."
                         : "Elles s'ouvrent dans le lecteur choisi dans Réglages › Lecture, Infuse ou VLC.")
                }
            }
        }
        .pageReglages("Vidéos personnelles")
        .onAppear {
            actif = etat.videosPerso.reglages.actif
            lecteurIntegre = etat.videosPerso.reglages.lecteurIntegre
            if etat.videosPerso.reglages.estComplet || actif { remplir(etat.videosPerso.reglages.acces) }
        }
    }

    private var memeCompte: Bool { saisis.partageLeCompte(de: etat.nas.reglages) }
    private var libelleMotDePasse: String {
        etat.videosPerso.aSonMotDePasse ? "Mot de passe (déjà enregistré)" : memeCompte ? "Mot de passe (celui des films)" : "Mot de passe"
    }

    private var saisis: ReglagesVideosPerso {
        let liste = dossiers.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return ReglagesVideosPerso(actif: actif,
                                   acces: ReglagesNAS(hote: hote.trimmingCharacters(in: .whitespaces), partage: partage.trimmingCharacters(in: .whitespaces),
                                                      dossiers: liste, utilisateur: utilisateur.trimmingCharacters(in: .whitespaces)),
                                   lecteurIntegre: lecteurIntegre)
    }

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
            await etat.videosPerso.lire(films: etat.nas.reglages, force: true)
            let nombre = etat.videosPerso.videos.count
            message = etat.videosPerso.erreur ?? (nombre == 0 ? "Connexion réussie, mais aucune vidéo trouvée dans ce partage."
                                                              : "\(Format.pluriel(nombre, "vidéo")) trouvée\(nombre > 1 ? "s" : "").")
        }
    }
}
