import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

enum ReglageTV: Hashable {
    case cle, plateformes, tele, nas, videosPerso, lecture, gouts, aPropos
}

/// Les Réglages de la TV, sur le modèle de l'iPhone (piste B, EF-169) : en tête, l'état — ce qui est en ordre en vert,
/// ce qui reste à régler en orange, chaque ligne s'ouvrant sur son réglage — puis en tuiles ce que l'état ne couvre
/// pas. Tout se modifie à la télécommande ; le plus simple reste de tout recevoir de l'iPhone.
struct ReglagesTV: View {
    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(filter: #Predicate<Abonnement> { $0.actif }, sort: \Abonnement.nom) private var abonnements: [Abonnement]
    @Query(filter: #Predicate<Chaine> { $0.active }) private var chaines: [Chaine]
    @Query private var interets: [Interet]
    @State private var configuration = false
    @State private var chemin: [ReglageTV] = DepartTV.reglage.flatMap { nom in
        ["cle": ReglageTV.cle, "plateformes": .plateformes, "tele": .tele, "nas": .nas, "videosPerso": .videosPerso,
         "lecture": .lecture, "gouts": .gouts, "aPropos": .aPropos][nom].map { [$0] }
    } ?? []

    var body: some View {
        NavigationStack(path: $chemin) {
            PageTV(titre: "Réglages", sousTitre: sousTitre) {
                SectionTV(titre: "État de Séance sur cette TV") {
                    ligne(.cle, "TMDB", etat.tmdb != nil ? "Fiches, affiches et plateformes" : "Les fiches et les affiches en viennent", etat.tmdb != nil)
                    ligne(.plateformes, "Plateformes", abonnements.isEmpty ? "Pour savoir ce que tu peux regarder" : abonnements.map(\.nom).joined(separator: ", "), !abonnements.isEmpty)
                    ligne(.tele, "Télévision", chaines.isEmpty ? "Choisis tes chaînes" : "\(chaines.count) chaînes · \(libelleGuide)", !chaines.isEmpty)
                    ligne(.nas, "NAS", etat.nasPret ? "\(etat.nas.hote) · partage « \(etat.nas.partage) »" : "Tes films déjà téléchargés", etat.nasPret)
                    ligne(.videosPerso, "Vidéos personnelles", libelleVideos, !etat.videosPerso.aConfigurer(films: etat.nas))
                    ligne(.lecture, "Lecture", "Tes vidéos du NAS s'ouvrent dans \(etat.lecteur.nom)", true)
                    // Les listes arrivent de l'iPhone, de l'iPad et du Mac par le dossier « Séance » du NAS (EF-144).
                    LigneTVReglage(titre: etat.synchroEnCours ? "Synchronisation…" : "Synchronisation avec tes appareils",
                                   detail: libelleSynchro, enOrdre: etat.nasPret && etat.erreurSynchro == nil && etat.derniereSynchro != nil,
                                   desactive: etat.synchroEnCours,
                                   action: { Task { await etat.synchroniser(contexte: contexte, bavard: true) } })
                    LigneTVReglage(titre: "Tester une alerte sur l'iPhone et l'Apple Watch",
                                   detail: "L'Apple TV n'affiche pas d'alerte : ton iPhone prévient, par le NAS, à sa prochaine ouverture de Séance",
                                   symbole: "bell.badge.fill", desactive: !etat.nasPret,
                                   action: { Task { await etat.demanderEssaiAlerte() } })
                }
                SectionTV(titre: "Toi") {
                    ligne(.gouts, "Tes goûts", interets.isEmpty ? "Genres à choisir" : interets.map(\.libelle).sorted().joined(separator: ", "), nil, symbole: "heart.fill")
                }
                SectionTV(titre: "Cet appareil",
                          explication: "Le plus simple : ton iPhone envoie la clé, le NAS et tes listes d'un coup, avec un code à six chiffres.") {
                    LigneTVReglage(titre: "Configurer depuis mon iPhone", detail: "Un code ici, et tout arrive",
                                   symbole: "iphone.and.arrow.forward", action: { configuration = true }) { BoutTV(forme: .chevron) }
                    ligne(.aPropos, "À propos", "Version \(Self.version)", nil, symbole: "info.circle.fill")
                }
            }
            .navigationDestination(for: ReglageTV.self) { PageReglageTV(reglage: $0).pageOuverte() }
        }
        .fullScreenCover(isPresented: $configuration) { ConfigurationTV() }
    }

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }

    private var manques: Int {
        [etat.tmdb == nil, abonnements.isEmpty, chaines.isEmpty, !etat.nasPret, etat.videosPerso.aConfigurer(films: etat.nas)].filter { $0 }.count
    }

    private var sousTitre: String {
        manques == 0 ? "Tout est branché. Choisis une ligne pour l'ouvrir."
                     : "\(manques) réglage\(manques > 1 ? "s" : "") à compléter — les lignes orange. Choisis-en une pour l'ouvrir."
    }

    private var libelleGuide: String {
        etat.derniereLectureTele.map { "guide lu \($0.formatted(.relative(presentation: .named)))" } ?? "guide jamais lu"
    }

    private var libelleSynchro: String {
        if !etat.nasPret { return "Passe par le NAS : règle-le d'abord" }
        if let erreur = etat.erreurSynchro { return erreur }
        return etat.derniereSynchro.map { "Par le NAS · \($0.formatted(.relative(presentation: .named))). Active « Par le NAS » sur l'iPhone." }
            ?? "Par le NAS · jamais faite. Active « Par le NAS » sur l'iPhone, dans Réglages › Sauvegarde."
    }

    private var libelleVideos: String {
        if !etat.videosPerso.actif { return "Désactivées" }
        if etat.videosPerso.aConfigurer(films: etat.nas) { return "Accès à terminer" }
        return etat.videosPerso.videos.isEmpty ? "Partage « \(etat.videosPerso.reglages.acces.partage) », pas encore lu"
                                               : "\(etat.videosPerso.videos.count) vidéos"
    }

    private func ligne(_ reglage: ReglageTV, _ titre: String, _ detail: String, _ enOrdre: Bool?, symbole: String? = nil) -> some View {
        NavigationLink(value: reglage) {
            LigneTVReglage.Contenu(titre: titre, detail: detail, symbole: symbole, enOrdre: enOrdre)
        }
        .buttonStyle(LigneTV())
    }
}

extension LigneTVReglage where Accessoire == EmptyView {
    /// Le contenu seul, pour un `NavigationLink` (qui fournit lui-même le bouton).
    struct Contenu: View {
        let titre: String
        var detail: String?
        var symbole: String?
        var enOrdre: Bool?
        @Environment(\.isFocused) private var aLeFocus

