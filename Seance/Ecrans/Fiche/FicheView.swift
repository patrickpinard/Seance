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
            erreur = "Enregistre d'abord ta clé TMDB dans Moi › TMDB."
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
    @State private var videoChoisie: Video?
    @State private var dansSoiree = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                enTete
                actions
                BlocOuRegarder(etat: etatDisponibilite)
                SectionNASFiche(reference: fiche.reference)
                if !fiche.synopsis.isEmpty || !(fiche.accroche ?? "").isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        TitreSection("Synopsis")
                        VStack(alignment: .leading, spacing: 8) {
                            if let accroche = fiche.accroche, !accroche.isEmpty {
                                Text(accroche).italic()
                            }
                            if !fiche.synopsis.isEmpty {
                                Text(fiche.synopsis).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                if let serie = fiche.serie {
                    SectionEpisodes(serie: serie)
                }
                SectionBandesAnnonces(videos: fiche.videos) { videoChoisie = $0 }
                if !fiche.casting.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        TitreSection("Casting")
                        ScrollView(.horizontal, showsIndicators: false) {
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
                Text("Disponibilités : JustWatch")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(edges: .top)
        .task { rafraichir() }
        .sheet(item: $videoChoisie) { video in
            LecteurBandeAnnonce(video: video)
        }
    }

    /// UX-06 : image de fond, affiche, titre, année, genres, durée et anneau de note.
    private var enTete: some View {
        ZStack(alignment: .bottomLeading) {
            ImageDistante(url: ImageTMDB.url(fiche.cheminFond, .fondGrand), coins: 0)
                .frame(height: 300)
                .clipped()
            LinearGradient(colors: [.clear, Theme.fond.opacity(0.7), Theme.fond], startPoint: .top, endPoint: .bottom)
                .frame(height: 300)
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
                    AnneauNote(pourcentage: fiche.pourcentage, diametre: 44)
                }
            }
            .padding(.horizontal, 20)
            .offset(y: 60)
        }
        .padding(.bottom, 60)
    }

    /// Actions en icônes : « + » ajoute à « À voir », « − » retire ; l'œil marque vu ; ▶︎ la bande-annonce.
    private var actions: some View {
        HStack(spacing: 14) {
            BoutonIcone(
                symbole: suivi == nil ? "plus" : "minus",
                libelle: suivi == nil ? "Ajouter à voir" : "Retirer de mes listes",
                principal: suivi == nil,
                actif: suivi != nil,
                explication: suivi == nil
                    ? "Ajouter à « À voir » dans Mes listes. La cloche 🔔 s'active pour te prévenir des sorties et des nouveaux épisodes."
                    : "Retirer ce titre de Mes listes, avec ses alertes."
            ) {
                basculerAVoir()
            }

            if let film = fiche.film {
                BoutonIcone(symbole: vu ? "eye.fill" : "eye", libelle: vu ? "Vu" : "Marquer vu", actif: vu,
                            explication: vu ? "Tu as vu ce film : il compte dans tes goûts et ne revient plus dans les suggestions."
                                            : "Marquer ce film comme vu : Séance affine tes goûts et ne te le propose plus.") {
                    marquerVu(film)
                }
            }

            boutonAlertes

            if let video = fiche.videos.first {
                BoutonIcone(symbole: "play.rectangle.fill", libelle: "Bande-annonce",
                            explication: "Voir la bande-annonce, lue en streaming : rien n'est enregistré sur l'appareil.") {
                    videoChoisie = video
                }
            }
            Spacer()
            menuAutres
        }
        .padding(.horizontal, 20)
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
        vu = (try? suiviService.estVu(fiche.reference)) ?? false
        dansSoiree = (try? ServiceSoiree(contexte: contexte).estRetenu(fiche.reference)) ?? false
        etatDisponibilite = (try? ServiceDisponibilite(contexte: contexte).etat(fiche.reference, offres: fiche.offres)) ?? .introuvable
    }

    private func basculerAVoir() {
        let service = ServiceSuivi(contexte: contexte)
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

    private func marquerVu(_ film: FicheFilm) {
        guard !vu else { return }
        try? ServiceSuivi(contexte: contexte).marquerVu(film: film)
        rafraichir()
    }
}

/// EF-73 : l'état de disponibilité en tête du bloc « Où regarder ».
private struct BlocOuRegarder: View {
    let etat: EtatDisponibilite

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Où regarder").font(.title3.weight(.bold))
            HStack(spacing: 12) {
                Image(systemName: icone).font(.title3).foregroundStyle(Theme.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titre).font(.subheadline.weight(.semibold))
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 20)
    }

    private var icone: String {
        switch etat {
        case .surNAS: "externaldrive.fill"
        case .dansAbonnements: "play.tv.fill"
        case .aLaTeleBientot: "tv"
        case .aLouerOuAcheter: "cart"
        case .introuvable: "questionmark.circle"
        }
    }

    private var titre: String {
        switch etat {
        case .surNAS: "Sur le NAS"
        case .dansAbonnements: "Dans tes abonnements"
        case .aLaTeleBientot: "À la télé bientôt"
        case .aLouerOuAcheter: "À louer ou acheter"
        case .introuvable: "Introuvable légalement en Suisse"
        }
    }

    private var detail: String? {
        switch etat {
        case .surNAS(let qualite): qualite.map { "Qualité \($0)" }
        case .dansAbonnements(let fournisseurs): fournisseurs.map(\.nom).joined(separator: ", ")
        case .aLaTeleBientot(let diffusion):
            "\(diffusion.chaine), \(diffusion.debut.formatted(.dateTime.weekday(.wide).hour().minute()))"
        case .aLouerOuAcheter(let location, let achat):
            Array(Set((location + achat).map(\.nom))).sorted().joined(separator: ", ")
        case .introuvable: nil
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
