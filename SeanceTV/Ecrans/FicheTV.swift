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
    /// « Regarder » depuis l'appui long sur une carte (8.0) : l'action principale part dès que la fiche est chargée.
    var lancerALOuverture = false
    @State private var dejaLance = false

    /// Le film du NAS ouvert dans le lecteur de Séance (6.6).
    @State private var filmALire: FichierNAS?
    /// Où commencer le fichier lancé : la position retenue, ou `nil` pour le début (8.0).
    @State private var departLecture: Double?
    /// Une vidéo entamée : « Reprendre à 1:03:12 ou depuis le début ? ».
    @State private var repriseAProposer: FichierNAS?
    /// « Qui regarde avec toi ? » avant la lecture (8.2).
    @State private var compagnonsAChoisir: LectureAvant?
    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Environment(\.openURL) private var ouvrir
    /// Netflix, Apple TV, Disney+ : l'identifiant du titre chez eux, lu sur Wikidata (6.1).
    @State private var identifiants: IdentifiantsPlateformes?
    @State private var choixSource = false
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
    /// « ⋯ » : les actions secondaires, dans une fenêtre de Séance (8.0).
    @State private var plusOuvert = false
    /// « Noter » : la rangée de 1 à 10, ouverte par l'étoile de « Ton avis ».
    @State private var notationOuverte = false

    init(reference: ReferenceTitre, lancerALOuverture: Bool = false) {
        self.reference = reference
        self.lancerALOuverture = lancerALOuverture
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
                // Maquette 8.0, n° 13 et 14 : surligne, titre, résumé court, l'action principale et ses voisines, la
                // reprise, puis « Ton avis » — le tout sur l'image, en haut à gauche.
                VStack(alignment: .leading, spacing: 30) {
                    Spacer().frame(height: 110)
                    entete
                    VStack(alignment: .leading, spacing: 14) {
                        actions
                        reprise
                    }
                    if let erreur { Text(erreur).font(.system(size: 26)).foregroundStyle(Theme.attention) }
                    avis.id("avis")
                    Spacer().frame(height: 120)
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
        .task(id: reference) {
            await charger()
            guard lancerALOuverture, !dejaLance else { return }
            dejaLance = true
            if let premiere = sourcesTV.first, sourcesTV.count == 1 || premiere.bouton.hasPrefix("Reprendre") {
                premiere.lancer()
            } else if sourcesTV.count > 1 {
                choixSource = true
            } else {
                etat.dire("Aucune source pour regarder « \(titre) » : ni sur ton NAS, ni sur tes plateformes.")
            }
        }
        .task(id: reference) {
            Plantages.page("Fiche \(reference)")
            identifiants = await EtatTV.identifiants.identifiants([reference])[reference]
        }
        .fullScreenCover(item: $filmALire) { fichier in
            LecteurVLCTV(video: VideoPerso(chemin: fichier.chemin, taille: fichier.tailleOctets),
                         acces: etat.nas, motDePasse: etat.motDePasseDuNAS ?? "", surEchec: { _ in
                // Même VLC n'y arrive pas : l'app de Réglages › Lecture, comme avant.
                filmALire = nil
                lireDehors(fichier)
            }, depart: departLecture, surPosition: { secondes, duree in
                etat.noterPosition(fichier.chemin, secondes: secondes, duree: duree)
            }, fichier: fichier, surSuivant: { prochain in
                // L'épisode d'après (8.1) : le lecteur se referme et se rouvre sur lui, depuis le début.
                departLecture = nil
                filmALire = prochain
            })
        }
        .fullScreenCover(item: $compagnonsAChoisir) { avant in
            ChoixAvecQuiTV(moment: .avant(titre: titre) { _ in
                // La question se referme d'abord : le lecteur s'ouvre juste après.
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    lancer(avant.fichier, reprendre: avant.reprendre)
                }
            }) { compagnonsAChoisir = nil }
        }
        // Une question de Séance, à ses couleurs : reprendre, ou repartir du début.
        .fullScreenCover(item: $repriseAProposer) { fichier in
            let position = etat.positions.aReprendre(fichier.chemin)
            DialogueTV(titre: titre,
                       message: position.map { "Tu t'es arrêté à \(PositionsLecture.horodatage($0.secondes))\($0.appareil.map { ", sur l'\($0)" } ?? "")." },
                       choix: [
                           DialogueTV.Choix(libelle: "Reprendre à \(PositionsLecture.horodatage(position?.secondes ?? 0))", principal: true) {
                               departLecture = position?.secondes
                               filmALire = fichier
                           },
                           DialogueTV.Choix(libelle: "Depuis le début") {
                               etat.oublierPosition(fichier.chemin)
                               departLecture = nil
                               filmALire = fichier
                           },
                       ], progression: position?.fraction)
        }
        .task(id: saisonAffichee) { await chargerSaison() }
        .fullScreenCover(isPresented: $choixDuSoir) { ChoixSoireeTV(titre: titre) { jour in prevoir(jour) } }
    }

    // MARK: Morceaux

    /// L'image de fond du titre ; à défaut (certains titres n'en ont pas), son affiche, cadrée large et plus assombrie.
    private var fond: some View {
        let cheminFond = film?.cheminFond ?? serie?.cheminFond ?? siens.first?.cheminFond
        let url = ImageTMDB.url(cheminFond, .fondGrand) ?? ImageTMDB.url(cheminAffiche, .afficheGrande)
        // Plein écran (maquette 8.0) : l'image occupe tout, assombrie à gauche sous le texte et en bas.
        return ImageTV(url: url, symboleVide: "")
            .frame(maxWidth: .infinity)
            .frame(height: 1080)
            .overlay {
                ZStack {
                    LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                    LinearGradient(stops: [.init(color: Theme.fond.opacity(cheminFond == nil ? 0.45 : 0), location: 0),
                                           .init(color: Theme.fond.opacity(0.2), location: 0.6),
                                           .init(color: Theme.fond, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .ignoresSafeArea()
    }

    private var entete: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ligneFaits).font(.system(size: 26, weight: .bold)).foregroundStyle(.white.opacity(0.78))
            Text(titre).font(.system(size: 76, weight: .heavy)).lineLimit(2)
            if let synopsis, !synopsis.isEmpty {
                Text(synopsis).font(.system(size: 27)).foregroundStyle(.white.opacity(0.8)).lineLimit(3).lineSpacing(4)
                    .frame(maxWidth: 1050, alignment: .leading)
            }
        }
        .foregroundStyle(.white)
    }

    /// Charte 8.0 : l'action principale — regarder —, puis Ma liste, Ce soir et « ⋯ » pour le reste, dans le même ordre
    /// que sur l'iPhone. Le focus blanchit et soulève le bouton, comme partout sur tvOS.
    private var actions: some View {
        HStack(spacing: 28) {
            // Un seul accès : le bouton le lance ; plusieurs (le NAS et Netflix…), « Regarder… » demande lequel.
            // Entamé : « Reprendre à … » est l'action principale, même quand d'autres sources existent (maquette n° 13).
            if let premiere = sourcesTV.first, premiere.bouton.hasPrefix("Reprendre") {
                Button { premiere.lancer() } label: { Label(premiere.bouton, systemImage: "play.fill") }
                    .buttonStyle(BoutonTV(principal: true))
            } else if sourcesTV.count == 1, let seule = sourcesTV.first {
                Button { seule.lancer() } label: { Label(seule.bouton, systemImage: "play.fill") }
                    .buttonStyle(BoutonTV(principal: true))
            } else if sourcesTV.count > 1 {
                Button { choixSource = true } label: { Label("Regarder", systemImage: "play.fill") }
                    .buttonStyle(BoutonTV(principal: true))
                    // Une fenêtre de Séance, lisible sur la TV (6.3).
                    .fullScreenCover(isPresented: $choixSource) {
                        DialogueTV(titre: "Regarder « \(titre) »", message: "Où veux-tu le lancer ?",
                                   choix: sourcesTV.map { source in
                                       DialogueTV.Choix(libelle: source.nom, principal: source.nom.hasPrefix("Sur ton NAS")) { source.lancer() }
                                   })
                    }
            }
            if suivi == nil {
                Button { garder() } label: { Label("Ma liste", systemImage: "plus") }
            } else {
                // Maquette 8.0, n° 14 : le bouton dit où le titre en est — « En cours », « À voir », « Terminé ». 8.1 : il
                // bascule — un clic le termine, un autre le rouvre (il ne faisait rien, et « Terminé » restait pour de bon).
                Button { basculerTermine() } label: {
                    Label(etatDansLaListe, systemImage: estTermine ? "checkmark.circle.fill" : "circle")
                }
                .accessibilityLabel(estTermine ? "Terminé, choisir pour le rouvrir" : "\(etatDansLaListe), choisir pour le terminer")
            }
            Button { basculerSoiree() } label: { Image(systemName: prevuCeSoir ? "moon.stars.fill" : "moon.stars") }
                .buttonStyle(BoutonRondTV(choisi: prevuCeSoir))
                .accessibilityLabel(prevuCeSoir ? "Retirer de ce soir" : "Ce soir")
            Button { plusOuvert = true } label: { Image(systemName: "ellipsis") }
                .buttonStyle(BoutonRondTV())
                .accessibilityLabel("Plus")
                .fullScreenCover(isPresented: $plusOuvert) {
                    DialogueTV(titre: titre, message: nil, choix: choixPlus)
                }
        }
        .buttonStyle(BoutonTV())
        .focusSection()
    }

    private var estTermine: Bool {
        reference.type == .film ? vu : suivi?.statut == .termine
    }

    /// Terminé ↔ À voir pour un film (il passe dans les vus, ou en sort) ; Terminé ↔ En cours pour une série.
    private func basculerTermine() {
        if reference.type == .film { return basculerVu() }
        guard let suivi else { return }
        suivi.statut = suivi.statut == .termine ? .enCours : .termine
        try? contexte.save()
        etat.dire(suivi.statut == .termine ? "« \(titre) » terminé" : "« \(titre) » de nouveau en cours")
        if suivi.statut == .termine, let serie {
            etat.demanderAvecQui(reference, titre: titre) { _ = try ServiceSuivi(contexte: $0).terminer(serie: serie) }
        }
    }

    private var etatDansLaListe: String {
        if reference.type == .film, vu { return "Terminé" }
        return switch suivi?.statut {
        case .enCours: "En cours"
        case .termine: "Terminé"
        default: "Dans ma liste"
        }
    }

    /// « ⋯ » : un autre soir, terminé, les alertes — les mêmes mots que le menu de l'iPhone.
    private var choixPlus: [DialogueTV.Choix] {
        var choix = [DialogueTV.Choix(libelle: "Un autre soir…") { choixDuSoir = true }]
        if reference.type == .film, let fichier = siens.first, etat.positions.aReprendre(fichier.chemin) != nil {
            choix.insert(DialogueTV.Choix(libelle: "Depuis le début") {
                etat.oublierPosition(fichier.chemin)
                departLecture = nil
                filmALire = fichier
            }, at: 0)
        }
        if reference.type == .film {
            choix.append(DialogueTV.Choix(libelle: vu ? "Pas encore vu" : "Terminé") { basculerVu() })
        }
        // 8.2.15 : comme le « ⋯ » de l'iPhone — « Déjà vu avant », et pour une série le choix des alertes.
        if !vu {
            choix.append(DialogueTV.Choix(libelle: ActionTitre.dejaVuAvant.libelle(reference.type)) { Task { await dejaVuAvant() } })
        }
        if let suivi {
            if reference.type == .serie {
                choix.append(DialogueTV.Choix(libelle: "Me prévenir à chaque épisode") { reglerAlertes(suivi, .episodes) })
                choix.append(DialogueTV.Choix(libelle: "Me prévenir aux nouvelles saisons seulement") { reglerAlertes(suivi, .saisons) })
                if suivi.alertesActives {
                    choix.append(DialogueTV.Choix(libelle: "Ne plus me prévenir") { reglerAlertes(suivi, nil) })
                }
            } else {
                choix.append(DialogueTV.Choix(libelle: suivi.alertesActives ? "Ne plus me prévenir" : "Me prévenir") { basculerAlertes(suivi) })
            }
        }
        if prevuCeSoir {
            choix.append(DialogueTV.Choix(libelle: "Retirer de ce soir") { basculerSoiree() })
        }
        return choix
    }

    // MARK: Tes pouces, ta note

    private var aime: Bool { !aimes.isEmpty }
    private var ecarte: Bool { suivi?.statut == .exclu }
    private var genres: [Int] { film?.genres.map(\.id) ?? serie?.genres.map(\.id) ?? [] }
    /// La note se donne après avoir regardé : un film vu, une série dont on a vu au moins un épisode.
    private var peutNoter: Bool { vu || !visionnages.isEmpty || suivi?.note != nil }

    /// « Ton avis » : trois ronds du même trait — j'aime, pas pour moi, noter. Plein et orange quand c'est choisi.
    private var avis: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 24) {
                Text("Ton avis").font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.texte2)
                Button { basculerAime() } label: { Image(systemName: aime ? "hand.thumbsup.fill" : "hand.thumbsup") }
                    .buttonStyle(BoutonRondTV(choisi: aime))
                    .accessibilityLabel(aime ? "J'aime, choisi" : "J'aime")
                Button { basculerEcarte() } label: { Image(systemName: ecarte ? "hand.thumbsdown.fill" : "hand.thumbsdown") }
                    .buttonStyle(BoutonRondTV(choisi: ecarte))
                    .accessibilityLabel(ecarte ? "Pas pour moi, choisi" : "Pas pour moi")
                if peutNoter {
                    Button { notationOuverte.toggle() } label: { Image(systemName: suivi?.note == nil ? "star" : "star.fill") }
                        .buttonStyle(BoutonRondTV(choisi: suivi?.note != nil))
                        .accessibilityLabel(suivi?.note.map { "Ta note : \($0) sur 10" } ?? "Noter")
                }
            }
            if peutNoter, notationOuverte {
                HStack(spacing: 12) {
                    ForEach(1...10, id: \.self) { valeur in
                        Button { noter(valeur); notationOuverte = false } label: { Text("\(valeur)").frame(width: 46) }
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
                    if let (idGuide, chaine) = chaineBlueTV {
                        Button { ouvrirBlueTV(idGuide, nom: chaine) } label: { Label("Regarder \(chaine) dans blue TV", systemImage: "play.tv.fill") }
                            .buttonStyle(BoutonTV())
                            .padding(.top, 8)
                    }
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
        .sectionDeFocus(si: !plateformesIncluses.isEmpty || chaineBlueTV != nil)
    }

    /// Ce qui se lance d'ici (6.1) : le film du NAS, les plateformes incluses qui ont un lien, la chaîne en direct.
    private var sourcesTV: [(nom: String, bouton: String, lancer: () -> Void)] {
        var sources: [(nom: String, bouton: String, lancer: () -> Void)] = []
        if reference.type == .film, let fichier = siens.first {
            // Entamé : « Reprendre à 1:03:12 » devient l'action principale (8.0).
            let bouton = etat.positions.aReprendre(fichier.chemin).map { "Reprendre à \(PositionsLecture.horodatage($0.secondes))" } ?? "Lire"
            sources.append((["Sur ton NAS", fichier.qualite].compactMap { $0 }.joined(separator: " · "), bouton, { lire(fichier, reprendre: true) }))
        }
        // Une série du NAS : l'épisode à regarder, s'il y est (6.1.1) — il n'y avait pas de bouton en tête de fiche.
        if reference.type == .serie, let numero = prochain?.numero, let fichier = fichierNAS(numero) {
            let code = "S\(String(format: "%02d", numero.saison))E\(String(format: "%02d", numero.episode))"
            sources.append(("\(code) sur ton NAS", "Lire \(code)", { lire(fichier) }))
        }
        for plateforme in plateformesIncluses where LiensPlateformes.lien(plateforme: plateforme.id, titre: titre) != nil {
            sources.append((plateforme.nom, "Regarder sur \(plateforme.nom)", { ouvrirPlateforme(plateforme) }))
        }
        if let (idGuide, chaine) = chaineBlueTV {
            sources.append(("\(chaine) en direct · blue TV", "\(chaine) en direct", { ouvrirBlueTV(idGuide, nom: chaine) }))
        }
        return sources
    }

    /// Le passage en cours, ou qui commence dans le quart d'heure, à ouvrir dans l'app blue TV (6.1).
    private var chaineBlueTV: (String, String)? {
        guard UserDefaults.standard.object(forKey: "tele.blueTV") as? Bool ?? true,
              let passage = passages.first, passage.debut <= .now.addingTimeInterval(15 * 60), passage.fin > .now,
              LiensChaines.numero(chaine: passage.chaine) != nil else { return nil }
        return (passage.chaine, NomChaineTV.lire(passage.chaine, parmi: chaines))
    }

    /// L'app blue TV s'ouvre sur une émission, pas sur une chaîne (6.3) : Séance demande d'abord au catalogue public de
    /// Swisscom ce qui passe, puis ouvre `tvguide://…`. Sans réponse, l'app s'ouvre sur son guide.
    private func ouvrirBlueTV(_ idGuide: String, nom: String) {
        BlueTVSurTV.ouvrir(idGuide, nom: nom, etat: etat, ouvrir: ouvrir)
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
        // Maquette 8.0, n° 14 : « Épisodes » et les saisons en pastilles sur une ligne, puis les épisodes en cartes ;
        // les vus sont éteints, avec « Vu ». Un clic lit l'épisode s'il est sur le NAS, sinon le coche ; l'appui long
        // propose les deux.
        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 18) {
                Text("Épisodes").font(.system(size: 38, weight: .bold))
                if liste.count > 1 {
                    ForEach(liste, id: \.numero) { saison in
                        Button("Saison \(saison.numero)") { saisonChoisie = saison.numero }
                            .buttonStyle(BoutonTV(principal: (saisonAffichee ?? 1) == saison.numero, hauteur: 52))
                    }
                }
                Spacer()
                Text("\(vus.count) \(vus.count > 1 ? "vus" : "vu") sur \(total)").font(.system(size: 24)).foregroundStyle(Theme.texte2)
            }
            .focusSection()
            if let numero = saisonAffichee, let saison = saisons[numero] {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 30) {
                        ForEach(saison.episodes) { episode in carteEpisode(episode, serie: serie) }
                    }
                    .padding(.vertical, 26)
                }
                .scrollClipDisabled()
                .focusSection()
            } else {
                Text("Lecture de la saison…").font(.system(size: 26)).foregroundStyle(Theme.texte2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func carteEpisode(_ episode: EpisodeTMDB, serie: SerieDetail) -> some View {
        let numero = episode.numeroEpisode
        let estVu = vus.contains(numero)
        let diffuse = episode.dateDiffusion.map { $0 <= DateTMDB(.now) } ?? false
        let fichier = fichierNAS(numero)
        let date = episode.dateDiffusion.map { $0.instant(heure: 12).formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_CH"))) }
        return Button {
            if let fichier { lire(fichier) } else { cocher(episode, serie: serie, vu: estVu) }
        } label: {
            CarteLargeTV(surtitre: ["É\(episode.numero)", date].compactMap { $0 }.joined(separator: " · "), titre: episode.nom,
                         detail: estVu ? "Vu" : nil, cheminImage: episode.cheminImage ?? serie.cheminFond,
                         largeur: 420, lectureEnCoin: fichier != nil)
                .opacity(estVu ? 0.55 : 1)
        }
        .buttonStyle(.card)
        .disabled(!diffuse && !estVu && fichier == nil)
        .contextMenu {
            if let fichier { Button { lire(fichier) } label: { Label("Regarder", systemImage: "play.fill") } }
            Button { cocher(episode, serie: serie, vu: estVu) } label: {
                Label(estVu ? "Pas encore vu" : "Épisode regardé", systemImage: estVu ? "circle" : "checkmark")
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

    private var acteurs: [PersonneCasting] { film?.casting?.avecRealisateurs(15) ?? serie?.casting?.avecRealisateurs(15) ?? [] }

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

    /// La surligne de la fiche (maquette 8.0) : « Film · 2014 · 2 h 49 · Sur ton NAS », « Série · 2 saisons · Apple TV+ ».
    private var ligneFaits: String {
        var faits: [String] = [reference.type == .film ? "Film" : "Série"]
        if let annee = film?.dateSortie?.annee { faits.append("\(annee)") }
        if let minutes = film?.dureeMinutes, minutes > 0 { faits.append(minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min") }
        if let serie { faits.append(serie.nombreSaisons > 1 ? "\(serie.nombreSaisons) saisons" : "1 saison") }
        if !siens.isEmpty { faits.append("Sur ton NAS") } else if let plateforme = plateformes.first { faits.append(CarteLargeTV.nomCourt(plateforme)) }
        return faits.joined(separator: " · ")
    }

    /// Sous l'action principale, un film entamé : la barre et ce qu'il reste ; « Depuis le début » est dans « ⋯ ».
    @ViewBuilder
    private var reprise: some View {
        if reference.type == .film, let fichier = siens.first, let position = etat.positions.aReprendre(fichier.chemin), let fraction = position.fraction {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25))
                        Capsule().fill(.white).frame(width: geo.size.width * fraction)
                    }
                }
                .frame(width: 420, height: 6)
                Text([position.reste.map { PositionsLecture.reste($0) }, "« Depuis le début » dans ⋯"].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 22)).foregroundStyle(Theme.texte2)
            }
        }
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
    /// Le film du NAS dans Séance même, par le moteur de VLC (6.6) : la touche Retour ramène ici, sur la fiche.
    /// Infuse ou VLC ne servent plus que si même VLCKit échoue.
    /// `reprendre` : le bouton « Reprendre à … » repart droit à la position ; ailleurs, Séance demande (maquette n° 22).
    private func lire(_ fichier: FichierNAS, reprendre: Bool = false) {
        guard etat.motDePasseDuNAS != nil else {
            return etat.dire("Le mot de passe du NAS manque : vois Réglages › NAS.")
        }
        // 8.2 : « Qui regarde avec toi ? » avant de lancer, dans une maison à plusieurs personnes.
        if ConteneurTV.famille.aPlusieursProfils, compagnonsAChoisir == nil {
            compagnonsAChoisir = LectureAvant(fichier: fichier, reprendre: reprendre)
            return
        }
        lancer(fichier, reprendre: reprendre)
    }

    private struct LectureAvant: Identifiable {
        let fichier: FichierNAS
        let reprendre: Bool
        var id: String { fichier.chemin }
    }

    private func lancer(_ fichier: FichierNAS, reprendre: Bool) {
        etat.noterLecture(fichier)
        if reprendre, let position = etat.positions.aReprendre(fichier.chemin) {
            departLecture = position.secondes
            filmALire = fichier
        } else if etat.positions.aReprendre(fichier.chemin) != nil {
            repriseAProposer = fichier
        } else {
            departLecture = nil
            filmALire = fichier
        }
    }

    private func lireDehors(_ fichier: FichierNAS) {
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
            etat.dire("Noté : tes suggestions en tiendront compte")
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
    /// Les alertes d'une série, comme sur l'iPhone : à chaque épisode, aux nouvelles saisons, ou plus du tout.
    private func reglerAlertes(_ suivi: Suivi, _ mode: ModeAlerteSerie?) {
        suivi.alertesActives = mode != nil
        if let mode { suivi.modeAlertes = mode }
        try? contexte.save()
        etat.dire(mode == nil ? "Plus d'alertes pour « \(titre) »"
                  : mode == .saisons ? "Ton iPhone te préviendra des nouvelles saisons" : "Ton iPhone te préviendra à chaque épisode")
    }

    /// La même action que le menu de l'iPhone (`ActionsCommunes`).
    private func dejaVuAvant() async {
        guard let tmdb = etat.tmdb else { return etat.dire("Il faut la clé TMDB pour cela.") }
        do {
            try await ActionsCommunes.dejaVuAvant(reference, contexte: contexte, tmdb: tmdb)
            vu = reference.type == .film ? true : vu
            etat.dire(reference.type == .film ? "« \(titre) » marqué déjà vu" : "« \(titre) » : toute la série marquée vue")
        } catch {
            etat.dire("TMDB ne répond pas : réessaie dans un instant.")
        }
    }

    private func basculerAlertes(_ suivi: Suivi) {
        suivi.alertesActives.toggle()
        try? contexte.save()
        etat.dire(suivi.alertesActives ? "Ton iPhone te préviendra (sorties, épisodes, passages TV)" : "Plus d'alertes pour « \(titre) »")
    }

    private func prevoir(_ jour: Date) {
        try? ServiceSoiree(contexte: contexte).retenir(reference, titre: titre, cheminAffiche: cheminAffiche, soiree: ServiceSoiree.soiree(jour: jour))
        etat.dire("« \(titre) » prévu \(jour.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_CH"))))")
    }

    /// Le titre lui-même, pas la page d'accueil (6.6) : sur tvOS, le lien universel de Netflix n'ouvre que son
    /// accueil. On essaie le schéma de l'app d'abord, puis les autres adresses tant que la précédente est refusée.
    private func ouvrirPlateforme(_ plateforme: Fournisseur) {
        // 8.1 : l'identifiant du titre chez Netflix ou Disney+ arrive de Wikidata à l'ouverture de la fiche ; choisi trop
        // tôt, Séance partait sur la recherche — l'accueil de l'app. On l'attend 2,5 secondes au plus, comme sur l'iPhone.
        guard identifiants != nil || !LiensPlateformes.avecLienDirect.contains(plateforme.id) else {
            return lancerPlateforme(plateforme)
        }
        // La lecture lancée à l'ouverture de la fiche remplit `identifiants` ; on la guette.
        etat.dire("Ouverture de \(plateforme.nom)…")
        Task {
            for _ in 0..<25 where identifiants == nil {
                try? await Task.sleep(for: .milliseconds(100))
            }
            lancerPlateforme(plateforme)
        }
    }

    private func lancerPlateforme(_ plateforme: Fournisseur) {
        let liens = LiensPlateformes.liensTV(plateforme: plateforme.id, titre: titre, reference: reference, identifiants: identifiants)
        guard !liens.isEmpty else {
            return etat.dire("Ouvre \(plateforme.nom) sur l'Apple TV et cherche « \(titre) ».")
        }
        func essayer(_ reste: [URL]) {
            guard let lien = reste.first else {
                return etat.dire("\(plateforme.nom) ne s'ouvre pas d'ici : lance l'app et cherche « \(titre) ».")
            }
            ouvrir(lien) { accepte in
                if !accepte { return essayer(Array(reste.dropFirst())) }
                // 8.2 : au retour, « As-tu regardé … ? » — le film, ou le prochain épisode de la série.
                let tmdb = etat.tmdb
                Task { etat.noterLecture(await ActionsCommunes.lectureSurPlateforme(reference, titre: titre, contexte: contexte, tmdb: tmdb)) }
            }
        }
        essayer(liens)
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
        if vu { etat.demanderAvecQui(reference, titre: titre) { try ServiceSuivi(contexte: $0).marquerVu(film: film) } }
    }
}

/// Ouvrir une chaîne dans l'app blue TV, depuis n'importe quelle page de la TV (6.6). L'app ne s'ouvre pas sur une
/// chaîne mais sur une émission : Séance demande d'abord au catalogue public de Swisscom ce qui passe en ce moment.
@MainActor
enum BlueTVSurTV {
    static func ouvrir(_ idGuide: String, nom: String, etat: EtatTV, ouvrir: OpenURLAction) {
        guard let numero = LiensChaines.numero(chaine: idGuide) else {
            return etat.dire("\(nom) n'est pas dans blue TV.")
        }
        Task {
            let emission = await CatalogueBlueTV(transport: URLSession.shared).emission(chaine: numero)
            guard let lien = LiensChaines.appBlueTV(emission: emission) else {
                return etat.dire("blue TV ne répond pas : lance l'app et choisis \(nom).")
            }
            ouvrir(lien) { accepte in
                if !accepte { etat.dire("Installe blue TV sur l'Apple TV pour regarder \(nom) en direct.") }
            }
        }
    }
}