        var body: some View {
            HStack(spacing: 20) {
                if let enOrdre {
                    Image(systemName: enOrdre ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 32)).foregroundStyle(enOrdre ? Color.green : Color.orange)
                } else if let symbole {
                    Image(systemName: symbole).font(.system(size: 30))
                        .foregroundStyle(aLeFocus ? AnyShapeStyle(Color.black) : AnyShapeStyle(Theme.accentClair)).frame(width: 44)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(titre).font(.system(size: 30, weight: .semibold))
                    if let detail {
                        Text(detail).font(.system(size: 23))
                            .foregroundStyle(aLeFocus ? Color.black.opacity(0.65) : Color.white.opacity(0.65)).lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
                if enOrdre == false {
                    Text("À régler").font(.system(size: 24, weight: .bold)).foregroundStyle(Color.orange)
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 26, weight: .bold)).opacity(0.45)
                }
            }
            .foregroundStyle(aLeFocus ? .black : .white)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        }
    }
}

/// Une ligne qui se choisit : elle s'éclaire quand elle a le focus.
struct LigneTV: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Corps(configuration: configuration) }

    private struct Corps: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var aLeFocus

        var body: some View {
            configuration.label
                // Le focus pose un fond blanc : le texte passe au noir, sinon il disparaît (blanc sur blanc).
                .foregroundStyle(aLeFocus ? Color.black : Color.white)
                .background(aLeFocus ? AnyShapeStyle(.white) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .scaleEffect(aLeFocus ? 1.02 : 1)
                .animation(.easeOut(duration: 0.15), value: aLeFocus)
        }
    }
}

