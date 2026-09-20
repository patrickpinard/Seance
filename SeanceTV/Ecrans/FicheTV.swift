import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// La fiche d'un titre sur la TV (EF-143), aussi complète que celle de l'iPhone : l'image en grand, les actions à
/// portée de télécommande — lire, ce soir, prévoir un autre soir, à voir, vu, être prévenu —, tes pouces et ta note,
/// où regarder (NAS, plateformes, passages TV avec le jour et l'heure), les épisodes saison par saison, les
/// bandes-annonces et le casting, dont chaque visage ouvre la fiche de la personne.
struct FicheTV: View {
    let reference: ReferenceTitre

    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Environment(\.openURL) private var ouvrir
    @Query private var fichiers: [FichierNAS]
    @Query private var suivis: [Suivi]
    @Query private var soirees: [SelectionSoir]
    @Query private var abonnements: [Abonnement]
    @Query private var visionnages: [Visionnage]
    @Query private var passages: [Diffusion]
    @Query private var chaines: [Chaine]
    @Query private var aimes: [TitreAime]

    @State private var film: FicheFilm?
    @State private var serie: SerieDetail?
    @State private var erreur: String?
    @State private var vu = false
    @State private var saisonChoisie: Int?
    @State private var saisons: [Int: SaisonDetail] = [:]
    @State private var choixDuSoir = false

    init(reference: ReferenceTitre) {
        self.reference = reference
        let id = reference.tmdbID
        let idFacultatif: Int? = reference.tmdbID
        let type = reference.type.rawValue
        let maintenant = Date.now
        _visionnages = Query(filter: #Predicate<Visionnage> { $0.tmdbID == id && $0.typeBrut == type })
        _passages = Query(filter: #Predicate<Diffusion> { $0.tmdbID == idFacultatif && $0.typeBrut == type && $0.fin > maintenant }, sort: \Diffusion.debut)
        _aimes = Query(filter: #Predicate<TitreAime> { $0.tmdbID == id && $0.typeBrut == type })
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            fond
            ScrollViewReader { defilement in
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    Spacer().frame(height: 300)
                    entete
                    actions
                    if let synopsis, !synopsis.isEmpty {
                        Text(synopsis).font(.system(size: 29)).foregroundStyle(.white.opacity(0.85)).lineSpacing(6).frame(maxWidth: 1250, alignment: .leading)
                    }
                    if let erreur { Text(erreur).font(.system(size: 26)).foregroundStyle(.orange) }
                    avis.id("avis")
                    ouRegarder.id("ouRegarder")
                    if let serie { episodes(serie).id("episodes") } else if reference.type == .serie, !episodesNAS.isEmpty { episodesDuNAS }
                    bandesAnnonces
                }
                .padding(.horizontal, MargesTV.bord)
                // Calée à gauche sur toute la largeur : plus étroite que l'écran, la page se centrait et ne s'alignait
                // plus sur l'étagère du casting.
                .frame(maxWidth: .infinity, alignment: .leading)
                casting
                    .id("casting")
                    .padding(.top, 40)
                    .padding(.bottom, 80)
            }
            #if DEBUG
            // Captures : `SEANCE_TV_ANCRE=episodes` amène une section à l'écran, la télécommande du simulateur ne se pilotant pas.
            .task(id: film?.id ?? serie?.id) {
                guard let ancre = ProcessInfo.processInfo.environment["SEANCE_TV_ANCRE"], film != nil || serie != nil else { return }
                try? await Task.sleep(for: .seconds(2))
                defilement.scrollTo(ancre, anchor: .top)
            }
            #endif
            }
        }
        .background(Theme.fond.ignoresSafeArea())
        .task(id: reference) { await charger() }
        .task(id: saisonAffichee) { await chargerSaison() }
        .fullScreenCover(isPresented: $choixDuSoir) { ChoixSoireeTV(titre: titre) { jour in prevoir(jour) } }
    }

    // MARK: Morceaux

