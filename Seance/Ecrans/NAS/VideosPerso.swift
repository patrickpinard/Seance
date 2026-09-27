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
    /// Intégrée au rayon « Perso » de la page NAS (6.3) : le défilement, le titre et la barre sont ceux de cette page.
    var integree = false

    @Environment(EtatApp.self) private var etat
    @Environment(\.openURL) private var ouvrir
    /// Rangement et sections repliables des souvenirs (8.2.15), comme les films et les séries.
    @AppStorage("videos.rangement") private var rangementSouvenirs = "Année"
    @State private var sectionsSouvenirs = SectionsRepliables()
    @State private var illisible: VideoPerso?
    /// La vidéo ouverte dans le lecteur de Séance (Réglages › Vidéos personnelles).
    @State private var aLire: VideoPerso?
    @State private var aCouvrir: CibleCouverture?
    /// La vidéo confiée au moteur de VLC (6.5), quand le lecteur d'Apple ne sait pas la lire.
    @State private var aLireAvecVLC: VideoPerso?
    /// Quarante souvenirs, une carte par écran : on cherche par le nom (6.4).
    @State private var recherche = ""

    /// Deux colonnes sur l'iPhone : une carte pleine largeur par écran demandait quarante écrans de défilement.
    static var colonnesSouvenirs: [GridItem] {
        [GridItem(.adaptive(minimum: 168, maximum: 260), spacing: 12, alignment: .top)]
    }

    var body: some View {
        let albums = etat.videosPerso.albums
        Group {
            if integree {
                contenu(albums)
            } else {
                ScrollView { contenu(albums) }
                    .background(Theme.fond)
                    .navigationTitle(titrePage(albums))
                    .toolbar { barre(albums) }
                    .searchable(text: $recherche, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Un souvenir")
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
            // Depuis la 6.5, Séance lit tout elle-même : le lecteur d'Apple pour ce qu'il sait lire (le plus léger,
            // avec AirPlay et l'image dans l'image), le moteur de VLC pour le reste — AVI, WMV, MKV, DV.
            if LecteurIntegre.lisible(video.chemin) {
                LecteurIntegre(video: video, acces: etat.videosPerso.reglages.acces,
                               motDePasse: etat.videosPerso.motDePasse(films: etat.nas.reglages) ?? "") { _ in
                    // Le lecteur d'iOS ne sait pas la décoder (6.2) : on repasse par VLC, puis par les apps du dehors.
                    aLire = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(700))
                        aLireAvecVLC = video
                    }
                }
            } else {
                lecteurDeSecours(video)
            }
        }
        .fullScreenCover(item: $aLireAvecVLC) { video in
            lecteurDeSecours(video)
        }
    }

    @ViewBuilder
    private func contenu(_ albums: [AlbumSouvenirs]) -> some View {
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
        .padding(.vertical, integree ? 0 : 16)
    }

    /// La barre de la page : la couverture d'un album, ou relire le NAS.
    @ToolbarContentBuilder
    private func barre(_ albums: [AlbumSouvenirs]) -> some ToolbarContent {
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
        // 8.2.15 (demande de Patrick) : la même présentation que les films et les séries — les pastilles de
        // rangement, et par année des sections qu'on ouvre et qu'on ferme, les plus récentes d'abord.
        if !albums.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["Année", "A→Z"], id: \.self) { mode in
                        PuceFiltre(libelle: mode, active: rangementSouvenirs == mode) { rangementSouvenirs = mode }
                            .accessibilityLabel("Ranger par \(mode)")
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        if rangementSouvenirs == "A→Z" {
            LazyVGrid(columns: Self.colonnesSouvenirs, spacing: 12) {
                ForEach(filtrer(albums).sorted { $0.titre.localizedCaseInsensitiveCompare($1.titre) == .orderedAscending }) { album in
                    carteAlbum(album)
                }
            }
            .padding(.horizontal, 16)
        } else {
            let annees = ArbreVideosPerso.parAnnee(filtrer(albums))
            if annees.count > 1 {
                let titres = annees.map(\.titre)
                let toutes = sectionsSouvenirs.toutesOuvertes(titres)
                HStack {
                    Spacer()
                    Button(toutes ? "Tout fermer" : "Tout ouvrir") {
                        withAnimation(.snappy) { sectionsSouvenirs.toutes(ouvertes: !toutes, titres: titres) }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 44)
                }
                .padding(.horizontal, 20)
            }
            ForEach(annees, id: \.titre) { section in
                EnTeteRepliable(titre: section.titre, detail: Format.pluriel(section.albums.count, "souvenir"),
                                ouverte: sectionsSouvenirs.ouverte(section.titre)) { sectionsSouvenirs.basculer(section.titre) }
                    .padding(.horizontal, 20)
                if sectionsSouvenirs.ouverte(section.titre) {
                    LazyVGrid(columns: Self.colonnesSouvenirs, spacing: 12) {
                        ForEach(section.albums) { album in
                            carteAlbum(album)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
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
        let apercu = album.videos.first { VignettesSouvenirs.possible($0.chemin) }
        let carte = CarteLargeTitre(reference: nil, titre: album.titre, accroche: album.periode,
                                    faits: faits(album), lecture: false, icone: album.symbole,
                                    vignette: apercu.flatMap(vignette), etiquette: album.estVideoSeule ? "VIDÉO" : "ALBUM",
                                    lectureEnCoin: album.estVideoSeule)
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

    /// Le moteur de VLC, ou les apps du dehors là où il n'existe pas (le Mac).
    @ViewBuilder
    private func lecteurDeSecours(_ video: VideoPerso) -> some View {
        #if targetEnvironment(macCatalyst)
        Color.clear.onAppear { aLire = nil; aLireAvecVLC = nil; lireAilleurs(video) }
        #else
        Color.clear.onAppear {
            aLireAvecVLC = nil
            etat.lecture = LectureEnCours(video: video, acces: etat.videosPerso.reglages.acces,
                                          motDePasse: etat.videosPerso.motDePasse(films: etat.nas.reglages) ?? "") { _ in
                Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    lireAilleurs(video)
                }
            }
        }
        #endif
    }

    /// La recherche porte sur le nom de l'album et sur ceux de ses vidéos.
    private func filtrer(_ albums: [AlbumSouvenirs]) -> [AlbumSouvenirs] {
        let cherche = recherche.trimmingCharacters(in: .whitespaces)
        guard !cherche.isEmpty else { return albums }
        return albums.filter { album in
            album.titre.localizedStandardContains(cherche)
                || album.videos.contains { $0.nom.localizedStandardContains(cherche) }
        }
    }

    /// Demande la première image de la vidéo, et la rend si elle est déjà là.
    private func vignette(_ video: VideoPerso) -> Image? {
        etat.videosPerso.vignettes.demander(video, acces: etat.videosPerso.reglages.acces,
                                            motDePasse: etat.videosPerso.motDePasse(films: etat.nas.reglages))
        return etat.videosPerso.vignettes.vignettes[video.chemin]
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
        LazyVGrid(columns: Self.colonnesSouvenirs, spacing: 12) {
            ForEach(album.videos) { video in
                let choisie = etat.videosPerso.couvertures.couverture(video.chemin)
                Button { lire(video) } label: {
                    CarteLargeTitre(reference: nil, titre: choisie?.titre ?? Self.nomLisible(video.nom),
                                    accroche: (choisie?.date ?? video.modifieLe).map(Self.date),
                                    faits: [(video.chemin as NSString).pathExtension.uppercased(), Self.taille(video.taille)].compactMap { $0 }.filter { !$0.isEmpty },
                                    lecture: false, icone: ArbreVideosPerso.symbole(de: video, dans: album, couvertures: etat.videosPerso.couvertures),
                                    vignette: vignette(video), etiquette: "VIDÉO", lectureEnCoin: true)
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
        // 6.5 : le format ne décide plus. Séance ouvre son lecteur, qui choisit le moteur qui convient.
        if etat.videosPerso.reglages.lecteurIntegre, etat.videosPerso.motDePasse(films: etat.nas.reglages) != nil {
            #if targetEnvironment(macCatalyst)
            if LecteurIntegre.lisible(video.chemin) { aLire = video } else { aLireAvecVLC = video }
            #else
            // 8.0 : le lecteur de Séance, le même que pour les films — avec la reprise et l'image dans l'image.
            etat.lectureEnImage = false
            etat.lecture = LectureEnCours(video: video, acces: etat.videosPerso.reglages.acces,
                                          motDePasse: etat.videosPerso.motDePasse(films: etat.nas.reglages) ?? "") { _ in
                Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    lireAilleurs(video)
                }
            }
            #endif
            return
        }
        // Partir ailleurs sans rien dire laissait deviner pourquoi (6.5) : on donne la raison.
        if let raison = raisonDeSortir(video) {
            etat.confirmer(raison, symbole: "arrow.up.forward.app")
        }
        lireAilleurs(video)
    }

    /// Pourquoi cette vidéo ne se lit pas dans Séance, en une phrase pour l'écran.
    private func raisonDeSortir(_ video: VideoPerso) -> String? {
        if !etat.videosPerso.reglages.lecteurIntegre {
            return "« Lire dans Séance » est décoché dans Réglages › Vidéos personnelles."
        }
        if etat.videosPerso.motDePasse(films: etat.nas.reglages) == nil {
            return "Le mot de passe de tes vidéos personnelles manque : vois Réglages › Vidéos personnelles."
        }
        return nil
    }

    /// Hors de Séance : l'app choisie dans Réglages › Lecture, puis l'autre si elle ne s'ouvre pas (pas installée) ;
    /// si aucune ne s'ouvre, l'alerte propose l'App Store.
    private func lireAilleurs(_ video: VideoPerso) {
        let prefere = etat.nas.lecteur
        let autre: LecteurVideo = prefere == .vlc ? .infuse : .vlc
        // Chaque lecteur a plusieurs adresses possibles (6.4) : on les essaie toutes avant de passer au suivant.
        func essayer(_ adresses: [URL], puis lecteurs: [LecteurVideo]) {
            if let adresse = adresses.first {
                ouvrir(adresse) { accepte in
                    if !accepte { essayer(Array(adresses.dropFirst()), puis: lecteurs) }
                }
                return
            }
            guard let lecteur = lecteurs.first else { illisible = video; return }
            let suivantes = etat.videosPerso.liens(pour: video, films: etat.nas.reglages, lecteur: lecteur)
            if suivantes.isEmpty { return essayer([], puis: Array(lecteurs.dropFirst())) }
            essayer(suivantes, puis: Array(lecteurs.dropFirst()))
        }
        essayer([], puis: [prefere, autre])
    }

    /// Le nom du fichier, débarrassé de ce qui ne se lit pas : tirets et soulignés deviennent des espaces (6.4).
    static func nomLisible(_ nom: String) -> String {
        let propre = nom.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return propre.isEmpty ? nom : propre
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
    /// L'image choisie dans la vidéo (8.2), en secondes ; `nil` : celle de Séance.
    @State private var instant: Double?
    @State private var apercus: [(secondes: Double, image: Image)] = []
    @State private var apercusEnCours = false

    /// Une vidéo (pas un album) dont Séance sait tirer des images.
    private var avecImages: Bool {
        cible.etiquette == "VIDÉO" && VignettesSouvenirs.possible(cible.chemin)
    }

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
                                        .font(.title2.weight(.semibold))
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
                    if avecImages { choixImage }
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
            instant = etat.videosPerso.couvertures.entrees[cible.chemin]?.instantImage
        }
        .task { await chargerApercus() }
    }

    /// « Image » (8.2) : six images prises à travers la vidéo ; celle qu'on touche devient sa vignette, partout.
    private var choixImage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Image").font(.headline)
            if apercus.isEmpty {
                Label(apercusEnCours ? "Séance prend des images dans la vidéo…" : "Aucune image n'a pu être lue sur le NAS.",
                      systemImage: apercusEnCours ? "hourglass" : "photo")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(apercus, id: \.secondes) { apercu in
                        let choisie = instant == apercu.secondes
                        Button { instant = apercu.secondes } label: {
                            apercu.image.resizable().scaledToFill()
                                .frame(width: 150, height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(choisie ? Theme.accent : Theme.trait, lineWidth: choisie ? 3 : 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Image à \(PositionsLecture.horodatage(apercu.secondes))")
                        .accessibilityAddTraits(choisie ? .isSelected : [])
                    }
                }
            }
            if instant != nil {
                Button("Revenir à l'image de Séance") { instant = nil }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
        }
    }

    private func chargerApercus() async {
        guard avecImages, let motDePasse = etat.videosPerso.motDePasse(films: etat.nas.reglages) else { return }
        apercusEnCours = true
        defer { apercusEnCours = false }
        apercus = await etat.videosPerso.vignettes.apercus(VideoPerso(chemin: cible.chemin, taille: 0),
                                                          acces: etat.videosPerso.reglages.acces, motDePasse: motDePasse)
    }

    private func valider() {
        let titreChoisi = titre.trimmingCharacters(in: .whitespacesAndNewlines)
        let titreGarde = titreChoisi.isEmpty || titreChoisi == cible.titreParDefaut ? nil : titreChoisi
        if pourToutLAlbum, let album = cible.album {
            // L'icône va à l'album ; la vidéo garde son titre et sa date, et reprend celle de l'album.
            let deLAlbum = etat.videosPerso.couvertures.couverture(album.id)
            etat.videosPerso.choisirCouverture(album.id, symbole: symbole, titre: deLAlbum?.titre, date: deLAlbum?.date)
            etat.videosPerso.choisirCouverture(cible.chemin, symbole: nil, titre: titreGarde, date: avecDate ? date : nil, instantImage: instant)
        } else {
            etat.videosPerso.choisirCouverture(cible.chemin, symbole: symbole, titre: titreGarde, date: avecDate ? date : nil, instantImage: instant)
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
