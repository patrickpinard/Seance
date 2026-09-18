import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Ce que la fiche affiche, qu'il s'agisse d'un film ou d'une série.
struct FicheAffichee {
    var reference: ReferenceTitre
    var titre: String
    var accroche: String?
    var synopsis: String
    var cheminAffiche: String?
    var cheminFond: String?
    var annee: Int?
    var genres: [String]
    var duree: String?
    var pourcentage: Int
    var offres: OffresRegion?
    var casting: [PersonneCasting]
    /// Bandes-annonces et teasers YouTube, en français d'abord.
    var videos: [Video]
    var langueOriginale: String
    var film: FicheFilm?
    var serie: SerieDetail?

    init(film: FicheFilm) {
        reference = film.reference
        titre = film.titre
        accroche = film.accroche
        synopsis = film.synopsis
        cheminAffiche = film.cheminAffiche
        cheminFond = film.cheminFond
        annee = film.dateSortie?.annee
        genres = film.genres.map(\.nom)
        duree = film.dureeMinutes.map { "\($0 / 60) h \(String(format: "%02d", $0 % 60))" }
        pourcentage = Int((film.noteMoyenne * 10).rounded())
        offres = film.fournisseurs?.offres()
        casting = film.casting?.principaux(15) ?? []
        videos = film.videos?.bandesAnnonces ?? []
        langueOriginale = film.langueOriginale
        self.film = film
    }

    init(serie: SerieDetail) {
        reference = serie.reference
        titre = serie.nom
        synopsis = serie.synopsis
        cheminAffiche = serie.cheminAffiche
        cheminFond = serie.cheminFond
        annee = serie.saisons.compactMap(\.dateDiffusion).min()?.annee
        genres = serie.genres.map(\.nom)
        duree = "\(serie.nombreSaisons) saison\(serie.nombreSaisons > 1 ? "s" : "")"
        pourcentage = Int((serie.noteMoyenne * 10).rounded())
        offres = serie.fournisseurs?.offres()
        casting = serie.casting?.principaux(15) ?? []
        videos = serie.videos?.bandesAnnonces ?? []
        langueOriginale = serie.langueOriginale
        self.serie = serie
    }
}

struct FicheView: View {
    let reference: ReferenceTitre
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @State private var fiche: FicheAffichee?
    @State private var erreur: String?