/// Une tuile de réglage : le symbole dans l'orange de Séance, le titre, l'état courant.
struct TuileTV: View {
    let titre: String
    let symbole: String
    let valeur: String

    @Environment(\.isFocused) private var aLeFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbole).font(.system(size: 40, weight: .semibold))
                .foregroundStyle(aLeFocus ? AnyShapeStyle(Color.black) : AnyShapeStyle(Theme.accentClair))
            Text(titre).font(.system(size: 28, weight: .semibold)).lineLimit(2)
            Text(valeur).font(.system(size: 22))
                .foregroundStyle(aLeFocus ? Color.black.opacity(0.65) : Color.white.opacity(0.65))
                .lineLimit(2, reservesSpace: true)
        }
        .foregroundStyle(aLeFocus ? .black : .white)
        .frame(width: 420, alignment: .leading)
        .padding(28)
        .background(Theme.surface)
    }
}

// MARK: - Les pages

struct PageReglageTV: View {
    let reglage: ReglageTV

    var body: some View {
        switch reglage {
        case .cle: PageCleTV()
        case .plateformes: PagePlateformesTV()
        case .tele: PageChainesTV()
        case .nas: PageNASTV()
        case .videosPerso: PageVideosPersoTV()
        case .lecture: PageLectureTV()
        case .gouts: PageGoutsTV()
        case .aPropos: PageAProposTV()
        }
    }
}

private struct PageCleTV: View {
    @Environment(EtatTV.self) private var etat
    @State private var cle = ""
    @State private var message: String?
    @State private var verification = false

    var body: some View {
        PageTV(titre: "Clé TMDB", sousTitre: etat.tmdb != nil ? "Enregistrée dans le trousseau de cette Apple TV." : "Les fiches, les affiches et les plateformes en viennent.") {
            SectionTV(explication: "La même que sur ton iPhone ; elle ne voyage dans aucun fichier. Tu la retrouves sur themoviedb.org, dans Paramètres › API. Plus simple : Réglages › « Configurer depuis mon iPhone ».") {
                ChampTV(titre: "Clé d'API ou jeton de lecture", secret: true, texte: $cle)
                LigneTVReglage(titre: verification ? "Vérification…" : "Enregistrer et tester", symbole: "checkmark.seal.fill",
                               desactive: cle.isEmpty || verification, action: enregistrer)
                if let message { LigneTVReglage(titre: message, symbole: "info.circle") }
            }
        }
    }

    private func enregistrer() {
        verification = true
        Task {
            let erreur = await etat.enregistrerCleTMDB(cle)
            verification = false
            message = erreur ?? "Clé acceptée par TMDB et enregistrée."
            if erreur == nil { cle = "" }
        }
    }
}

/// Les plateformes de streaming proposées en Suisse : on coche ses abonnements (EF-149).
private struct PagePlateformesTV: View {
    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query private var abonnements: [Abonnement]
    @State private var catalogue: [FournisseurCatalogue] = []

    var body: some View {
        PageTV(titre: "Plateformes", sousTitre: "Coche tes abonnements : Séance ne dira « dans tes abonnements » que pour ceux-là.") {
            SectionTV(explication: "Disponibilités en Suisse fournies par JustWatch, via TMDB.") {
                if catalogue.isEmpty {
                    LigneTVReglage(titre: etat.tmdb == nil ? "Il faut d'abord la clé TMDB" : "Lecture du catalogue…", symbole: "hourglass")
                }
                ForEach(catalogue) { plateforme in
                    let coche = abonnements.contains { $0.providerID == plateforme.id && $0.actif }
                    LigneTVReglage(titre: plateforme.nom, action: { basculer(plateforme, coche: !coche) }) { BoutTV(forme: .coche(coche)) }
                }
            }
        }
        .task {
            let lues = (try? await etat.tmdb?.catalogueFournisseurs(.film)) ?? []
            catalogue = lues.sorted { ($0.priorites["CH"] ?? 999, $0.nom) < ($1.priorites["CH"] ?? 999, $1.nom) }.prefix(40).map { $0 }
        }
    }

