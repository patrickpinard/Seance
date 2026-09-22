import SeanceKit
import SwiftUI

/// Un album de vidéos personnelles, comme destination de navigation (par valeur) ; `chemin` vide : tous les albums.
struct DossierVideosPerso: Hashable {
    var chemin = ""
}

/// Les vidéos personnelles (EF-159), en albums de souvenirs (6.2, piste B choisie par Patrick) : un dossier d'événement
/// est un album, une vidéo seule fait carte à elle seule ; tout est rangé par année, en grandes cartes 16/9 à icône. Un
/// appui long (clic droit sur le Mac) ouvre la feuille « Couverture » : l'icône, le titre, la date.
struct VideosPersoView: View {
    let dossier: DossierVideosPerso

    @Environment(EtatApp.self) private var etat
    @Environment(\.openURL) private var ouvrir
    @State private var illisible: VideoPerso?
    /// La vidéo ouverte dans le lecteur de Séance (Réglages › Vidéos personnelles).
    @State private var aLire: VideoPerso?
    @State private var aCouvrir: CibleCouverture?

    var body: some View {
        let albums = etat.videosPerso.albums
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let erreur = etat.videosPerso.erreur {
                    MessageEtat(texte: erreur, ton: .probleme, libelleAction: "Réessayer") { relire(force: true) }
                }
                if dossier.chemin.isEmpty {
                    racine(albums)
                } else if let album = albums.first(where: { $0.id == dossier.chemin }) {
                    page(album)
                } else {
                    EtatVide(symbole: "rectangle.stack", titre: "Album introuvable",
                             message: "Ce dossier n'est plus sur le NAS, ou il n'a pas encore été relu.",
                             libelleAction: "Relire le NAS", symboleAction: "arrow.clockwise") { relire(force: true) }
                        .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 16)
        }
        .background(Theme.fond)
        .navigationTitle(titrePage(albums))
        .toolbar {
            if !dossier.chemin.isEmpty, let album = albums.first(where: { $0.id == dossier.chemin }) {
                ToolbarItem(placement: .primaryAction) {
                    Button { aCouvrir = cible(album) } label: { Label("Couverture de l'album", systemImage: "pencil") }
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button { relire(force: true) } label: { Label("Relire le NAS", systemImage: "arrow.clockwise") }
                        .disabled(etat.videosPerso.enCours)
                }
            }
        }
        .task { await etat.videosPerso.lire(films: etat.nas.reglages) }
        .sheet(item: $aCouvrir) { cible in
            FeuilleCouverture(cible: cible)
        }
        .alert("Cette vidéo ne s'ouvre pas", isPresented: Binding { illisible != nil } set: { if !$0 { illisible = nil } }) {
            Button("Installer VLC") { ouvrir(LecteurVideo.vlc.appStore) }
            Button("Installer Infuse") { ouvrir(LecteurVideo.infuse.appStore) }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Ni le lecteur de Séance, ni Infuse, ni VLC n'ont pu l'ouvrir. VLC lit tous les formats directement sur le NAS : installe-le, et vérifie que le mot de passe de l'accès est enregistré dans Réglages › Vidéos personnelles.")
        }
        .fullScreenCover(item: $aLire) { video in
            LecteurIntegre(video: video, acces: etat.videosPerso.reglages.acces,
                           motDePasse: etat.videosPerso.motDePasse(films: etat.nas.reglages) ?? "") { _ in
                // Le lecteur d'iOS ne sait pas la lire (6.2) : il se referme, et la vidéo part dans Infuse ou VLC. L'alerte
                // ouverte pendant que le lecteur était à l'écran ne se voyait pas.
                aLire = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    lireAilleurs(video)
                }
            }
        }
    }

    private func titrePage(_ albums: [AlbumSouvenirs]) -> String {
        guard !dossier.chemin.isEmpty else { return "Vidéos personnelles" }
        return albums.first { $0.id == dossier.chemin }?.titre ?? (dossier.chemin as NSString).lastPathComponent
    }

    // MARK: Tous les albums

    @ViewBuilder
    private func racine(_ albums: [AlbumSouvenirs]) -> some View {
        if albums.isEmpty {
            vide
        }
        ForEach(ArbreVideosPerso.parAnnee(albums), id: \.titre) { section in
            HStack(alignment: .firstTextBaseline) {
                Text(section.titre).font(.title2.weight(.bold))
                Spacer()
                Text(Format.pluriel(section.albums.count, "souvenir")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: CarteLargeTitre.colonnes, spacing: 14) {
                ForEach(section.albums) { album in
                    carteAlbum(album)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var vide: some View {
        if etat.videosPerso.enCours {
            ProgressView("Lecture de tes vidéos…").frame(maxWidth: .infinity).padding(.top, 60)
        } else if etat.videosPerso.aConfigurer(films: etat.nas.reglages) {
            EtatVide(symbole: "video.badge.ellipsis", titre: "Accès à terminer",
                     message: "Il manque l'adresse, le partage ou le mot de passe de tes vidéos personnelles.",
                     libelleAction: "Ouvrir le réglage", symboleAction: "gearshape") { etat.ongletDemande = .reglages }
                .padding(.horizontal, 20)
        } else {
            EtatVide(symbole: "video", titre: "Aucune vidéo pour l'instant",
                     message: "Le NAS n'a pas encore été lu, ou ses dossiers de vidéos sont vides.",
                     libelleAction: "Relire le NAS", symboleAction: "arrow.clockwise") { relire(force: true) }
                .padding(.horizontal, 20)
        }
    }

    /// Un album s'ouvre ; une vidéo seule se lance d'un toucher.
    @ViewBuilder
    private func carteAlbum(_ album: AlbumSouvenirs) -> some View {
        let carte = CarteLargeTitre(reference: nil, titre: album.titre, accroche: album.periode,
                                    faits: faits(album), lecture: false, icone: album.symbole,
                                    etiquette: album.estVideoSeule ? "VIDÉO" : "ALBUM", lectureEnCoin: album.estVideoSeule)
        if album.estVideoSeule, let video = album.videos.first {
            Button { lire(video) } label: { carte }
                .buttonStyle(.plain)
                .accessibilityHint("Lit la vidéo")
                .contextMenu { boutonCouverture(album) }
        } else {
            NavigationLink(value: DossierVideosPerso(chemin: album.id)) { carte }
                .buttonStyle(.plain)
                .contextMenu { boutonCouverture(album) }
        }
    }

    private func faits(_ album: AlbumSouvenirs) -> [String] {
        let nombre = album.estVideoSeule ? nil : Format.pluriel(album.videos.count, "vidéo")
        let format = album.estVideoSeule ? album.videos.first.map { ($0.chemin as NSString).pathExtension.uppercased() } : nil
        return [nombre, format, Self.taille(album.taille)].compactMap { $0 }.filter { !$0.isEmpty }
    }

    private func boutonCouverture(_ album: AlbumSouvenirs) -> some View {
        Button { aCouvrir = cible(album) } label: { Label("Couverture…", systemImage: "photo.badge.checkmark") }
    }

    // MARK: Un album

    @ViewBuilder
    private func page(_ album: AlbumSouvenirs) -> some View {
        CarteLargeTitre(reference: nil, titre: album.titre, accroche: ["Album", album.periode].compactMap { $0 }.joined(separator: " · "),
                        faits: faits(album), lecture: false, icone: album.symbole, etiquette: "ALBUM")
            .frame(maxWidth: 620)
            .padding(.horizontal, 16)
            .contextMenu { boutonCouverture(album) }
        Text("Les vidéos").font(.title3.weight(.bold)).padding(.horizontal, 20).accessibilityAddTraits(.isHeader)
        LazyVGrid(columns: CarteLargeTitre.colonnes, spacing: 14) {
            ForEach(album.videos) { video in
                let choisie = etat.videosPerso.couvertures.couverture(video.chemin)
                Button { lire(video) } label: {
                    CarteLargeTitre(reference: nil, titre: choisie?.titre ?? video.nom,
                                    accroche: (choisie?.date ?? video.modifieLe).map(Self.date),
                                    faits: [(video.chemin as NSString).pathExtension.uppercased(), Self.taille(video.taille)].compactMap { $0 }.filter { !$0.isEmpty },
                                    lecture: false, icone: ArbreVideosPerso.symbole(de: video, dans: album, couvertures: etat.videosPerso.couvertures),
                                    etiquette: "VIDÉO", lectureEnCoin: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Lit la vidéo")
                .contextMenu {
                    Button { aCouvrir = cible(video, dans: album) } label: { Label("Couverture…", systemImage: "photo.badge.checkmark") }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: Couverture

    private func cible(_ album: AlbumSouvenirs) -> CibleCouverture {
        let choisie = etat.videosPerso.couvertures.couverture(album.id)
        let nomParDefaut = album.estVideoSeule ? (album.videos.first?.nom ?? album.titre) : (album.id as NSString).lastPathComponent
        return CibleCouverture(chemin: album.id, titreParDefaut: nomParDefaut, titre: choisie?.titre ?? "", symbole: album.symbole,
                               suggestion: IconesSouvenirs.suggerer(album.titre), date: choisie?.date, dateParDefaut: album.fin ?? .now,
                               etiquette: album.estVideoSeule ? "VIDÉO" : "ALBUM", album: nil)
    }

    private func cible(_ video: VideoPerso, dans album: AlbumSouvenirs) -> CibleCouverture {
        let choisie = etat.videosPerso.couvertures.couverture(video.chemin)
        return CibleCouverture(chemin: video.chemin, titreParDefaut: video.nom, titre: choisie?.titre ?? "",
                               symbole: ArbreVideosPerso.symbole(de: video, dans: album, couvertures: etat.videosPerso.couvertures),
                               suggestion: IconesSouvenirs.suggerer(video.nom), date: choisie?.date, dateParDefaut: video.modifieLe ?? .now,
                               etiquette: "VIDÉO", album: album)
    }

    // MARK: Lecture

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
        lireAilleurs(video)
    }

    /// Hors de Séance : l'app choisie dans Réglages › Lecture, puis l'autre si elle ne s'ouvre pas (pas installée) ;
    /// si aucune ne s'ouvre, l'alerte propose l'App Store.
    private func lireAilleurs(_ video: VideoPerso) {
        let prefere = etat.nas.lecteur
        let autre: LecteurVideo = prefere == .vlc ? .infuse : .vlc
        func essayer(_ lecteurs: [LecteurVideo]) {
            guard let lecteur = lecteurs.first else { illisible = video; return }
            guard let lien = etat.videosPerso.lien(pour: video, films: etat.nas.reglages, lecteur: lecteur) else { illisible = video; return }
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

/// Ce que la feuille « Couverture » modifie : un album, ou une vidéo d'un album.
struct CibleCouverture: Identifiable {
    let chemin: String
    let titreParDefaut: String
    let titre: String
    let symbole: String
    let suggestion: String?
    let date: Date?
    let dateParDefaut: Date
    let etiquette: String
    /// Pour une vidéo : son album, dont on peut changer l'icône d'un coup (« Pour tout l'album »).
    let album: AlbumSouvenirs?

    var id: String { chemin }
}

/// La feuille « Couverture » (6.2) : l'icône parmi les vingt-quatre de la charte, le titre et la date ; pour une vidéo
/// d'un album, « Pour tout l'album » donne l'icône à l'album entier. « Rétablir » revient à ce que Séance propose.
struct FeuilleCouverture: View {
    let cible: CibleCouverture

    @Environment(EtatApp.self) private var etat
    @Environment(\.dismiss) private var fermer
    @State private var symbole = IconesSouvenirs.parDefaut
    @State private var titre = ""
    @State private var avecDate = false
    @State private var date = Date.now
    @State private var pourToutLAlbum = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    CarteLargeTitre(reference: nil, titre: titre.isEmpty ? cible.titreParDefaut : titre,
                                    accroche: avecDate ? VideosPersoView.date(date) : nil, lecture: false, icone: symbole,
                                    etiquette: pourToutLAlbum ? "ALBUM" : cible.etiquette)
                        .frame(maxWidth: 520)
                    if let suggestion = cible.suggestion {
                        Label("Proposé d'après le nom : \(IconesSouvenirs.libelle(suggestion))", systemImage: "wand.and.stars")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accentClair)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 14) {
                        ForEach(IconesSouvenirs.toutes) { icone in
                            let choisie = icone.symbole == symbole
                            Button { symbole = icone.symbole } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: icone.symbole)
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundStyle(choisie ? Color.black : Theme.accentClair)
                                        .frame(width: 58, height: 58)
                                        .background(choisie ? AnyShapeStyle(Theme.degradeAccent) : AnyShapeStyle(Theme.accent.opacity(0.16)), in: Circle())
                                    Text(icone.libelle)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(choisie ? Theme.accentClair : Color.secondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(icone.libelle)
                            .accessibilityAddTraits(choisie ? .isSelected : [])
                        }
                    }
                    VStack(spacing: 0) {
                        TextField(cible.titreParDefaut, text: $titre)
                            .accessibilityLabel("Titre")
                            .padding(14)
                        Divider().overlay(Theme.trait)
                        Toggle("Choisir la date", isOn: $avecDate).padding(14).tint(Theme.accent)
                        if avecDate {
                            DatePicker("Date", selection: $date, displayedComponents: .date)
                                .environment(\.locale, Locale(identifier: "fr_CH"))
                                .padding(.horizontal, 14).padding(.bottom, 12)
                                .tint(Theme.accent)
                        }
                        if cible.album != nil {
                            Divider().overlay(Theme.trait)
                            Toggle("Pour tout l'album", isOn: $pourToutLAlbum).padding(14).tint(Theme.accent)
                        }
                    }
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Button(role: .destructive) { retablir() } label: {
                        Label("Rétablir ce que Séance propose", systemImage: "arrow.uturn.backward")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .padding(20)
            }
            .background(Theme.fond)
            .titreDeFeuille("Couverture")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { fermer() } }
                ToolbarItem(placement: .confirmationAction) { Button("OK") { valider() }.accessibilityIdentifier("validerCouverture") }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.fond)
        .onAppear {
            symbole = cible.symbole
            titre = cible.titre
            avecDate = cible.date != nil
            date = cible.date ?? cible.dateParDefaut
        }
    }

    private func valider() {
        let titreChoisi = titre.trimmingCharacters(in: .whitespacesAndNewlines)
        let titreGarde = titreChoisi.isEmpty || titreChoisi == cible.titreParDefaut ? nil : titreChoisi
        if pourToutLAlbum, let album = cible.album {
            // L'icône va à l'album ; la vidéo garde son titre et sa date, et reprend celle de l'album.
            let deLAlbum = etat.videosPerso.couvertures.couverture(album.id)
            etat.videosPerso.choisirCouverture(album.id, symbole: symbole, titre: deLAlbum?.titre, date: deLAlbum?.date)
            etat.videosPerso.choisirCouverture(cible.chemin, symbole: nil, titre: titreGarde, date: avecDate ? date : nil)
        } else {
            etat.videosPerso.choisirCouverture(cible.chemin, symbole: symbole, titre: titreGarde, date: avecDate ? date : nil)
        }
        fermer()
    }

    private func retablir() {
        etat.videosPerso.choisirCouverture(cible.chemin, symbole: nil, titre: nil, date: nil)
        fermer()
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
