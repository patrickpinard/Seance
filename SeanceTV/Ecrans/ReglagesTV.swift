import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

enum ReglageTV: Hashable {
    case cle, plateformes, tele, nas, videosPerso, lecture, gouts, aPropos, versions
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
    /// Leurs affiches habillent les cartes.
    @Query private var suivis: [Suivi]
    @Query private var fichiers: [FichierNAS]
    @State private var configuration = false
    @State private var quiRegarde = false
    /// La ligne qui a le focus : l'aperçu de droite la décrit.
    @FocusState private var focus: String?
    /// 8.1 : le réglage montré à droite, en entier — celui de la ligne qui a (ou vient d'avoir) le focus. `nil` sur une
    /// ligne d'action (Synchroniser, Famille…) : l'explication prend sa place.
    @State private var affiche: ReglageTV?
    @State private var chemin: [ReglageTV] = DepartTV.reglage.flatMap { nom in
        ["cle": ReglageTV.cle, "plateformes": .plateformes, "tele": .tele, "nas": .nas, "videosPerso": .videosPerso,
         "lecture": .lecture, "gouts": .gouts, "aPropos": .aPropos, "versions": .versions][nom].map { [$0] }
    } ?? []

    var body: some View {
        NavigationStack(path: $chemin) {
            // 8.0, charte commune : la liste groupée de l'iPhone — Où regarder, Toi, La maison, L'app. 8.1 (demande de
            // Patrick) : à droite, le réglage lui-même, pas un aperçu — on y entre d'un appui à droite, sans changer de page,
            // comme dans les Réglages de tvOS.
            HStack(alignment: .top, spacing: 50) {
                ScrollView {
                        VStack(alignment: .leading, spacing: 34) {
                            // 8.7, comme sur l'iPhone : en tête, ce qui manque, nommé ; la page de droite montre le premier.
                            etatDesReglages
                            groupe("Où regarder") {
                                ForEach(points.filter { $0.reglage != .cle }, id: \.reglage) { point in
                                    ligne(point.reglage, point.titre, point.valeur, point.enOrdre, symbole: point.symbole)
                                        .focused($focus, equals: point.titre)
                                }
                            }
                            // 8.4 : « Toi » (tes goûts, tester une alerte) est dans les Préférences, comme sur l'iPhone.
                            groupe("La maison") {
                                Button { Task { await etat.synchroniser(contexte: contexte, bavard: true) } } label: {
                                    LigneTVReglage.Contenu(titre: etat.synchroEnCours ? "Synchronisation…" : "Synchroniser maintenant",
                                                           detail: etat.derniereSynchro.map { $0.formatted(.relative(presentation: .named)) },
                                                           symbole: "arrow.triangle.2.circlepath")
                                }
                                .buttonStyle(LigneTV())
                                .disabled(etat.synchroEnCours)
                                .focused($focus, equals: "Synchroniser maintenant")
                                Button { configuration = true } label: {
                                    LigneTVReglage.Contenu(titre: "Configurer depuis mon iPhone", detail: nil, symbole: "iphone.and.arrow.forward")
                                }
                                .buttonStyle(LigneTV())
                                .focused($focus, equals: "Configurer depuis mon iPhone")
                                Button { quiRegarde = true } label: {
                                    LigneTVReglage.Contenu(titre: "Famille", detail: QuiRegardeTV.nom(ConteneurTV.famille.actif), symbole: "person.2.fill")
                                }
                                .buttonStyle(LigneTV())
                                .focused($focus, equals: "Famille")
                            }
                            groupe("L'app") {
                                if let tmdb = points.first(where: { $0.reglage == .cle }) {
                                    ligne(tmdb.reglage, tmdb.titre, tmdb.valeur, tmdb.enOrdre, symbole: tmdb.symbole)
                                        .focused($focus, equals: tmdb.titre)
                                }
                                ligne(.aPropos, "À propos", Self.version, nil, symbole: "info.circle.fill")
                                    .focused($focus, equals: "À propos")
                            }
                        }
                        .padding(.leading, MargesTV.bord)
                        .padding(.vertical, 40)
                }
                .frame(width: 800 + MargesTV.bord)
                .focusSection()
                Group {
                    if let affiche {
                        PageReglageTV(reglage: affiche, integree: true)
                            .id(affiche)
                    } else if let premier = points.first(where: { $0.enOrdre == false })?.reglage ?? points.first?.reglage {
                        // 8.4 : jamais de colonne vide — le premier réglage à compléter, sinon le premier de la liste.
                        PageReglageTV(reglage: premier, integree: true)
                            .id(premier)
                    } else {
                        apercu
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .focusSection()
            }
            .onChange(of: focus) { _, ligne in
                // Le focus parti dans la page de droite (`nil`) : elle reste affichée.
                guard let ligne else { return }
                affiche = Self.reglage(ligne)
            }
            .navigationDestination(for: ReglageTV.self) { PageReglageTV(reglage: $0).pageOuverte() }
        }
        .fullScreenCover(isPresented: $configuration) { ConfigurationTV() }
        .fullScreenCover(isPresented: $quiRegarde) {
            QuiRegardeTV { profil in
                quiRegarde = false
                ConteneurTV.changerDeProfil(vers: profil)
            }
        }
    }

    /// « 2 réglages à compléter — NAS et Vidéos personnelles. Le reste est branché. », ou « Séance est prête ».
    private var etatDesReglages: some View {
        let manques = points.filter { $0.enOrdre == false }.map(\.titre)
        return VStack(alignment: .leading, spacing: 6) {
            Text(manques.isEmpty ? "Séance est prête" : manques.count > 1 ? "\(manques.count) réglages à compléter" : "1 réglage à compléter")
                .font(.system(size: 34, weight: .heavy))
            Text(manques.isEmpty ? "Tout est branché." : manques.formatted(.list(type: .and).locale(Locale(identifier: "fr_CH"))) + ". Le reste est branché.")
                .font(.system(size: 24))
                .foregroundStyle(Theme.texte2)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Piste B : héros et grandes cartes

    private struct Point {
        let reglage: ReglageTV
        let titre: String
        let symbole: String
        let detail: String
        let enOrdre: Bool
        /// La valeur courte, à droite de la ligne (maquette 8.0, n° 19) ; `detail` va dans l'aperçu.
        var valeur = ""
    }

    private var points: [Point] {
        [Point(reglage: .cle, titre: "TMDB", symbole: "film.stack", detail: etat.tmdb != nil ? "Fiches, affiches et plateformes" : "Les fiches et les affiches en viennent",
               enOrdre: etat.tmdb != nil, valeur: etat.tmdb != nil ? "Clé enregistrée" : "À saisir"),
         Point(reglage: .plateformes, titre: "Plateformes", symbole: "play.tv.fill",
               detail: abonnements.isEmpty ? "Pour savoir ce que tu peux regarder" : abonnements.map { CarteLargeTV.nomCourt($0.nom) }.joined(separator: ", "),
               enOrdre: !abonnements.isEmpty, valeur: abonnements.isEmpty ? "À choisir" : "\(abonnements.count)"),
         Point(reglage: .tele, titre: "TV", symbole: "tv.fill", detail: chaines.isEmpty ? "Choisis tes chaînes" : "\(chaines.count) chaînes\n\(libelleGuide)",
               enOrdre: !chaines.isEmpty, valeur: chaines.isEmpty ? "À choisir" : "\(chaines.count) chaînes"),
         Point(reglage: .nas, titre: "NAS", symbole: "externaldrive.fill",
               detail: etat.nasPret ? "\(etat.nas.hote) · partage « \(etat.nas.partage) »\n\(libelleBibliotheque)" : "Tes films déjà téléchargés",
               enOrdre: etat.nasPret, valeur: etat.nasPret ? (etat.nas.dossiers.isEmpty ? etat.nas.partage : etat.nas.dossiers.joined(separator: ", ")) : "À configurer"),
         Point(reglage: .videosPerso, titre: "Vidéos personnelles", symbole: "video.fill", detail: libelleVideos,
               enOrdre: !etat.videosPerso.aConfigurer(films: etat.nas), valeur: etat.videosPerso.actif ? "\(etat.videosPerso.videos.count)" : "Désactivées"),
         Point(reglage: .lecture, titre: "Lecture", symbole: "play.circle.fill", detail: "Séance (VLCKit) : tous les formats, dans l'app",
               enOrdre: true, valeur: "Séance")]
    }

    /// « 7 titres, 9 vidéos », pour l'aperçu du NAS.
    private var libelleBibliotheque: String {
        let titres = Set(fichiers.compactMap(\.reference)).count
        return "\(titres) titre\(titres > 1 ? "s" : ""), \(fichiers.count) vidéo\(fichiers.count > 1 ? "s" : "")"
    }

    private var affiches: [String] {
        Array(Set(suivis.compactMap(\.cheminAffiche) + fichiers.compactMap(\.cheminAffiche))).sorted()
    }

    private func affiche(_ rang: Int) -> String? {
        affiches.isEmpty ? nil : affiches[(rang * 7 + 3) % affiches.count]
    }

    /// Un groupe de la liste : son titre en capitales, ses lignes sur une surface arrondie (maquette 8.0, n° 19).
    private func groupe(_ titre: String, @ViewBuilder _ lignes: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titre.uppercased()).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.texte2).padding(.leading, 8)
            VStack(spacing: 2) { lignes() }
                .padding(8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.trait, lineWidth: 1))
        }
    }