    private func basculer(_ plateforme: FournisseurCatalogue, coche: Bool) {
        if let existant = abonnements.first(where: { $0.providerID == plateforme.id }) {
            existant.actif = coche
        } else if coche {
            contexte.insert(Abonnement(providerID: plateforme.id, nom: plateforme.nom, cheminLogo: plateforme.cheminLogo))
        }
        contexte.sauver()
    }
}

private struct PageChainesTV: View {
    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(sort: \Chaine.nom) private var chaines: [Chaine]

    var body: some View {
        PageTV(titre: "Télévision", sousTitre: "Les chaînes que tu reçois : leur programme alimente « Ce soir à la TV » et l'onglet TV.") {
            SectionTV(titre: "Tes chaînes") {
                ForEach(chaines) { chaine in
                    LigneTVReglage(titre: chaine.nom.isEmpty ? chaine.identifiantGuide : chaine.nom,
                                   action: { chaine.active.toggle(); contexte.sauver() }) { BoutTV(forme: .coche(chaine.active)) }
                }
            }
            SectionTV(explication: etat.derniereLectureTele.map { "Guide lu \($0.formatted(.relative(presentation: .named))). Séance le relit deux fois par jour." }
                      ?? "Le guide n'a pas encore été lu sur cette TV.") {
                LigneTVReglage(titre: etat.teleEnCours ? "Lecture du guide…" : "Relire le programme maintenant", symbole: "arrow.clockwise",
                               desactive: etat.teleEnCours, action: { Task { await etat.actualiserTele(contexte: contexte, force: true) } })
            }
        }
        .task { _ = try? ServiceProgrammesTV.preparerChaines(contexte) }
    }
}

private struct PageNASTV: View {
    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @State private var hote = ""
    @State private var partage = ""
    @State private var dossiers = ""
    @State private var utilisateur = ""
    @State private var motDePasse = ""
    @State private var message: String?
    @State private var test = false

    var body: some View {
        PageTV(titre: "NAS", sousTitre: "Tes films et tes séries déjà téléchargés, lus directement sur le disque de la maison.") {
            SectionTV(titre: "Connexion") {
                ChampTV(titre: "Adresse du NAS", invite: "192.168.1.220", texte: $hote)
                ChampTV(titre: "Partage", invite: "Films", texte: $partage)
                ChampTV(titre: "Dossiers", invite: "Dossiers, séparés par des virgules", texte: $dossiers)
                ChampTV(titre: "Compte", texte: $utilisateur)
                ChampTV(titre: "Mot de passe", invite: etat.motDePasseNAS ? "Mot de passe (déjà enregistré)" : "Mot de passe", secret: true, texte: $motDePasse)
            }
            SectionTV(explication: "Pour lire avec Infuse, ajoute aussi ce partage dans Infuse sur cette Apple TV : Séance lui demande d'ouvrir le titre dans sa bibliothèque.") {
                LigneTVReglage(titre: test ? "Connexion au NAS…" : "Enregistrer, tester et lire le NAS", symbole: "externaldrive.fill",
                               desactive: test || hote.isEmpty || partage.isEmpty || utilisateur.isEmpty, action: enregistrer)
                if let message { LigneTVReglage(titre: message, symbole: "info.circle") }
                if etat.analyseEnCours { LigneTVReglage(titre: "Lecture de la bibliothèque…", symbole: "arrow.triangle.2.circlepath") }
                if let rapport = etat.rapport {
                    LigneTVReglage(titre: "\(rapport.filmsReconnus) films et \(rapport.seriesReconnues) séries",
                                   detail: "sur \(rapport.videosLues) vidéos lues", symbole: "film.stack")
                }
            }
        }
        .onAppear {
            hote = etat.nas.hote; partage = etat.nas.partage
            dossiers = etat.nas.dossiers.joined(separator: ", "); utilisateur = etat.nas.utilisateur
        }
    }