    /// L'image de fond du titre ; à défaut (certains titres n'en ont pas), son affiche, cadrée large et plus assombrie.
    private var fond: some View {
        let cheminFond = film?.cheminFond ?? serie?.cheminFond ?? siens.first?.cheminFond
        let url = ImageTMDB.url(cheminFond, .fondGrand) ?? ImageTMDB.url(cheminAffiche, .afficheGrande)
        return ImageTV(url: url, symboleVide: "")
            .frame(maxWidth: .infinity)
            .frame(height: 760)
            .overlay {
                LinearGradient(stops: [.init(color: Theme.fond.opacity(cheminFond == nil ? 0.45 : 0), location: 0),
                                       .init(color: Theme.fond.opacity(cheminFond == nil ? 0.75 : 0.55), location: 0.45),
                                       .init(color: Theme.fond, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea()
    }

    private var entete: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titre).font(.system(size: 76, weight: .heavy)).lineLimit(2)
            Text(ligneFaits).font(.system(size: 30, weight: .medium)).foregroundStyle(.white.opacity(0.75))
            if !plateformes.isEmpty {
                Label("Dans tes abonnements : " + plateformes.joined(separator: ", "), systemImage: "play.rectangle.on.rectangle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.accentClair)
            }
        }
        .foregroundStyle(.white)
    }

    private var actions: some View {
        HStack(spacing: 28) {
            // Un film du NAS : la lecture d'abord, c'est pour elle qu'on est devant la TV.
            if reference.type == .film, let fichier = siens.first {
                Button { lire(fichier) } label: { Label("Lire", systemImage: "play.fill") }
                    .buttonStyle(BoutonTV(principal: true))
            }
            Button { basculerSoiree() } label: {
                Label(prevuCeSoir ? "Retirer de ce soir" : "Ce soir", systemImage: prevuCeSoir ? "moon.stars.fill" : "moon.stars")
            }
            if suivi == nil {
                Button { garder() } label: { Label("À voir", systemImage: "bookmark") }
            }
            Button { choixDuSoir = true } label: { Label("Un autre soir…", systemImage: "calendar") }
            if reference.type == .film {
                Button { basculerVu() } label: { Label(vu ? "Vu" : "Marquer vu", systemImage: vu ? "checkmark.circle.fill" : "checkmark.circle") }
            }
            if let suivi {
                Button { basculerAlertes(suivi) } label: {
                    Label(suivi.alertesActives ? "Alertes" : "Me prévenir", systemImage: suivi.alertesActives ? "bell.fill" : "bell")
                }
            }
        }
        .buttonStyle(BoutonTV())
        .focusSection()
    }

    // MARK: Tes pouces, ta note

    private var aime: Bool { !aimes.isEmpty }
    private var ecarte: Bool { suivi?.statut == .exclu }
    private var genres: [Int] { film?.genres.map(\.id) ?? serie?.genres.map(\.id) ?? [] }
    /// La note se donne après avoir regardé : un film vu, une série dont on a vu au moins un épisode.
    private var peutNoter: Bool { vu || !visionnages.isEmpty || suivi?.note != nil }

    private var avis: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 28) {
                Button { basculerAime() } label: { Label(aime ? "J'aime ✓" : "J'aime", systemImage: aime ? "hand.thumbsup.fill" : "hand.thumbsup") }
                Button { basculerEcarte() } label: {
                    Label(ecarte ? "Je n'aime pas ✓" : "Je n'aime pas", systemImage: ecarte ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                }
                Text(aime ? "Tes idées en tiennent compte." : ecarte ? "Séance ne te le propose plus." : "Sans l'avoir vu : pour de meilleures idées.")
                    .font(.system(size: 24)).foregroundStyle(.secondary)
            }
            .buttonStyle(BoutonTV())
            if peutNoter {
                HStack(spacing: 12) {
                    Text("Ta note").font(.system(size: 28, weight: .semibold)).frame(width: 150, alignment: .leading)
                    ForEach(1...10, id: \.self) { valeur in
                        Button { noter(valeur) } label: { Text("\(valeur)").frame(width: 46) }
                            .buttonStyle(BoutonTV(principal: suivi?.note == valeur, hauteur: 64))
                    }
                }
            }
        }
        .focusSection()
    }

    // MARK: Où regarder