    /// À droite, ce que la ligne choisie règle : son symbole en grand, son nom, son état.
    private var apercu: some View {
        let point = points.first { $0.titre == focus }
        let symbole = point?.symbole ?? Self.symboles[focus ?? ""] ?? "gearshape.fill"
        return VStack(spacing: 22) {
            Image(systemName: symbole)
                .font(.system(size: 120, weight: .semibold))
                .foregroundStyle(Theme.accentClair)
            Text(focus ?? "Réglages").font(.system(size: 44, weight: .heavy))
            if let point {
                Text(point.detail).font(.system(size: 26)).foregroundStyle(Theme.texte2).multilineTextAlignment(.center).frame(maxWidth: 620)
                if !point.enOrdre {
                    Label("À régler", systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.attention)
                }
            } else if let texte = Self.explications[focus ?? ""] {
                Text(texte).font(.system(size: 26)).foregroundStyle(Theme.texte2).multilineTextAlignment(.center).frame(maxWidth: 620)
            }
        }
        .animation(.easeOut(duration: 0.15), value: focus)
    }

    /// Le réglage d'une ligne de la liste, d'après son titre ; `nil` pour une ligne d'action.
    private static func reglage(_ titre: String) -> ReglageTV? {
        ["TMDB": .cle, "Plateformes": .plateformes, "TV": .tele, "NAS": .nas, "Vidéos personnelles": .videosPerso,
         "Lecture": .lecture, "Tes goûts": .gouts, "À propos": .aPropos][titre]
    }

