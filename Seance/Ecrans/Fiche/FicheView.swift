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
    @Environment(\.dismiss) private var fermer
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
        // ⌘[ sur le Mac (6.4) : la page ouverte se referme, comme dans toute app Mac.
        .onChange(of: etat.retourDemande) { _, _ in fermer() }
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
    @State private var confirmationSerieTerminee = false

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
                    // La colonne prend la largeur de l'écran, jamais celle de son élément le plus large : une pastille
                    // ou un passage TV un peu long élargissait toute la fiche, qui se retrouvait rognée à gauche.
                    uneColonne
                        .containerRelativeFrame(.horizontal, alignment: .leading)
                }
            }
            .padding(.bottom, 40)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { largeurDisponible = $0 }
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > 180 } action: { _, nouveau in defile = nouveau }
        .toolbarBackground(defile ? .visible : .hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
        .task { rafraichir() }
        // « Annuler » sur le message d'une action (soirée, je n'aime pas) : les boutons de la fiche se remettent d'accord.
        .onChange(of: etat.confirmation == nil) { rafraichir() }
        .sheet(item: $videoChoisie) { video in
            LecteurBandeAnnonce(video: video)
        }
    }

    /// iPhone : tout à la suite, les actions et où regarder en premier.
    private var uneColonne: some View {
        VStack(alignment: .leading, spacing: 24) {
            enTete
            ouEnTete
            actions
            pouces
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
                    ouEnTete
                    actions
                    pouces
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
        BlocOuRegarder(reference: fiche.reference, offres: fiche.offres, etat: etatDisponibilite, sortie: sortie, diffusion: diffusion,
                       alertesActives: suivi?.alertesActives == true && suivi?.masque != true,
                       titreDuFilm: fiche.titre) {
            reglerAlertes(.episodes)
        }
    }

    /// En tête de fiche : où regarder, et y aller d'un toucher. « Lire sur le NAS » lance le film (ou le prochain épisode
    /// de la série) ; avant, la pastille « Sur ton NAS » n'était qu'une étiquette, qu'on touchait pour rien.
    private var ouEnTete: some View {
        // 6.1 : un grand bouton ▶︎ — un seul accès, il le lance ; plusieurs, il demande lequel —, puis le reste en pastilles.
        ActionsOuRegarder(reference: fiche.reference, titre: fiche.titre, episode: prochainEpisode, presentation: .enTete)
            .padding(.horizontal, 20)
    }

    private var prochainEpisode: NumeroEpisode? {
        guard let serie = fiche.serie else { return nil }
        let vus = (try? ServiceSuivi(contexte: contexte).episodesVus(serie.reference)) ?? []
        return ProgressionSerie.suivant(vus: vus, saisons: serie.saisons, dernierDiffuse: serie.dernierEpisode)?.numero
    }

    /// « Ton avis » : dire si le titre te plaît sans l'avoir vu ; la note de 1 à 10 vient après l'avoir regardé.
    private var pouces: some View {
        PoucesTitre(reference: fiche.reference, titre: fiche.titre, cheminAffiche: fiche.cheminAffiche,
                    genres: fiche.film?.genres.map(\.id) ?? fiche.serie?.genres.map(\.id) ?? [],
                    acteursIDs: fiche.casting.prefix(5).map(\.id), acteurs: fiche.casting.prefix(5).map(\.nom))
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

    /// Charte 8.0 : sous l'action principale (regarder, dans « Où regarder »), deux gestes fréquents — Ma liste et Ce
    /// soir — puis « ⋯ » pour le reste. Les mêmes mots et le même ordre sur l'iPhone, l'iPad, le Mac et l'Apple TV.
    private var actions: some View {
        // Un titre supprimé des terminés n'est plus dans Mes listes, même s'il reste vu et noté.
        let dansMesListes = suivi.map { !$0.masque } ?? false
        return HStack(spacing: 10) {
            Button { basculerAVoir() } label: {
                Label(dansMesListes ? "Dans ma liste" : "Ma liste", systemImage: dansMesListes ? "checkmark" : "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(StyleBoutonSecondaire(pleineLargeur: true))
            .accessibilityHint(dansMesListes ? "Retire ce titre de Mes listes, avec ses alertes" : "Ajoute ce titre à « À voir »")
            Button { basculerSoiree() } label: {
                Label("Ce soir", systemImage: dansSoiree ? "moon.stars.fill" : "moon.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(StyleBoutonSecondaire(pleineLargeur: true))
            .accessibilityLabel(dansSoiree ? "Ce soir, choisi" : "Ce soir")
            .accessibilityHint(dansSoiree ? "Retire ce titre de ta soirée" : "Ajoute ce titre à ta soirée de ce soir")
            menuAutres
        }
        .sensoryFeedback(.success, trigger: dansMesListes)
        .sensoryFeedback(.success, trigger: dansSoiree)
        .padding(.horizontal, 20)
        .frame(maxWidth: 720, alignment: .leading)
        .confirmationDialog("Ranger « \(fiche.titre) » dans Terminés ?", isPresented: $confirmationSerieTerminee, titleVisibility: .visible) {
            if let serie = fiche.serie { Button("Terminé") { terminerSerie(serie) } }
        } message: {
            Text("Les épisodes pas encore cochés le seront, à la date d'aujourd'hui.")
        }
    }

    /// ✓ Terminé (6.1) : un toucher, et le film rejoint Terminés, daté d'aujourd'hui — il compte dans tes statistiques.
    /// « Déjà vu avant », à l'appui long, le sort des suggestions sans fausser tes heures.
    private func boutonMarquerVu(_ film: FicheFilm) -> some View {
        BoutonIcone(symbole: "checkmark", libelle: "Terminé",
                    explication: "Terminé : le film rejoint tes Terminés, daté d'aujourd'hui. Appui long : « Déjà vu avant », hors statistiques.") {
            marquerVu(film, anterieur: false)
        }
        .contextMenu {
            Button { marquerVu(film, anterieur: true) } label: {
                Label("Déjà vu avant", systemImage: "clock.arrow.circlepath")
            }
        }
        .accessibilityAction(named: "Déjà vu avant") { marquerVu(film, anterieur: true) }
    }

    /// 👁 Déjà marqué : le menu dit quand, et permet d'annuler une erreur.
    private func boutonDejaVu(_ film: FicheFilm) -> some View {
        Menu {
            Section(detailVu) {
                Button(role: .destructive) {
                    try? ServiceSuivi(contexte: contexte).marquerNonVu(film: film.reference)
                    rafraichir()
                    etat.confirmer("Marqué comme non vu", symbole: "eye.slash")
                } label: {
                    Label("Marquer comme non vu", systemImage: "eye.slash")
                }
            }
        } label: {
            RondIcone(symbole: "checkmark", actif: true)
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
            .help("Alertes : nouvelles saisons, veille et jour des épisodes, arrivée sur tes plateformes, passages à la TV")
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
        let actives = suivi?.alertesActives == true
        return Menu {
            if let film = fiche.film {
                if vu {
                    Button(role: .destructive) {
                        try? ServiceSuivi(contexte: contexte).marquerNonVu(film: film.reference)
                        rafraichir()
                        etat.confirmer("Marqué comme non vu", symbole: "eye.slash")
                    } label: { Label("Pas encore vu", systemImage: "eye.slash") }
                } else {
                    Button { marquerVu(film, anterieur: false) } label: { Label("Terminé", systemImage: "checkmark") }
                    Button { marquerVu(film, anterieur: true) } label: { Label("Déjà vu avant", systemImage: "clock.arrow.circlepath") }
                }
            }
            if let serie = fiche.serie, ProgressionSerie.estFinie(serie), !(suivi?.statut == .termine && suivi?.masque == false) {
                Button { confirmationSerieTerminee = true } label: { Label("Terminé", systemImage: "checkmark") }
            }
            if fiche.serie != nil {
                Menu {
                    Button { reglerAlertes(.episodes) } label: {
                        Label("À chaque épisode", systemImage: actives && suivi?.modeAlertes == .episodes ? "checkmark" : "bell.badge")
                    }
                    Button { reglerAlertes(.saisons) } label: {
                        Label("Aux nouvelles saisons seulement", systemImage: actives && suivi?.modeAlertes == .saisons ? "checkmark" : "bell")
                    }
                    if actives {
                        Button(role: .destructive) { reglerAlertes(nil) } label: { Label("Ne plus me prévenir", systemImage: "bell.slash") }
                    }
                } label: { Label(actives ? "Alertes" : "Me prévenir", systemImage: actives ? "bell.fill" : "bell") }
            } else {
                Button { reglerAlertes(actives ? nil : .episodes) } label: {
                    Label(actives ? "Ne plus me prévenir" : "Me prévenir de la sortie", systemImage: actives ? "bell.slash" : "bell")
                }
            }
            if let video = fiche.videos.first {
                Button { videoChoisie = video } label: { Label("Bande-annonce", systemImage: "play.rectangle") }
            }
            Divider()
            Button { basculerFavori() } label: {
                Label(estFavori ? "Retirer de mes favoris" : "Ajouter à mes favoris", systemImage: estFavori ? "star.fill" : "star")
            }
            Button {
                etat.titreADater = TitreChoisi(reference: fiche.reference, titre: fiche.titre, cheminAffiche: fiche.cheminAffiche)
            } label: {
                Label("Un autre soir…", systemImage: "calendar.badge.clock")
            }
            Button {
                etat.titrePourListe = TitreChoisi(reference: fiche.reference, titre: fiche.titre, cheminAffiche: fiche.cheminAffiche)
            } label: {
                Label("Ajouter à une liste…", systemImage: "list.bullet.rectangle.portrait")
            }
            Divider()
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
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.texte)
                .frame(width: 44, height: 44)
                .background(Theme.eleve, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .help("Terminé, alertes, bande-annonce, favoris, un autre soir, listes, partager")
        .accessibilityLabel("Plus d'actions")
    }

    /// 🌙 Ajoute à la soirée de ce soir ou en retire, et le dit : sans message, rien ne montrait que le geste avait pris.
    private func basculerSoiree() {
        let service = ServiceSoiree(contexte: contexte)
        let reference = fiche.reference
        let titre = fiche.titre
        let affiche = fiche.cheminAffiche
        if dansSoiree {
            try? service.retirer(reference)
            etat.confirmer("« \(titre) » retiré de ta soirée", symbole: "moon") { [contexte] in
                try? ServiceSoiree(contexte: contexte).retenir(reference, titre: titre, cheminAffiche: affiche)
            }
        } else {
            try? service.retenir(reference, titre: titre, cheminAffiche: affiche)
            etat.confirmer("Ajouté à ta soirée de ce soir", symbole: "moon.stars.fill") { [contexte] in
                try? ServiceSoiree(contexte: contexte).retirer(reference)
            }
        }
        rafraichir()
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
        contexte.sauver()
        rafraichir()
        Task {
            if mode != nil { await etat.alertes.demanderAutorisation() }
            await etat.alertes.planifier(contexte: contexte, tmdb: etat.tmdb)
        }
    }

    private func rafraichir() {
        let suiviService = ServiceSuivi(contexte: contexte)
        // 6.1 : une série finie et vue jusqu'au bout avant la règle se range dans Terminés en ouvrant sa fiche.
        if let serie = fiche.serie { try? suiviService.rangerSiTerminee(serie) }
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

    /// ★ Les favoris (EF-165) : une collection à part, ni « À voir » ni « J'aime ».
    private var estFavori: Bool {
        (try? ServiceFavoris(contexte: contexte).estFavori(fiche.reference)) ?? false
    }

    private func basculerFavori() {
        let reference = fiche.reference
        let annee = fiche.annee
        guard let ajoute = try? ServiceFavoris(contexte: contexte).basculer(reference, titre: fiche.titre,
                                                                           cheminAffiche: fiche.cheminAffiche, annee: annee)
        else { return }
        rafraichir()
        etat.confirmer(ajoute ? "★ Ajouté à tes favoris" : "Retiré de tes favoris", symbole: ajoute ? "star.fill" : "star") { [contexte] in
            _ = try? ServiceFavoris(contexte: contexte).basculer(reference, titre: fiche.titre, cheminAffiche: fiche.cheminAffiche, annee: annee)
            rafraichir()
        }
    }

    private func basculerAVoir() {
        let service = ServiceSuivi(contexte: contexte)
        if let suivi, suivi.masque {
            suivi.masque = false
            contexte.sauver()
            rafraichir()
            etat.confirmer("Remis dans Terminés", symbole: "bookmark.fill") { [contexte] in
                suivi.masque = true
                contexte.sauver()
                rafraichir()
            }
            return
        }
        if let suivi {
            let copie = InstantaneSuivi(suivi)
            contexte.delete(suivi)
            contexte.sauver()
            etat.confirmer("« \(fiche.titre) » retiré de Mes listes", symbole: "minus.circle") { [contexte] in
                copie.restaurer(dans: contexte)
                rafraichir()
            }
        } else {
            if let film = fiche.film {
                _ = try? service.suivre(film: film)
            } else if let serie = fiche.serie {
                _ = try? service.suivre(serie: serie)
            }
            let reference = fiche.reference
            etat.confirmer("Ajouté à À voir", symbole: "plus.circle.fill") { [contexte] in
                if let ajoute = try? ServiceSuivi(contexte: contexte).suivi(reference) {
                    contexte.delete(ajoute)
                    contexte.sauver()
                }
                rafraichir()
            }
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
        etat.confirmer(anterieur ? "Marqué déjà vu avant" : "« \(film.titre) » dans Terminés", symbole: "checkmark") { [contexte] in
            try? ServiceSuivi(contexte: contexte).marquerNonVu(film: film.reference)
            rafraichir()
        }
        // 6.1 : vu à plusieurs ? Le film s'inscrit aussi chez les autres personnes de la famille.
        if !anterieur {
            VuEnsemble.demander(etat, reference: film.reference, titre: film.titre) { try $0.marquerVu(film: film) }
        }
    }

    /// « Terminé » sur une série finie (6.1) : les épisodes manquants se cochent, la série va dans Terminés.
    private func terminerSerie(_ serie: SerieDetail) {
        let service = ServiceSuivi(contexte: contexte)
        let avant = (try? service.episodesVus(serie.reference)) ?? []
        try? service.terminer(serie: serie)
        let ajoutes = ((try? service.episodesVus(serie.reference)) ?? []).subtracting(avant)
        rafraichir()
        etat.confirmer("« \(serie.nom) » dans Terminés", symbole: "checkmark") { [contexte] in
            let service = ServiceSuivi(contexte: contexte)
            for numero in ajoutes { try? service.decocher(numero, serie: serie.reference) }
            rafraichir()
        }
        VuEnsemble.demander(etat, reference: serie.reference, titre: serie.nom) { try $0.terminer(serie: serie) }
    }
}

/// EF-73 : l'état de disponibilité en tête du bloc « Où regarder ».
private struct BlocOuRegarder: View {
    let reference: ReferenceTitre
    let offres: OffresRegion?
    let etat: EtatDisponibilite
    /// Pour un film introuvable : au cinéma, bientôt, ou pas encore en streaming.
    let sortie: EtatSortie?
    /// Pour une série introuvable : épisode du jour, prochain épisode, chaîne.
    let diffusion: EtatDiffusionSerie?
    let alertesActives: Bool
    let prevenir: () -> Void

    @Query private var passages: [Diffusion]
    @Query private var chaines: [Chaine]
    @Environment(\.openURL) private var openURL
    /// Le titre, pour ouvrir la boutique qui le loue (6.4).
    var titreDuFilm: String = ""

    init(reference: ReferenceTitre, offres: OffresRegion?, etat: EtatDisponibilite, sortie: EtatSortie?, diffusion: EtatDiffusionSerie?,
         alertesActives: Bool, titreDuFilm: String = "", prevenir: @escaping () -> Void) {
        self.titreDuFilm = titreDuFilm
        self.reference = reference
        self.offres = offres
        self.etat = etat
        self.sortie = sortie
        self.diffusion = diffusion
        self.alertesActives = alertesActives
        self.prevenir = prevenir
        let id: Int? = reference.tmdbID
        let type = reference.type.rawValue
        let maintenant = Date.now
        _passages = Query(filter: #Predicate<Diffusion> { $0.tmdbID == id && $0.typeBrut == type && $0.fin > maintenant }, sort: \Diffusion.debut)
    }

    /// Les plateformes où le titre se regarde **quand on veut** (vidéo à la demande), parmi celles que TMDB liste.
    /// blue TV y figure pour son catalogue à la demande ; son direct, lui, est dans « À la TV », à heure fixe.
    private var aLaDemandeSurBlueTV: Bool {
        guard let offres else { return false }
        return (offres.abonnement + offres.gratuit + offres.avecPublicite).contains { $0.nom.localizedCaseInsensitiveContains("blue") }
    }

    /// « TF1 · jeudi 24 sept. à 20:55 » : les trois prochains passages connus du guide.
    private var prochainsPassages: [String] {
        let noms = Dictionary(chaines.map { ($0.identifiantGuide, $0.nom) }, uniquingKeysWith: { premier, _ in premier })
        let calendrier = Calendar.current
        return passages.prefix(3).map { passage in
            let heure = passage.debut.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_CH")))
            let jour = passage.debut <= .now ? "en ce moment, depuis"
                : calendrier.isDateInToday(passage.debut) ? "aujourd'hui à"
                : calendrier.isDateInTomorrow(passage.debut) ? "demain à"
                : passage.debut.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(Locale(identifier: "fr_CH"))) + " à"
            return "\(noms[passage.chaine] ?? passage.chaine) · \(jour) \(heure)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Où regarder").font(.title3.weight(.bold))
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: icone).font(.title3).foregroundStyle(Theme.texte).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(titre).font(.subheadline.weight(.semibold))
                        if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                }
                // Louer ou acheter (6.4) : la mention ne menait nulle part, alors que c'est le seul moyen de voir le
                // film ce soir. Le bouton ouvre la boutique la moins chère d'abord — celle que TMDB cite en premier.
                if case .aLouerOuAcheter(let location, let achat) = etat,
                   let boutique = (location + achat).first,
                   let lien = LiensPlateformes.lien(plateforme: boutique.id, titre: titreDuFilm) {
                    Button {
                        openURL(lien) { acceptee in
                            PlateformesApprises.noter(boutique.id, ouverte: acceptee)
                        }
                    } label: {
                        Label("Louer sur \(boutique.nom)", systemImage: "cart.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(Theme.accent)
                    .accessibilityHint("Ouvre \(boutique.nom) sur ce titre")
                }
                // Deux façons de regarder, bien séparées : à la demande (quand tu veux) et à la TV (date et heure fixes).
                if aLaDemandeSurBlueTV {
                    Label("blue TV, à la demande : tu le regardes quand tu veux.", systemImage: "play.tv")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !prochainsPassages.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("À la TV · en direct, à heure fixe", systemImage: "tv")
                            .font(.caption.weight(.bold)).foregroundStyle(Theme.texte2)
                        ForEach(prochainsPassages, id: \.self) { Text($0).font(.subheadline) }
                        Text("Sur tes chaînes (blue TV, antenne…) ; pas de replay.").font(.caption2).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                // Pas encore regardable chez soi : se faire prévenir de l'arrivée en streaming ou des épisodes.
                if case .introuvable = etat, sortie != nil || diffusion != nil {
                    if alertesActives {
                        Label(diffusion == nil ? "Tu seras prévenu de sa sortie" : "Tu seras prévenu des épisodes et de l'arrivée sur tes plateformes",
                              systemImage: "bell.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.texte2)
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
        case .aLaTeleBientot: return "À la TV bientôt"
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
            ImageDistante(url: ImageTMDB.url(personne.cheminPortrait, .portrait), coins: 40, symboleVide: "person.fill")
                .frame(width: 80, height: 80)
            Text(personne.nom).font(.caption.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
            if let role = personne.personnage, !role.isEmpty {
                Text(role).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: 90)
    }
}