    /// « RTS 1 · ce soir à 21:10 » : les trois prochains passages connus du guide.
    private var prochainsPassages: [String] {
        let calendrier = Calendar.current
        return passages.prefix(3).map { passage in
            let heure = passage.debut.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_CH")))
            let jour = passage.debut <= .now ? "en ce moment, depuis"
                : calendrier.isDateInToday(passage.debut) ? "aujourd'hui à"
                : calendrier.isDateInTomorrow(passage.debut) ? "demain à"
                : passage.debut.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(Locale(identifier: "fr_CH"))) + " à"
            return "\(NomChaineTV.lire(passage.chaine, parmi: chaines)) · \(jour) \(heure)"
        }
    }

    private var offres: OffresRegion? { (film?.fournisseurs ?? serie?.fournisseurs)?.offres() }

    /// Les plateformes cochées où le titre est inclus : chacune s'ouvre sur le titre.
    private var plateformesIncluses: [Fournisseur] {
        guard let offres else { return [] }
        let cochees = Set(abonnements.filter(\.actif).map(\.providerID))
        return (offres.abonnement + offres.gratuit + offres.avecPublicite).filter { cochees.contains($0.id) }
    }

    private var ouRegarder: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Où regarder").font(.system(size: 38, weight: .bold))
            if let fichier = siens.first {
                Label(["Sur ton NAS", fichier.qualite].compactMap { $0 }.joined(separator: " · "), systemImage: "externaldrive.fill")
                    .font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.accentClair)
            }
            if !plateformesIncluses.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("En streaming · quand tu veux").font(.system(size: 24, weight: .bold)).foregroundStyle(.secondary)
                    HStack(spacing: 24) {
                        ForEach(plateformesIncluses) { plateforme in
                            Button { ouvrirPlateforme(plateforme) } label: { Label(plateforme.nom, systemImage: "play.tv") }
                        }
                    }
                    .buttonStyle(BoutonTV())
                }
            }
            if !prochainsPassages.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("À la TV · en direct, à heure fixe").font(.system(size: 24, weight: .bold)).foregroundStyle(.secondary)
                    ForEach(prochainsPassages, id: \.self) { Label($0, systemImage: "tv").font(.system(size: 28, weight: .medium)) }
                }
            }
            if siens.isEmpty, plateformesIncluses.isEmpty, prochainsPassages.isEmpty {
                let aLouer = Array(Set((offres?.location ?? []) + (offres?.achat ?? [])).map(\.nom)).sorted()
                Label(aLouer.isEmpty ? (abonnements.isEmpty ? "Coche tes plateformes dans Réglages › Plateformes pour le savoir." : "Dans aucun de tes abonnements, ni sur ton NAS, ni à la TV cette semaine.")
                                     : "À louer ou acheter : " + aLouer.prefix(5).joined(separator: ", "),
                      systemImage: aLouer.isEmpty ? "questionmark.circle" : "cart")
                    .font(.system(size: 27)).foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(maxWidth: 1500, alignment: .leading)
        // Une section de focus sans rien à choisir (un film du NAS ou de la TV : que des étiquettes) arrêtait la
        // télécommande : on ne descendait plus jusqu'au casting. Elle n'existe que s'il y a des plateformes à ouvrir.
        .sectionDeFocus(si: !plateformesIncluses.isEmpty)
    }

    // MARK: Épisodes (EF-11 à EF-13)

    private var vus: Set<NumeroEpisode> {
        Set(visionnages.compactMap { v in
            guard let saison = v.saison, let episode = v.episode else { return nil }
            return NumeroEpisode(saison: saison, episode: episode)
        })
    }

    private func numerosDeSaison(_ serie: SerieDetail) -> [SaisonResume] {
        serie.saisons.filter { $0.numero > 0 && $0.nombreEpisodes > 0 }.sorted { $0.numero < $1.numero }
    }

    private var prochain: (numero: NumeroEpisode, disponible: Bool)? {
        serie.flatMap { ProgressionSerie.suivant(vus: vus, saisons: $0.saisons, dernierDiffuse: $0.dernierEpisode) }
    }

    private var saisonAffichee: Int? {
        saisonChoisie ?? prochain?.numero.saison ?? serie.flatMap { numerosDeSaison($0).first?.numero }
    }

    private func fichierNAS(_ numero: NumeroEpisode) -> FichierNAS? {
        siens.first { $0.saison == numero.saison && $0.episode == numero.episode }
    }

    private func episodes(_ serie: SerieDetail) -> some View {
        let liste = numerosDeSaison(serie)
        let total = ProgressionSerie.total(serie.saisons)
        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                Text("Épisodes").font(.system(size: 38, weight: .bold))
                Text("\(vus.count) \(vus.count > 1 ? "vus" : "vu") sur \(total)").font(.system(size: 26)).foregroundStyle(.secondary)
                if let prochain, prochain.disponible {
                    Text("À regarder : \(prochain.numero.description)").font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.accentClair)
                }
            }
            if liste.count > 1 {
                SelecteurTV(selection: Binding { saisonAffichee ?? 1 } set: { saisonChoisie = $0 },
                            cases: liste.map { ($0.numero, "Saison \($0.numero)") })
                    // Le sélecteur apporte ses propres marges de page : ici il est déjà dans celles de la fiche.
                    .padding(.horizontal, -MargesTV.bord)
            }
            if let numero = saisonAffichee, let saison = saisons[numero] {
                VStack(spacing: 6) {
                    ForEach(saison.episodes) { episode in ligne(episode, serie: serie) }
                }
                .padding(20)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            } else {
                Text("Lecture de la saison…").font(.system(size: 26)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 1500, alignment: .leading)
        .focusSection()
    }

    /// Une ligne d'épisode : la choisir le coche ou le décoche ; s'il est sur le NAS, « Lire » est à côté.
    private func ligne(_ episode: EpisodeTMDB, serie: SerieDetail) -> some View {
        let numero = episode.numeroEpisode
        let estVu = vus.contains(numero)
        let diffuse = episode.dateDiffusion.map { $0 <= DateTMDB(.now) } ?? false
        return HStack(spacing: 16) {
            Button { cocher(episode, serie: serie, vu: estVu) } label: {
                HStack(spacing: 22) {
                    Image(systemName: estVu ? "checkmark.circle.fill" : "circle").font(.system(size: 32))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(episode.numero). \(episode.nom)").font(.system(size: 29, weight: .semibold)).lineLimit(1)
                        Text([episode.dateDiffusion.map { $0.instant(heure: 12).formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "fr_CH"))) } ?? "Date à venir",
                              episode.dureeMinutes.map { "\($0) min" }, fichierNAS(numero) != nil ? "sur ton NAS" : nil]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 23)).opacity(0.7)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            }
            .buttonStyle(LigneTV())
            .disabled(!diffuse && !estVu)
            .opacity(diffuse || estVu ? 1 : 0.5)
            if let fichier = fichierNAS(numero) {
                Button { lire(fichier) } label: { Label("Lire", systemImage: "play.fill") }
                    .buttonStyle(BoutonTV(principal: true, hauteur: 64))
            }
        }
    }

    // MARK: Bandes-annonces et casting

    private var videos: [Video] { Array((film?.videos?.bandesAnnonces ?? serie?.videos?.bandesAnnonces ?? []).prefix(4)) }

    @ViewBuilder
    private var bandesAnnonces: some View {
        if !videos.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Bandes-annonces").font(.system(size: 38, weight: .bold))
                HStack(spacing: 24) {
                    ForEach(videos) { video in
                        Button { ouvrirVideo(video) } label: { Label(video.nom, systemImage: "play.rectangle.fill").lineLimit(1).frame(maxWidth: 420) }
                    }
                }
                .buttonStyle(BoutonTV())
                Text("Elles s'ouvrent dans l'app YouTube de l'Apple TV.").font(.system(size: 22)).foregroundStyle(.secondary)
            }
            .focusSection()
        }
    }

    private var acteurs: [PersonneCasting] { film?.casting?.principaux(15) ?? serie?.casting?.principaux(15) ?? [] }

    @ViewBuilder
    private var casting: some View {
        if !acteurs.isEmpty {
            EtagereTV(titre: "Casting", sousTitre: "Choisis un visage pour voir ses autres films et séries") {
                ForEach(acteurs) { personne in
                    NavigationLink(value: PersonneTVRef(id: personne.id, nom: personne.nom)) {
                        AfficheTV(titre: personne.nom, sousTitre: personne.personnage, cheminAffiche: personne.cheminPortrait)
                    }
                    .buttonStyle(.card)
                }
            }
            // L'étagère va d'un bord à l'autre de l'écran : elle sort des marges de la page.
        }
    }

    private var episodesDuNAS: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Sur ton NAS").font(.system(size: 38, weight: .bold))
            ForEach(episodesNAS, id: \.chemin) { fichier in
                HStack(spacing: 24) {
                    Text(numero(fichier)).font(.system(size: 28, weight: .bold)).monospacedDigit().frame(width: 150, alignment: .leading)
                    Text(fichier.qualite ?? "").font(.system(size: 24)).foregroundStyle(.secondary)
                    Spacer()
                    Button { lire(fichier) } label: { Label("Lire", systemImage: "play.fill") }
                        .buttonStyle(BoutonTV(principal: true))
                }
                .font(.system(size: 26))
            }
        }
        .frame(maxWidth: 1250, alignment: .leading)
        .focusSection()
    }

    // MARK: Données

    private var siens: [FichierNAS] { fichiers.filter { $0.reference == reference } }
    private var episodesNAS: [FichierNAS] {
        siens.filter { $0.saison != nil && $0.episode != nil }.sorted { ($0.saison ?? 0, $0.episode ?? 0) < ($1.saison ?? 0, $1.episode ?? 0) }
    }
    private var suivi: Suivi? { suivis.first { $0.reference == reference } }
    private var prevuCeSoir: Bool { soirees.contains { $0.reference == reference && $0.soiree == ServiceSoiree.soiree() } }

    private var titre: String { film?.titre ?? serie?.nom ?? siens.first?.titre ?? suivi?.titre ?? "…" }
    private var synopsis: String? { film?.synopsis ?? serie?.synopsis }
    private var cheminAffiche: String? { film?.cheminAffiche ?? serie?.cheminAffiche ?? siens.first?.cheminAffiche ?? suivi?.cheminAffiche }

    private var ligneFaits: String {
        var faits: [String] = [reference.type == .film ? "Film" : "Série"]
        if let minutes = film?.dureeMinutes, minutes > 0 { faits.append(minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min") }
        if let serie { faits.append(serie.nombreSaisons > 1 ? "\(serie.nombreSaisons) saisons" : "1 saison") }
        let genres = (film?.genres ?? serie?.genres ?? []).prefix(3).map(\.nom)
        if !genres.isEmpty { faits.append(genres.joined(separator: ", ")) }
        let note = film?.noteMoyenne ?? serie?.noteMoyenne ?? 0
        if note > 0 { faits.append("\(Int((note * 10).rounded())) % sur TMDB") }
        if !siens.isEmpty { faits.append("Sur ton NAS") }
        return faits.joined(separator: "  ·  ")
    }

    /// Les plateformes où le titre est inclus, en Suisse, parmi celles cochées sur l'iPhone (arrivées par la synchronisation).
    private var plateformes: [String] {
        guard let offres = (film?.fournisseurs ?? serie?.fournisseurs)?.offres() else { return [] }
        let cochees = Set(abonnements.filter(\.actif).map(\.providerID))
        return offres.abonnement.filter { cochees.contains($0.id) }.map(\.nom)
    }

    private func numero(_ fichier: FichierNAS) -> String {
        "S\(String(format: "%02d", fichier.saison ?? 0))E\(String(format: "%02d", fichier.episode ?? 0))"
    }

    // MARK: Actions

    private func charger() async {
        vu = (try? ServiceSuivi(contexte: contexte).estVu(reference)) ?? false
        guard let client = etat.tmdb else { return }
        do {
            switch reference.type {
            case .film: film = try await client.film(reference.tmdbID)
            case .serie: serie = try await client.serie(reference.tmdbID, complements: [.fournisseurs, .casting, .videos])
            }
        } catch {
            erreur = "La fiche n'a pas pu être lue sur TMDB. Vérifie la connexion de l'Apple TV."
        }
    }

    /// Dans l'app choisie dans Réglages › Lecture, et elle seule.
    private func lire(_ fichier: FichierNAS) {
        guard let url = etat.lien(pour: fichier) else {
            etat.dire(etat.lecteur == .infuse ? "Infuse ne s'ouvre que sur un titre reconnu. Choisis VLC dans Réglages › Lecture."
                                              : "Le mot de passe du NAS manque : vois Réglages › NAS.")
            return
        }
        etat.noterLecture(fichier)
        ouvrir(url) { accepte in
            if !accepte { etat.dire("\(etat.lecteur.nom) n'est pas installé sur cette Apple TV, ou refuse ce lien.") }
        }
    }

    private func chargerSaison() async {
        guard let numero = saisonAffichee, saisons[numero] == nil, let client = etat.tmdb else { return }
        if let saison = try? await client.saison(numero, serie: reference.tmdbID) { saisons[numero] = saison }
    }

    private func cocher(_ episode: EpisodeTMDB, serie: SerieDetail, vu estVu: Bool) {
        let service = ServiceSuivi(contexte: contexte)
        if estVu {
            try? service.decocher(episode.numeroEpisode, serie: reference)
        } else {
            _ = try? service.cocher([episode], serie: serie)
            // Un épisode, pas la série : prévue ce soir, elle quitte la soirée (comme sur l'iPhone).
            if prevuCeSoir { try? ServiceSoiree(contexte: contexte).retirer(reference) }
            etat.dire("Épisode \(episode.numeroEpisode) vu")
        }
    }

    private func noter(_ valeur: Int) {
        let service = ServiceSuivi(contexte: contexte)
        let nouvelle: Int? = suivi?.note == valeur ? nil : valeur
        if let film { try? service.noter(film: film, note: nouvelle) } else if let serie { try? service.noter(serie: serie, note: nouvelle) }
        etat.dire(nouvelle.map { "« \(titre) » noté \($0)/10" } ?? "Note effacée")
    }

    private func basculerAime() {
        let gouts = ServiceGouts(contexte: contexte)
        if aime {
            try? gouts.nePlusAimer(reference)
        } else {
            try? gouts.aimer(reference, titre: titre, cheminAffiche: cheminAffiche, genres: genres,
                             acteursIDs: acteurs.prefix(5).map(\.id), acteurs: acteurs.prefix(5).map(\.nom))
            etat.dire("Noté : tes idées en tiendront compte")
        }
    }

    private func basculerEcarte() {
        let gouts = ServiceGouts(contexte: contexte)
        if ecarte {
            try? gouts.reproposer(reference)
            etat.dire("« \(titre) » pourra de nouveau t'être proposé")
        } else {
            try? gouts.jamais(reference, titre: titre, genres: genres, cheminAffiche: cheminAffiche)
            try? ServiceSoiree(contexte: contexte).retirer(reference)
            etat.dire("« \(titre) » ne te sera plus proposé")
        }
    }

    /// La cloche : l'Apple TV n'affiche pas de notification, c'est l'iPhone qui prévient, une fois synchronisé.
    private func basculerAlertes(_ suivi: Suivi) {
        suivi.alertesActives.toggle()
        try? contexte.save()
        etat.dire(suivi.alertesActives ? "Ton iPhone te préviendra (sorties, épisodes, passages TV)" : "Plus d'alertes pour « \(titre) »")
    }

    private func prevoir(_ jour: Date) {
        try? ServiceSoiree(contexte: contexte).retenir(reference, titre: titre, cheminAffiche: cheminAffiche, soiree: ServiceSoiree.soiree(jour: jour))
        etat.dire("« \(titre) » prévu \(jour.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_CH"))))")
    }

    private func ouvrirPlateforme(_ plateforme: Fournisseur) {
        guard let lien = LiensPlateformes.lien(plateforme: plateforme.id, titre: titre) else {
            return etat.dire("Ouvre \(plateforme.nom) sur l'Apple TV et cherche « \(titre) ».")
        }
        ouvrir(lien) { accepte in
            if !accepte { etat.dire("\(plateforme.nom) ne s'ouvre pas d'ici : lance l'app et cherche « \(titre) ».") }
        }
    }

    private func ouvrirVideo(_ video: Video) {
        guard video.site == "YouTube", let lien = URL(string: "youtube://watch/\(video.cle)") else { return etat.dire("Cette vidéo ne se lit pas sur l'Apple TV.") }
        ouvrir(lien) { accepte in
            if !accepte { etat.dire("Installe l'app YouTube sur l'Apple TV pour voir les bandes-annonces.") }
        }
    }

    private func basculerSoiree() {
        let service = ServiceSoiree(contexte: contexte)
        if prevuCeSoir {
            try? service.retirer(reference)
            etat.dire("« \(titre) » retiré de ta soirée")
        } else {
            try? service.retenir(reference, titre: titre, cheminAffiche: cheminAffiche)
            etat.dire("« \(titre) » ajouté à ta soirée")
        }
    }

    private func garder() {
        let service = ServiceSuivi(contexte: contexte)
        if let film { _ = try? service.suivre(film: film) } else if let serie { _ = try? service.suivre(serie: serie) } else { return }
        etat.dire("« \(titre) » gardé dans « À voir »")
    }

    private func basculerVu() {
        guard let film else { return }
        let service = ServiceSuivi(contexte: contexte)
        if vu { try? service.marquerNonVu(film: reference) } else { try? service.marquerVu(film: film) }
        vu.toggle()
        etat.dire(vu ? "« \(titre) » marqué vu" : "« \(titre) » de nouveau à voir")
    }
}