    private static let symboles = ["Tes goûts": "heart.fill", "Tester une alerte": "bell.badge.fill", "Synchroniser maintenant": "arrow.triangle.2.circlepath",
                                   "Configurer depuis mon iPhone": "iphone.and.arrow.forward", "Famille": "person.2.fill", "À propos": "info.circle.fill"]

    /// Ce que dit l'aperçu des lignes qui ne sont pas des réglages à compléter.
    private static let explications = [
        "Tes goûts": "Les genres que tu aimes : ils orientent tes suggestions, ici comme sur ton iPhone.",
        "Tester une alerte": "Ton iPhone préviendra à sa prochaine ouverture.",
        "Synchroniser maintenant": "Par le dossier « Séance » du NAS : tes listes, tes notes et où tu en es arrivent des autres appareils.",
        "Configurer depuis mon iPhone": "Un code à six chiffres ici, et la clé TMDB, le NAS et tes réglages arrivent de ton iPhone.",
        "Famille": "Chacun ses listes et ses goûts : choisis qui regarde.",
        "À propos": "La version de Séance sur cette Apple TV, et l'historique des versions.",
    ]

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

    /// Une ligne de réglage : le focus montre sa page à droite ; un clic y montre aussi (l'appui à droite y entre).
    private func ligne(_ reglage: ReglageTV, _ titre: String, _ detail: String, _ enOrdre: Bool?, symbole: String? = nil) -> some View {
        Button { affiche = reglage } label: {
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
            // Maquette 8.0, n° 19 : l'icône dans un carré teinté, le nom, la valeur courte à droite, le point d'état, le chevron.
            HStack(spacing: 20) {
                if let symbole {
                    Image(systemName: symbole).font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.accentClair)
                        .frame(width: 50, height: 50)
                        .background(Theme.accent.opacity(aLeFocus ? 0.22 : 0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                Text(titre).font(.system(size: 28, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 12)
                if let detail {
                    Text(detail).font(.system(size: 22))
                        .foregroundStyle(aLeFocus ? Color.black.opacity(0.6) : Theme.texte2).lineLimit(1)
                }
                if let enOrdre {
                    Circle().fill(enOrdre ? Theme.vert : Theme.attention).frame(width: 12, height: 12)
                }
                Image(systemName: "chevron.right").font(.system(size: 22, weight: .bold)).opacity(0.45)
            }
            .foregroundStyle(aLeFocus ? .black : .white)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
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
        // Un seul élément, qui dit son titre et sa valeur : VoiceOver (et la télécommande des tests) le lisent.
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Les pages

struct PageReglageTV: View {
    let reglage: ReglageTV
    /// Dans la colonne de droite des Réglages (8.1) plutôt qu'en page à part : moins de marge, un titre plus petit.
    var integree = false

    var body: some View {
        Group {
            switch reglage {
            case .cle: PageCleTV()
            case .plateformes: PagePlateformesTV()
            case .tele: PageChainesTV()
            case .nas: PageNASTV()
            case .videosPerso: PageVideosPersoTV()
            case .lecture: PageLectureTV()
            case .gouts: PageGoutsTV()
            case .aPropos: PageAProposTV()
            case .versions: PageVersionsTV()
            }
        }
        .environment(\.pageIntegree, integree)
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
    @State private var aIdentifier: DemandeIdentification?
    @Query(sort: \Chaine.nom) private var chaines: [Chaine]

    var body: some View {
        PageTV(titre: "TV", sousTitre: "Les chaînes que tu reçois : leur programme alimente Regarder › TV.") {
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
            // 8.4 : les films du guide que TMDB n'a pas permis de reconnaître sans hésiter, à identifier.
            if let films = etat.rapportTele?.filmsNonReconnus, !films.isEmpty {
                SectionTV(titre: "Films non reconnus",
                          explication: "Un film du guide ne paraît au programme que s'il est reconnu dans TMDB sans hésitation ; identifie ceux-ci parmi ses propositions.") {
                    ForEach(films) { film in
                        LigneTVReglage(titre: film.titre, detail: film.annee.map(String.init), symbole: "questionmark.square.dashed",
                                       action: { aIdentifier = .guide(titre: film.titre, annee: film.annee) }) { BoutTV(forme: .valeur("Identifier")) }
                    }
                }
            }
            SectionIdentifiesTV(guide: true, demande: $aIdentifier)
        }
        .fullScreenCover(item: $aIdentifier) { demande in IdentificationTV(demande: demande) }
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
    @State private var aIdentifier: DemandeIdentification?

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
            // 8.4 : les vidéos non reconnues s'identifient dans Regarder › NAS › Non reconnus ; les choix faits se revoient ici.
            SectionIdentifiesTV(guide: false, demande: $aIdentifier)
        }
        .fullScreenCover(item: $aIdentifier) { demande in IdentificationTV(demande: demande) }
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
struct PageLectureTV: View {
    @Environment(EtatTV.self) private var etat
    /// 8.1 : la langue et les sous-titres que le lecteur choisit tout seul, pour la personne qui regarde.
    @State private var pistes = PreferencesPistes.lire(profil: ConteneurTV.famille.actif.id)

    var body: some View {
        PageTV(titre: "Lecture", sousTitre: "Tes films, tes séries et tes vidéos du NAS se lisent dans Séance, avec VLCKit, directement sur le NAS.") {
            SectionTV(titre: "Langue et sous-titres",
                      explication: "Choisis à chaque film quand le fichier les propose. Un clic passe au choix suivant ; « Langue et sous-titres » dans le lecteur change d'avis pour un film seulement.") {
                LigneTVReglage(titre: "Langue", detail: nomLangue(pistes.audio, vo: true), symbole: "speaker.wave.2.fill", action: {
                    let codes = PreferencesPistes.langues.map(\.code) + [""]
                    pistes.audio = codes[((codes.firstIndex(of: pistes.audio) ?? 0) + 1) % codes.count]
                    enregistrer()
                })
                LigneTVReglage(titre: "Sous-titres", detail: pistes.sousTitres.nom, symbole: "captions.bubble.fill", action: {
                    let tous = PreferencesPistes.SousTitres.allCases
                    pistes.sousTitres = tous[((tous.firstIndex(of: pistes.sousTitres) ?? 0) + 1) % tous.count]
                    enregistrer()
                })
                if pistes.sousTitres != .jamais {
                    LigneTVReglage(titre: "Langue des sous-titres", detail: nomLangue(pistes.langueSousTitres, vo: false), symbole: "textformat", action: {
                        let codes = PreferencesPistes.langues.map(\.code)
                        pistes.langueSousTitres = codes[((codes.firstIndex(of: pistes.langueSousTitres) ?? 0) + 1) % codes.count]
                        enregistrer()
                    })
                }
            }
            SectionTV(titre: "Si VLCKit n'y arrive pas",
                      explication: "Rare : un fichier que même VLCKit ne lit pas part dans cette app. Infuse ouvre le titre dans sa bibliothèque (le partage du NAS doit y être ajouté) ; VLC lit le fichier directement sur le NAS.") {
                ForEach(LecteurVideo.allCases) { lecteur in
                    LigneTVReglage(titre: lecteur.nom, action: { etat.choisir(lecteur) }) { BoutTV(forme: .coche(etat.lecteur == lecteur)) }
                }
            }
        }
    }

    private func nomLangue(_ code: String, vo: Bool) -> String {
        if code.isEmpty, vo { return "Version originale" }
        return PreferencesPistes.langues.first { $0.code == code }?.nom ?? code
    }

    private func enregistrer() {
        pistes.enregistrer(profil: ConteneurTV.famille.actif.id)
    }
}

/// Tes goûts : ouverte depuis Réglages, ou depuis tes Préférences (8.0).
struct PageGoutsTV: View {
    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query private var interets: [Interet]
    @State private var genres: [Genre] = []

    var body: some View {
        PageTV(titre: "Tes goûts", sousTitre: "Les genres que tu aimes : ils orientent tes suggestions, ici comme sur ton iPhone.") {
            SectionTV {
                if genres.isEmpty {
                    LigneTVReglage(titre: etat.tmdb == nil ? "Il faut d'abord la clé TMDB" : "Lecture des genres…", symbole: "hourglass")
                }
                ForEach(genres) { genre in
                    let coche = interets.contains { $0.genreID == genre.id && $0.poids >= 0 }
                    LigneTVReglage(titre: genre.nom, action: { basculer(genre, coche: !coche) }) { BoutTV(forme: .coche(coche)) }
                }
            }
            // « Pas ce genre » (8.7), comme dans Préférences › Toi sur l'iPhone.
            let ecartes = interets.filter { $0.poids < 0 }.sorted { $0.libelle < $1.libelle }
            if !ecartes.isEmpty {
                SectionTV(titre: "Genres que tu as écartés",
                          explication: "« Pas ce genre », dans l'appui long de la proposition de l'accueil : ces genres ne te sont plus proposés.") {
                    ForEach(ecartes) { interet in
                        LigneTVReglage(titre: interet.libelle, symbole: "hand.thumbsdown", action: {
                            if let genre = interet.genreID { try? ServiceGouts(contexte: contexte).reprendreGenre(genre) }
                        }) { BoutTV(forme: .valeur("Reproposer")) }
                    }
                }
            }
        }
        .task {
            let films = (try? await etat.tmdb?.genres(.film)) ?? []
            genres = films.filter { ![99, 10770].contains($0.id) }.sorted { $0.nom < $1.nom }
        }
    }

    private func basculer(_ genre: Genre, coche: Bool) {
        // Cocher un genre écarté le rend aimé : l'un remplace l'autre.
        interets.filter { $0.genreID == genre.id }.forEach(contexte.delete)
        if coche {
            contexte.insert(Interet(libelle: genre.nom, genreID: genre.id))
        }
        contexte.sauver()
    }
}

private struct PageAProposTV: View {
    /// Les arrêts brusques de Séance sur cette TV (8.2), notés au lancement suivant.
    @State private var plantages = Plantages.liste

    var body: some View {
        // 8.2.1 (demande de Patrick) : ni « Retour aux réglages » — la liste est à gauche —, ni « Comment ça marche ».
        PageTV(titre: "À propos") {
            SectionTV {
                LigneTVReglage(titre: "Version", detail: InstallationsVersions.libelle(ReglagesTV.version), symbole: "number") {
                    BoutTV(forme: .valeur(ReglagesTV.version))
                }
                // Le même historique que sur l'iPhone (6.3).
                NavigationLink(value: ReglageTV.versions) {
                    LigneTVReglage(titre: "Ce que chaque version a apporté", detail: "L'historique de Séance, version par version",
                                   symbole: "list.bullet.rectangle") {
                        BoutTV(forme: .chevron)
                    }
                }
                .buttonStyle(LigneTV())
            }
            if !plantages.isEmpty {
                SectionTV(titre: "Arrêts de Séance",
                          explication: "Séance s'est arrêtée brusquement à ces moments-là, sur la page indiquée. Si cela se répète, dis-le : la page aide à trouver la cause.") {
                    ForEach(plantages) { plantage in
                        LigneTVReglage(titre: plantage.date.formatted(.dateTime.day().month(.wide).hour().minute().locale(Locale(identifier: "fr_CH"))),
                                       detail: [plantage.page.map { "Page « \($0) »" }, "version \(plantage.version)"].compactMap { $0 }.joined(separator: " · "),
                                       symbole: "bolt.trianglebadge.exclamationmark")
                    }
                    LigneTVReglage(titre: "Effacer la liste", symbole: "trash", action: {
                        Plantages.effacer()
                        plantages = []
                    }) { EmptyView() }
                }
            }
            // La mention que demandent les conditions de TMDB.
            Text("Ce produit utilise l'API TMDB mais n'est ni approuvé ni certifié par TMDB. Disponibilités en Suisse : JustWatch, via TMDB. Programme TV : XML TV Fr.")
                .font(.system(size: 22))
                .foregroundStyle(Theme.texte2)
        }
    }
}