    var body: some View {
        Group {
            if let fiche {
                ContenuFiche(fiche: fiche)
            } else if let erreur {
                ContentUnavailableView {
                    Label("Fiche indisponible", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(erreur)
                } actions: {
                    Button("Réessayer") {
                        self.erreur = nil
                        Task { await charger() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
            }
        }
        .background(Theme.fond)
        .task(id: reference) { await charger() }
    }

    private func charger() async {
        guard let client = etat.tmdb else {
            erreur = "Enregistre d'abord ta clé TMDB dans Réglages › TMDB."
            return
        }
        do {
            switch reference.type {
            case .film:
                fiche = FicheAffichee(film: try await client.film(reference.tmdbID))
            case .serie:
                fiche = FicheAffichee(serie: try await client.serie(reference.tmdbID, complements: [.casting, .fournisseurs, .videos]))
            }
        } catch is CancellationError {
            return
        } catch {
            erreur = Journal.conseil(error) ?? "TMDB ne répond pas pour l'instant."
            etat.journal.noter(.tmdb, "Une fiche n'a pas pu être chargée.", erreur: error)
        }
    }
}

private struct ContenuFiche: View {
    let fiche: FicheAffichee
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @State private var etatDisponibilite: EtatDisponibilite = .introuvable
    @State private var suivi: Suivi?
    @State private var vu = false
    /// « Vu le 17 septembre 2026 » ou « Déjà vu avant » : le titre du menu de l'œil.
    @State private var detailVu = "Vu"
    @State private var videoChoisie: Video?
    @State private var dansSoiree = false

    @Environment(\.horizontalSizeClass) private var largeur
    /// Largeur réelle : une fenêtre de Mac étroite reste « regular » mais n'a pas la place pour deux colonnes.
    @State private var largeurDisponible: CGFloat = 1200
    @State private var synopsisComplet = false
    /// L'image de fond passée : la barre de navigation prend un fond, sinon le bouton retour flotte sur le contenu.
    @State private var defile = false

    /// Le point de vue « où regarder » d'un film absent des plateformes : au cinéma, bientôt, ou pas encore en streaming.
    private var sortie: EtatSortie? {
        guard let film = fiche.film else { return nil }
        return EtatSortie.etat(dates: film.datesDeSortie, dateMondiale: film.dateSortie, aujourdhui: DateTMDB(.now))
    }

    /// Et pour une série : épisode du jour, prochain épisode, chaîne qui la diffuse.
    private var diffusion: EtatDiffusionSerie? {
        fiche.serie.map { EtatDiffusionSerie.etat(serie: $0, aujourdhui: DateTMDB(.now)) }
    }

    var body: some View {
        ScrollView {
            Group {
                if largeur == .regular, largeurDisponible >= 900 {
                    deuxColonnes
                } else {
                    uneColonne
                }
            }
            .padding(.bottom, 40)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { largeurDisponible = $0 }
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > 180 } action: { _, nouveau in defile = nouveau }
        .toolbarBackground(defile ? .visible : .hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
        .task { rafraichir() }
        .sheet(item: $videoChoisie) { video in
            LecteurBandeAnnonce(video: video)
        }
    }

    /// iPhone : tout à la suite, les actions et où regarder en premier.
    private var uneColonne: some View {
        VStack(alignment: .leading, spacing: 24) {
            enTete
            actions
            bandeauAlertes
            NoteTitre(fiche: fiche)
            blocOuRegarder
            SectionNASFiche(reference: fiche.reference)
            synopsis
            if let serie = fiche.serie {
                SectionEpisodes(serie: serie)
            }
            SectionBandesAnnonces(videos: fiche.videos) { videoChoisie = $0 }
            casting
            source
        }
    }

    /// Mac et grandes fenêtres : le contenu à gauche, où regarder et le NAS dans une colonne à droite.
    private var deuxColonnes: some View {
        VStack(alignment: .leading, spacing: 24) {
            enTete
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 24) {
                    actions
                    bandeauAlertes
                    NoteTitre(fiche: fiche)
                    synopsis
                    if let serie = fiche.serie {
                        SectionEpisodes(serie: serie)
                    }
                    SectionBandesAnnonces(videos: fiche.videos) { videoChoisie = $0 }
                    casting
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 24) {
                    blocOuRegarder
                    SectionNASFiche(reference: fiche.reference)
                    source
                }
                .frame(width: 360, alignment: .leading)
                .padding(.vertical, 16)
                .background(Theme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.trailing, 20)
            }
        }
    }

    @ViewBuilder
    private var synopsis: some View {
        if !fiche.synopsis.isEmpty || !(fiche.accroche ?? "").isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                TitreSection("Synopsis")
                VStack(alignment: .leading, spacing: 8) {
                    if let accroche = fiche.accroche, !accroche.isEmpty {
                        Text(accroche).italic()
                    }
                    if !fiche.synopsis.isEmpty {
                        Text(fiche.synopsis)
                            .foregroundStyle(.secondary)
                            .lineLimit(synopsisComplet ? nil : 6)
                        if fiche.synopsis.count > 320 {
                            Button(synopsisComplet ? "Réduire" : "Lire la suite") { synopsisComplet.toggle() }
                                .font(.subheadline.weight(.semibold))
                                .tint(Theme.accent)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    @ViewBuilder
    private var casting: some View {
        if !fiche.casting.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                TitreSection("Casting")
                DefilementHorizontal {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(fiche.casting) { personne in
                            NavigationLink(value: ReferencePersonne(id: personne.id, nom: personne.nom)) {
                                CartePersonne(personne: personne)
                            }
                            .buttonStyle(.plain)
                            .help("Voir la fiche de \(personne.nom) : filmographie, vus et pas vus")
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private var source: some View {
        Text("Disponibilités : JustWatch")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 20)
    }

    /// UX-06 : image de fond, affiche, titre, année, genres, durée et anneau de note.
    private var enTete: some View {
        ZStack(alignment: .bottomLeading) {
            ImageDistante(url: ImageTMDB.url(fiche.cheminFond, .fondGrand), coins: 0)
                .frame(height: largeur == .regular ? 420 : 300)
                .clipped()
            LinearGradient(colors: [.clear, Theme.fond.opacity(0.7), Theme.fond], startPoint: .top, endPoint: .bottom)
                .frame(height: largeur == .regular ? 420 : 300)
            HStack(alignment: .bottom, spacing: 16) {
                ImageDistante(url: ImageTMDB.url(fiche.cheminAffiche, .affiche))
                    .frame(width: 110, height: 165)
                    .shadow(radius: 12)
                VStack(alignment: .leading, spacing: 6) {
                    Text(fiche.titre).font(.title2.weight(.heavy)).lineLimit(3)
                    Text([fiche.annee.map(String.init), fiche.duree].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(fiche.genres.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    // EF-67 : ta note à côté de celle de TMDB.
                    HStack(spacing: 10) {
                        AnneauNote(pourcentage: fiche.pourcentage, diametre: 44)
                        BadgeTaNote(reference: fiche.reference)
                    }
                }
            }
            .padding(.horizontal, 20)
            .offset(y: 60)
        }
        .padding(.bottom, 60)
    }

    /// Cloche allumée mais notifications coupées : aucune alerte ne partirait.
    @ViewBuilder
    private var bandeauAlertes: some View {
        if suivi?.alertesActives == true {
            BandeauAlertesCoupees()
                .padding(.horizontal, 20)
        }
    }

    private var blocOuRegarder: some View {
        BlocOuRegarder(etat: etatDisponibilite, sortie: sortie, diffusion: diffusion,
                       alertesActives: suivi?.alertesActives == true && suivi?.masque != true) {
            reglerAlertes(.episodes)
        }
    }

    /// Un bouton d'action et son nom en dessous : les icônes seules ne se comprenaient qu'au survol.
    /// Largeur fixe, sur deux lignes au besoin : avec des libellés à leur taille naturelle, cinq boutons dépassaient
    /// la largeur de l'iPhone et toute la fiche s'élargissait avec eux, coupée des deux côtés.
    private func legende<Contenu: View>(_ texte: String, @ViewBuilder _ contenu: () -> Contenu) -> some View {
        VStack(spacing: 5) {
            contenu()
            Text(texte)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(width: 60, alignment: .top)
                .accessibilityHidden(true)
        }
    }

    /// Actions en icônes : « + » ajoute à « À voir », « − » retire ; l'œil marque vu, aujourd'hui ou avant ; ▶︎ la bande-annonce.
    private var actions: some View {
        // Un titre supprimé des terminés n'est plus dans Mes listes, même s'il reste vu et noté.
        let dansMesListes = suivi.map { !$0.masque } ?? false
        let masque = suivi?.masque == true
        // Cinq boutons de 60 points, quatre espaces de 8 et les marges : 372 points, sous les 393 du plus étroit des iPhone visés.
        return HStack(alignment: .top, spacing: 8) {
            legende(dansMesListes ? "Retirer" : masque ? "Remettre" : "À voir") {
                BoutonIcone(
                    symbole: dansMesListes ? "minus" : "plus",
                    libelle: dansMesListes ? "Retirer de mes listes" : masque ? "Remettre dans Terminés" : "Ajouter à voir",
                    principal: !dansMesListes,
                    actif: dansMesListes,
                    explication: dansMesListes
                        ? "Retirer ce titre de Mes listes, avec ses alertes."
                        : masque
                        ? "Remettre ce titre dans la liste « Terminés »."
                        : "Ajouter à « À voir » dans Mes listes. La cloche 🔔 s'active pour te prévenir des sorties et des nouveaux épisodes."
                ) {
                    basculerAVoir()
                }
            }

            if let film = fiche.film {
                legende(vu ? "Vu" : "Marquer vu") {
                    if vu {
                        boutonDejaVu(film)
                    } else {
                        boutonMarquerVu(film)
                    }
                }
            }

            legende(suivi?.alertesActives == true ? "Alertes" : "Me prévenir") {
                boutonAlertes
            }

            if let video = fiche.videos.first {
                legende("Bande-annonce") {
                    BoutonIcone(symbole: "play.rectangle.fill", libelle: "Bande-annonce",
                                explication: "Voir la bande-annonce, lue en streaming : rien n'est enregistré sur l'appareil.") {
                        videoChoisie = video
                    }
                }
            }
            Spacer(minLength: 0)
            legende("Plus") {
                menuAutres
            }
        }
        .padding(.horizontal, 20)
    }

    /// 👁 Vu ce soir, ou vu il y a longtemps : les deux sortent le film des suggestions,
    /// seul le premier entre dans les statistiques.
    private func boutonMarquerVu(_ film: FicheFilm) -> some View {
        Menu {
            Section("Ne plus me le proposer") {
                Button { marquerVu(film, anterieur: false) } label: {
                    Label("Vu aujourd'hui", systemImage: "eye")
                }
                Button { marquerVu(film, anterieur: true) } label: {
                    Label("Déjà vu avant", systemImage: "clock.arrow.circlepath")
                }
            }
        } label: {
            RondIcone(symbole: "eye")
        }
        .help("Marquer vu : aujourd'hui compte dans tes statistiques ; « déjà vu avant » sort le film des suggestions sans fausser tes heures")
        .accessibilityLabel("Marquer vu")
    }

    /// 👁 Déjà marqué : le menu dit quand, et permet d'annuler une erreur.
    private func boutonDejaVu(_ film: FicheFilm) -> some View {
        Menu {
            Section(detailVu) {
                Button(role: .destructive) {
                    try? ServiceSuivi(contexte: contexte).marquerNonVu(film: film.reference)
                    rafraichir()
                } label: {
                    Label("Marquer comme non vu", systemImage: "eye.slash")
                }
            }
        } label: {
            RondIcone(symbole: "eye.fill", actif: true)
        }
        .help("Tu as vu ce film : il compte dans tes goûts et ne revient plus dans les suggestions. Touche pour annuler.")
        .accessibilityLabel(detailVu)
    }

    /// 🔔 Surveillance du titre : un film se bascule d'un geste ; une série propose ses deux rythmes.
    @ViewBuilder
    private var boutonAlertes: some View {
        let actives = suivi?.alertesActives == true
        if fiche.serie != nil {
            Menu {
                Section("Me prévenir") {
                    Button { reglerAlertes(.episodes) } label: {
                        Label("À chaque épisode", systemImage: actives && suivi?.modeAlertes == .episodes ? "checkmark" : "bell.badge")
                    }
                    Button { reglerAlertes(.saisons) } label: {
                        Label("Aux nouvelles saisons seulement", systemImage: actives && suivi?.modeAlertes == .saisons ? "checkmark" : "bell")
                    }
                    if actives {
                        Button(role: .destructive) { reglerAlertes(nil) } label: {
                            Label("Plus d'alertes", systemImage: "bell.slash")
                        }
                    }
                }
            } label: {
                RondIcone(symbole: actives ? "bell.fill" : "bell", actif: actives)
            }
            .help("Alertes : nouvelles saisons, veille et jour des épisodes, arrivée sur tes plateformes, passages à la télé")
            .accessibilityLabel(actives ? "Alertes activées" : "Me prévenir")
        } else {
            BoutonIcone(symbole: actives ? "bell.fill" : "bell", libelle: actives ? "Alertes activées" : "Me prévenir de la sortie", actif: actives,
                        explication: actives
                            ? "Tu seras prévenu : date de sortie annoncée, la veille, le jour même et arrivée sur tes plateformes. Touche pour couper."
                            : "Être prévenu de la sortie : date annoncée, la veille, le jour même et arrivée sur tes plateformes.") {
                reglerAlertes(actives ? nil : .episodes)
            }
        }
    }

    /// « … » : partager, voir sur TMDB, écarter faute de version française (EF-29).
    private var menuAutres: some View {
        let adresse = URL(string: "https://www.themoviedb.org/\(fiche.reference.type == .film ? "movie" : "tv")/\(fiche.reference.tmdbID)")!
        return Menu {
            Button {
                let service = ServiceSoiree(contexte: contexte)
                if dansSoiree {
                    try? service.retirer(fiche.reference)
                } else {
                    try? service.retenir(fiche.reference, titre: fiche.titre, cheminAffiche: fiche.cheminAffiche)
                }
                rafraichir()
            } label: {
                Label(dansSoiree ? "Retirer de ma soirée" : "Ajouter à ma soirée", systemImage: dansSoiree ? "moon.fill" : "moon.stars")
            }
            ShareLink(item: adresse, subject: Text(fiche.titre)) {
                Label("Partager", systemImage: "square.and.arrow.up")
            }
            Link(destination: adresse) {
                Label("Voir sur TMDB", systemImage: "safari")
            }
            if suivi?.exclusionLangue != true {
                Button(role: .destructive) {
                    try? ServiceSuivi(contexte: contexte).exclureLangue(fiche.reference, titre: fiche.titre)
                    rafraichir()
                } label: {
                    Label("Ni VF ni sous-titres FR", systemImage: "captions.bubble")
                }
            }
        } label: {
            RondIcone(symbole: "ellipsis", taille: 40)
        }
        .help("Ma soirée, partager, voir sur TMDB, écarter faute de version française")
        .accessibilityLabel("Plus d'actions")
    }

    private func reglerAlertes(_ mode: ModeAlerteSerie?) {
        let service = ServiceSuivi(contexte: contexte)
        var cible = suivi
        if cible == nil, mode != nil {
            if let film = fiche.film {
                cible = try? service.suivre(film: film)
            } else if let serie = fiche.serie {
                cible = try? service.suivre(serie: serie)
            }
        }
        guard let cible else { return }
        cible.alertesActives = mode != nil
        if let mode { cible.modeAlertes = mode }
        try? contexte.save()
        rafraichir()
        Task {
            if mode != nil { await etat.alertes.demanderAutorisation() }
            await etat.alertes.planifier(contexte: contexte, tmdb: etat.tmdb)
        }
    }

    private func rafraichir() {
        let suiviService = ServiceSuivi(contexte: contexte)
        suivi = try? suiviService.suivi(fiche.reference)
        let visionnages = (try? suiviService.visionnages(fiche.reference)) ?? []
        vu = !visionnages.isEmpty
        if let dernier = visionnages.last(where: { !$0.anterieur }) {
            detailVu = "Vu le \(dernier.vuLe.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "fr_CH"))))"
        } else {
            detailVu = "Déjà vu avant"
        }
        dansSoiree = (try? ServiceSoiree(contexte: contexte).estRetenu(fiche.reference)) ?? false
        etatDisponibilite = (try? ServiceDisponibilite(contexte: contexte).etat(fiche.reference, offres: fiche.offres)) ?? .introuvable
    }

    private func basculerAVoir() {
        let service = ServiceSuivi(contexte: contexte)
        if let suivi, suivi.masque {
            suivi.masque = false
            try? contexte.save()
            rafraichir()
            return
        }
        if let suivi {
            contexte.delete(suivi)
            try? contexte.save()
        } else if let film = fiche.film {
            _ = try? service.suivre(film: film)
        } else if let serie = fiche.serie {
            _ = try? service.suivre(serie: serie)
        }
        rafraichir()
        // Suivre un titre, c'est vouloir être prévenu : l'autorisation est demandée à ce moment-là (EF-81).
        Task {
            await etat.alertes.demanderAutorisation()
            await etat.alertes.planifier(contexte: contexte, tmdb: etat.tmdb)
        }
    }

    private func marquerVu(_ film: FicheFilm, anterieur: Bool) {
        guard !vu else { return }
        try? ServiceSuivi(contexte: contexte).marquerVu(film: film, anterieur: anterieur)
        rafraichir()
    }
}

/// EF-73 : l'état de disponibilité en tête du bloc « Où regarder ».
private struct BlocOuRegarder: View {
    let etat: EtatDisponibilite
    /// Pour un film introuvable : au cinéma, bientôt, ou pas encore en streaming.
    let sortie: EtatSortie?
    /// Pour une série introuvable : épisode du jour, prochain épisode, chaîne.
    let diffusion: EtatDiffusionSerie?
    let alertesActives: Bool
    let prevenir: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Où regarder").font(.title3.weight(.bold))
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: icone).font(.title3).foregroundStyle(Theme.accent).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(titre).font(.subheadline.weight(.semibold))
                        if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                }
                // Pas encore regardable chez soi : se faire prévenir de l'arrivée en streaming ou des épisodes.
                if case .introuvable = etat, sortie != nil || diffusion != nil {
                    if alertesActives {
                        Label(diffusion == nil ? "Tu seras prévenu de sa sortie" : "Tu seras prévenu des épisodes et de l'arrivée sur tes plateformes",
                              systemImage: "bell.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accentClair)
                    } else {
                        Button(action: prevenir) {
                            Label(diffusion == nil ? "Me prévenir de sa sortie" : "Me prévenir des épisodes et de l'arrivée sur tes plateformes",
                                  systemImage: "bell.badge")
                                .font(.subheadline.weight(.semibold))
                        }
                        .tint(Theme.accent)
                    }
                }
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 20)
    }

    private static func jour(_ date: DateTMDB) -> String {
        date.instant(heure: 12).formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "fr_CH")))
    }

    private var icone: String {
        switch etat {
        case .surNAS: return "externaldrive.fill"
        case .dansAbonnements: return "play.tv.fill"
        case .aLaTeleBientot: return "tv"
        case .aLouerOuAcheter: return "cart"
        case .introuvable:
            switch diffusion {
            case .episodeAujourdhui, .prochainEpisode: return "tv"
            case .commence: return "calendar"
            case .enCours: return "play.tv"
            case .terminee: return "checkmark.circle"
            case nil: break
            }
            switch sortie {
            case .auCinema, .bientotAuCinema: return "film"
            case .sortieNumerique, .aVenir: return "calendar"
            case .pasEncoreEnStreaming: return "hourglass"
            case nil: return "questionmark.circle"
            }
        }
    }

    private var titre: String {
        switch etat {
        case .surNAS: return "Sur le NAS"
        case .dansAbonnements: return "Dans tes abonnements"
        case .aLaTeleBientot: return "À la télé bientôt"
        case .aLouerOuAcheter: return "À louer ou acheter"
        case .introuvable:
            switch diffusion {
            case .episodeAujourdhui(let numero, _): return "Épisode \(numero) diffusé aujourd'hui"
            case .prochainEpisode(let numero, let le, _): return "Prochain épisode \(numero) le \(Self.jour(le))"
            case .commence(let le, _): return "Commence le \(Self.jour(le))"
            case .enCours(let reseau): return reseau.map { "Diffusée sur \($0)" } ?? "Série en cours de diffusion"
            case .terminee: return "Série terminée"
            case nil: break
            }
            switch sortie {
            case .auCinema(let depuis, _): return "Au cinéma depuis le \(Self.jour(depuis))"
            case .bientotAuCinema(let le): return "Au cinéma le \(Self.jour(le))"
            case .sortieNumerique(let le): return "En streaming le \(Self.jour(le))"
            case .aVenir(let le): return "Sortie prévue le \(Self.jour(le))"
            case .pasEncoreEnStreaming: return "Pas encore disponible en Suisse"
            case nil: return "Introuvable légalement en Suisse"
            }
        }
    }

    private var detail: String? {
        switch etat {
        case .surNAS(let qualite): return qualite.map { "Qualité \($0)" }
        case .dansAbonnements(let fournisseurs): return fournisseurs.map(\.nom).joined(separator: ", ")
        case .aLaTeleBientot(let diffusion):
            return "\(diffusion.chaine), \(diffusion.debut.formatted(.dateTime.weekday(.wide).hour().minute()))"
        case .aLouerOuAcheter(let location, let achat):
            return Array(Set((location + achat).map(\.nom))).sorted().joined(separator: ", ")
        case .introuvable:
            if let diffusion {
                let reseau = diffusion.reseau
                switch diffusion {
                case .episodeAujourdhui, .prochainEpisode, .commence:
                    return reseau.map { "Sur \($0) · pas sur tes plateformes suisses" } ?? "Pas sur tes plateformes suisses"
                case .enCours:
                    return "Pas encore sur tes plateformes suisses"
                case .terminee:
                    return reseau.map { "Diffusée sur \($0) · pas sur les plateformes suisses" } ?? "Pas sur les plateformes suisses"
                }
            }
            switch sortie {
            case .auCinema(_, let numerique?): return "En streaming le \(Self.jour(numerique))"
            case .auCinema(_, nil), .bientotAuCinema: return "Sortie en streaming pas encore annoncée"
            case .sortieNumerique, .aVenir: return "Pas encore sur les plateformes suisses"
            case .pasEncoreEnStreaming: return "Ni sur les plateformes, ni en location pour l'instant"
            case nil: return nil
            }
        }
    }
}

private struct CartePersonne: View {
    let personne: PersonneCasting

    var body: some View {
        VStack(spacing: 6) {
            ImageDistante(url: ImageTMDB.url(personne.cheminPortrait, .portrait), coins: 40)
                .frame(width: 80, height: 80)
            Text(personne.nom).font(.caption.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
            if let role = personne.personnage, !role.isEmpty {
                Text(role).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: 90)
    }
}