    private func enregistrer() {
        let liste = dossiers.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        etat.enregistrerNAS(ReglagesNAS(hote: hote.trimmingCharacters(in: .whitespaces), partage: partage.trimmingCharacters(in: .whitespaces),
                                        dossiers: liste, utilisateur: utilisateur.trimmingCharacters(in: .whitespaces)), motDePasse: motDePasse)
        motDePasse = ""
        test = true
        Task {
            switch await etat.testerNAS() {
            case .reussi(let comptes):
                message = "Connexion réussie : \(comptes.values.reduce(0, +)) vidéos dans \(comptes.count) dossier\(comptes.count > 1 ? "s" : "")."
                test = false
                await etat.analyserNAS(contexte: contexte)
            case .echec(let texte):
                message = texte
                test = false
            }
        }
    }
}

/// Un seul lecteur : « Lire » n'ouvre que celui-ci, partout dans l'app.
private struct PageLectureTV: View {
    @Environment(EtatTV.self) private var etat

    var body: some View {
        PageTV(titre: "Lecture", sousTitre: "L'app qui lit tes vidéos du NAS. « Lire » n'ouvre que celle-là.") {
            SectionTV(explication: "Infuse ouvre le titre dans sa bibliothèque : le partage du NAS doit y être ajouté, sur cette Apple TV. VLC lit le fichier directement sur le NAS, avec ton compte et ton mot de passe. Tes vidéos personnelles, elles, n'ont pas de fiche : elles passent par leur adresse dans le lecteur choisi ici.") {
                ForEach(LecteurVideo.allCases) { lecteur in
                    LigneTVReglage(titre: lecteur.nom, action: { etat.choisir(lecteur) }) { BoutTV(forme: .coche(etat.lecteur == lecteur)) }
                }
            }
        }
    }
}

private struct PageGoutsTV: View {
    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query private var interets: [Interet]
    @State private var genres: [Genre] = []

    var body: some View {
        PageTV(titre: "Tes goûts", sousTitre: "Les genres que tu aimes : ils orientent les idées du soir, ici comme sur ton iPhone.") {
            SectionTV {
                if genres.isEmpty {
                    LigneTVReglage(titre: etat.tmdb == nil ? "Il faut d'abord la clé TMDB" : "Lecture des genres…", symbole: "hourglass")
                }
                ForEach(genres) { genre in
                    let coche = interets.contains { $0.genreID == genre.id }
                    LigneTVReglage(titre: genre.nom, action: { basculer(genre, coche: !coche) }) { BoutTV(forme: .coche(coche)) }
                }
            }
        }
        .task {
            let films = (try? await etat.tmdb?.genres(.film)) ?? []
            genres = films.filter { ![99, 10770].contains($0.id) }.sorted { $0.nom < $1.nom }
        }
    }

    private func basculer(_ genre: Genre, coche: Bool) {
        if coche {
            contexte.insert(Interet(libelle: genre.nom, genreID: genre.id))
        } else {
            interets.filter { $0.genreID == genre.id }.forEach(contexte.delete)
        }
        contexte.sauver()
    }
}

private struct PageAProposTV: View {
    @Environment(\.dismiss) private var fermer

    var body: some View {
        PageTV(titre: "À propos", sousTitre: "Séance \(ReglagesTV.version) sur cette Apple TV.") {
            SectionTV(explication: "Avec un compte Apple gratuit, l'app cesse de s'ouvrir au bout de sept jours : relance l'installation depuis le Mac, tes réglages restent.") {
                LigneTVReglage(titre: "Version", symbole: "number") { BoutTV(forme: .valeur(ReglagesTV.version)) }
            }
            SectionTV(explication: "Ce produit utilise l'API TMDB mais n'est ni approuvé ni certifié par TMDB. Disponibilités en Suisse fournies par JustWatch, via TMDB. Programme TV : XML TV Fr.") {
                LigneTVReglage(titre: "Retour aux réglages", symbole: "chevron.left", action: { fermer() })
            }
        }
    }
}
