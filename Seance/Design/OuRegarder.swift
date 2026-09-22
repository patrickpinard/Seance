import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Le dessin d'une pastille « où regarder » : une icône ou un logo, un texte court. `principale` : celle qui lance
/// tout de suite la lecture, en orange ; les autres restent sobres.
struct PastilleOuRegarder: View {
    var symbole: String?
    var logo: String?
    let texte: String
    var principale = false
    /// Une pastille qui ouvre quelque chose le montre d'une petite flèche.
    var ouvre = false

    var body: some View {
        HStack(spacing: 6) {
            if let logo {
                BadgeOu.logo(logo).frame(width: 20, height: 20)
            } else if let symbole {
                Image(systemName: symbole).font(.caption.weight(.bold))
                    .foregroundStyle(principale ? Color.black : Theme.accentClair)
            }
            Text(texte).font(.caption.weight(.semibold)).lineLimit(1)
            if ouvre {
                Image(systemName: "arrow.up.forward").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(principale ? Color.black : Color.primary)
        .padding(.horizontal, 11)
        .frame(minHeight: 32)
        .background {
            if principale { Capsule().fill(Theme.degradeAccent) } else { Capsule().fill(Theme.surface) }
        }
        .overlay(Capsule().strokeBorder(Theme.trait.opacity(principale ? 0 : 1)))
        .zoneDeToucher()
    }
}

/// Où regarder ce titre, tout de suite et selon ce que tu as : « Lire sur le NAS » lance la vidéo, « Netflix » ouvre
/// la plateforme sur le titre, « TF1 · ce soir à 20:55 » mène au programme TV. C'est la raison d'être de Séance :
/// la soirée, les propositions et la recherche le montrent sans ouvrir la fiche.
struct ActionsOuRegarder: View {
    /// Comment les accès se présentent : toutes les pastilles côte à côte, ou un seul bouton qui choisit
    /// pour toi — le NAS d'abord, puis une plateforme de tes abonnements, puis la chaîne qui le passe.
    enum Presentation {
        case pastilles
        case boutonUnique
        /// En tête de fiche (6.1) : le grand bouton de lecture, puis les autres accès en pastilles.
        case enTete
    }

    let reference: ReferenceTitre
    let titre: String
    /// Pour une série : l'épisode à regarder, cherché sur le NAS.
    var episode: NumeroEpisode?
    /// Ce que la page sait déjà quand aucune pastille ne s'applique : « À louer ou acheter », « Introuvable ».
    var secours: String?
    var presentation: Presentation = .pastilles

    @Environment(EtatApp.self) private var etat
    @Environment(\.openURL) private var openURL
    @Query private var fichiers: [FichierNAS]
    /// Netflix, Apple TV, Disney+ : l'identifiant du titre chez eux, s'il est connu (6.1).
    @State private var identifiants: IdentifiantsPlateformes?

    init(reference: ReferenceTitre, titre: String, episode: NumeroEpisode? = nil, secours: String? = nil,
         presentation: Presentation = .pastilles) {
        self.reference = reference
        self.titre = titre
        self.episode = episode
        self.secours = secours
        self.presentation = presentation
        let id: Int? = reference.tmdbID
        let type = reference.type.rawValue
        _fichiers = Query(filter: #Predicate<FichierNAS> { $0.tmdbID == id && $0.typeBrut == type }, sort: \FichierNAS.chemin)
    }

    /// Le fichier à lire : le film, ou l'épisode à regarder s'il est sur le NAS.
    private var fichier: FichierNAS? {
        guard reference.type == .serie else { return fichiers.first }
        guard let episode else { return nil }
        return fichiers.first { $0.saison == episode.saison && $0.episode == episode.episode }
    }

    var body: some View {
        let badges = etat.ou.badges(reference)
        // Ce qui se lance vraiment (6.1) : un seul accès, le grand bouton le lance ; plusieurs, il demande lequel. Le reste
        // (un passage TV à venir, « Sur ton NAS, en partie ») reste dit en pastilles.
        let sources = sourcesLancables(badges)
        let autres = badges.filter { !lancable($0) }
        Group {
            if presentation == .boutonUnique, !sources.isEmpty || !badges.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if sources.isEmpty, let premier = badges.first {
                        boutonPrincipal(premier)
                    } else {
                        ChoixLecture(reference: reference, titre: titre, sources: sources, style: .grand)
                    }
                    let restent = sources.isEmpty ? Array(badges.dropFirst()) : autres
                    if !restent.isEmpty {
                        Text("Aussi : " + restent.map(Self.nom).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if presentation == .enTete, !sources.isEmpty {
                // Une petite capsule plutôt qu'un bouton de toute la largeur (6.1.1) ; le reste à côté, en pastilles.
                Flux(espacement: 8) {
                    ChoixLecture(reference: reference, titre: titre, sources: sources, style: .compact)
                    ForEach(autres, id: \.self) { pastille($0) }
                }
            } else {
                pastilles(badges)
            }
        }
        .task(id: reference) {
            etat.ou.demander(reference, client: etat.tmdb)
            guard etat.ou.aUnePlateformeDirecte else { return }
            identifiants = await EtatApp.identifiants.identifiants([reference])[reference]
        }
    }

    /// Les accès lancés d'un toucher, dans l'ordre : le NAS, les plateformes, la chaîne en direct.
    private func sourcesLancables(_ badges: [EtatOu.Badge]) -> [SourceLecture] {
        badges.compactMap { badge in
            switch badge {
            case .nas: fichier.map(SourceLecture.nas)
            case .plateforme(let id, let nom, _): LiensPlateformes.lien(plateforme: id, titre: titre) == nil ? nil : .plateforme(id: id, nom: nom)
            case .tele(let chaine, _): etat.ou.chaineBlueTV(reference).map { .blueTV(idGuide: $0, chaine: chaine) }
            }
        }
    }

    /// Ce qu'un toucher lance vraiment : le fichier du NAS, une plateforme qui a un lien, la chaîne en direct.
    private func lancable(_ badge: EtatOu.Badge) -> Bool {
        switch badge {
        case .nas: fichier != nil
        case .plateforme(let id, _, _): lien(plateforme: id) != nil
        case .tele: etat.ou.chaineBlueTV(reference) != nil
        }
    }

    /// Le titre lui-même quand Wikidata connaît son identifiant chez la plateforme, sa recherche sinon.
    private func lien(plateforme id: Int) -> URL? {
        LiensPlateformes.lien(plateforme: id, titre: titre, reference: reference, identifiants: identifiants)
    }

    /// Ouvre la plateforme sur le titre, et retient ce que cela a donné (6.0) : une plateforme qui refuse le lien le dit tout de
    /// suite, et Séance garde le compte de celles qui s'ouvrent vraiment (`PlateformesApprises`), pour les préférer ensuite.
    private func ouvrirPlateforme(_ lien: URL, id: Int, nom: String) {
        Task { await LancementPlateforme.ouvrir(plateforme: id, nom: nom, titre: titre, reference: reference, etat: etat, openURL: openURL) }
    }

    /// Le seul bouton de la carte de soirée : il lance ce qui est le plus direct.
    @ViewBuilder
    private func boutonPrincipal(_ badge: EtatOu.Badge) -> some View {
        switch badge {
        case .nas:
            if let fichier {
                BoutonLectureNAS(fichier: fichier, libelle: "Regarder maintenant", grand: true)
            } else {
                PastilleOuRegarder(symbole: "externaldrive.fill", texte: reference.type == .serie ? "Sur ton NAS, en partie" : "Sur ton NAS")
            }
        case .plateforme(let id, let nom, let logo):
            if let lien = lien(plateforme: id) {
                Button { ouvrirPlateforme(lien, id: id, nom: nom) } label: { EtiquetteGrandBouton(symbole: "play.fill", texte: "Regarder sur \(nom)") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Regarder sur \(nom)")
                    .accessibilityHint("Ouvre \(nom) sur ce titre")
            } else {
                PastilleOuRegarder(logo: logo, texte: nom).accessibilityLabel("Inclus sur \(nom)")
            }
        case .tele(let chaine, let quand):
            if let idGuide = etat.ou.chaineBlueTV(reference) {
                Button { Task { await LancementBlueTV.ouvrir(chaine: idGuide, nom: chaine, etat: etat, openURL: openURL) } } label: { EtiquetteGrandBouton(symbole: "play.tv.fill", texte: "\(chaine) en direct · blue TV") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Regarder \(chaine) en direct dans blue TV")
                    .accessibilityHint("Ouvre la chaîne dans l'app blue TV")
            } else {
                Button {
                    etat.ongletDemande = .accueil
                    etat.programmeTeleDemande = true
                } label: { EtiquetteGrandBouton(symbole: "tv.fill", texte: "\(chaine) · \(quand)") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("À la TV : \(chaine), \(quand)")
                    .accessibilityHint("Ouvre le programme TV")
            }
        }
    }

    /// Le nom court d'un accès, pour la ligne « Aussi : … ».
    private static func nom(_ badge: EtatOu.Badge) -> String {
        switch badge {
        case .nas: "ton NAS"
        case .plateforme(_, let nom, _): nom
        case .tele(let chaine, let quand): "\(chaine) \(quand)"
        }
    }

    @ViewBuilder
    private func pastilles(_ badges: [EtatOu.Badge]) -> some View {
        Flux(espacement: 8) {
            ForEach(badges, id: \.self) { pastille($0) }
            if badges.isEmpty, let texte = secoursAffiche {
                Label(texte, systemImage: "cart")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 32)
            }
        }
    }

    /// Une pastille « où regarder » : elle lance ce qui se lance, dit le reste.
    @ViewBuilder
    private func pastille(_ badge: EtatOu.Badge) -> some View {
        switch badge {
        case .nas:
            if let fichier {
                BoutonLectureNAS(fichier: fichier, libelle: "Lire sur le NAS", pastille: true)
            } else {
                PastilleOuRegarder(symbole: "externaldrive.fill", texte: reference.type == .serie ? "Sur ton NAS, en partie" : "Sur ton NAS")
            }
        case .plateforme(let id, let nom, let logo):
            if let lien = lien(plateforme: id) {
                Button { ouvrirPlateforme(lien, id: id, nom: nom) } label: { PastilleOuRegarder(logo: logo, texte: nom, ouvre: true) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Regarder sur \(nom)")
                    .accessibilityHint("Ouvre \(nom) sur ce titre")
            } else {
                PastilleOuRegarder(logo: logo, texte: nom).accessibilityLabel("Inclus sur \(nom)")
            }
        case .tele(let chaine, let quand):
            if let idGuide = etat.ou.chaineBlueTV(reference) {
                Button { Task { await LancementBlueTV.ouvrir(chaine: idGuide, nom: chaine, etat: etat, openURL: openURL) } } label: {
                    PastilleOuRegarder(symbole: "play.tv.fill", texte: "\(chaine) en direct · blue TV", ouvre: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Regarder \(chaine) en direct dans blue TV")
                .accessibilityHint("Ouvre la chaîne dans l'app blue TV")
            } else {
                Button {
                    etat.ongletDemande = .accueil
                    etat.programmeTeleDemande = true
                } label: {
                    PastilleOuRegarder(symbole: "tv.fill", texte: "\(chaine) · \(quand)")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("À la TV : \(chaine), \(quand)")
                .accessibilityHint("Ouvre le programme TV")
            }
        }
    }

    /// Rien chez toi : le dire plutôt que de laisser un blanc — mais seulement une fois les plateformes lues.
    private var secoursAffiche: String? {
        if let secours { return secours }
        guard etat.ou.aDesAbonnements, etat.ou.plateformesConnues(reference) else { return nil }
        return "Dans aucun de tes abonnements"
    }
}


/// Un accès qui se lance d'un toucher (6.1).
enum SourceLecture {
    case nas(FichierNAS)
    case plateforme(id: Int, nom: String)
    /// blue TV (6.3) : l'adresse se calcule au toucher, une fois connue l'émission qui passe.
    case blueTV(idGuide: String, chaine: String)

    /// « Sur ton NAS · 1080p », « Netflix », « RTS 1 en direct · blue TV ».
    var nom: String {
        switch self {
        case .nas(let fichier): ["Sur ton NAS", fichier.qualite].compactMap { $0 }.joined(separator: " · ")
        case .plateforme(_, let nom): nom
        case .blueTV(_, let chaine): "\(chaine) en direct · blue TV"
        }
    }

    var symbole: String {
        switch self {
        case .nas: "externaldrive.fill"
        case .plateforme: "play.rectangle.fill"
        case .blueTV: "play.tv.fill"
        }
    }

    /// Le texte du petit bouton de la fiche : « NAS », « Netflix », « RTS 1 en direct ».
    var court: String {
        switch self {
        case .nas: "Sur ton NAS"
        case .plateforme(_, let nom): nom
        case .blueTV(_, let chaine): "\(chaine) en direct"
        }
    }

    /// Le texte du grand bouton quand c'est le seul accès.
    var action: String {
        switch self {
        case .nas: "Regarder maintenant"
        case .plateforme(_, let nom): "Regarder sur \(nom)"
        case .blueTV(_, let chaine): "\(chaine) en direct · blue TV"
        }
    }
}

/// ▶︎ : un seul accès, il le lance ; plusieurs (le NAS et Netflix, deux plateformes…), il demande lequel — demande de
/// Patrick (22 septembre 2026) : Séance ne choisit pas à ta place. `rond` sur les grandes cartes, `grand` en tête de fiche
/// et sur la carte d'une soirée.
struct ChoixLecture: View {
    enum Style {
        case rond
        case grand
        /// En tête de fiche (6.1.1) : une petite capsule — « ▶︎ Netflix », ou « ▶︎ Lecture ▾ » pour choisir.
        case compact
    }

    let reference: ReferenceTitre
    let titre: String
    let sources: [SourceLecture]
    var style: Style = .rond

    @Environment(EtatApp.self) private var etat
    @Environment(\.openURL) private var openURL

    var body: some View {
        if sources.count == 1, let seule = sources.first {
            Button { lancer(seule) } label: { etiquette(seule) }
                .buttonStyle(.plain)
                .accessibilityLabel(style == .rond ? "Regarder \(titre) : \(seule.nom)" : seule.action)
        } else if !sources.isEmpty {
            Menu {
                Section("Regarder « \(titre) »") {
                    ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                        Button { lancer(source) } label: { Label(source.nom, systemImage: source.symbole) }
                    }
                }
            } label: {
                etiquette(nil)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Regarder \(titre) : choisir parmi \(sources.count)")
            .accessibilityIdentifier("choixLecture")
        }
    }

    @ViewBuilder
    private func etiquette(_ seule: SourceLecture?) -> some View {
        switch style {
        case .rond:
            RondIcone(symbole: "play.fill", principal: true, taille: 44)
                .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
        case .grand:
            EtiquetteGrandBouton(symbole: seule.map { if case .blueTV = $0 { "play.tv.fill" } else { "play.fill" } } ?? "play.fill",
                                 texte: seule?.action ?? "Regarder…")
        case .compact:
            HStack(spacing: 7) {
                Image(systemName: "play.fill")
                Text(seule?.court ?? "Lecture").lineLimit(1)
                if seule == nil { Image(systemName: "chevron.down").font(.caption.weight(.heavy)) }
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(Theme.degradeAccent, in: Capsule())
            .contentShape(Capsule())
        }
    }

    private func lancer(_ source: SourceLecture) {
        switch source {
        case .nas(let fichier): lire(fichier)
        case .plateforme(let id, let nom): Task { await ouvrir(plateforme: id, nom: nom) }
        case .blueTV(let idGuide, let chaine): Task { await LancementBlueTV.ouvrir(chaine: idGuide, nom: chaine, etat: etat, openURL: openURL) }
        }
    }

    /// Le fichier du NAS dans l'app de Réglages › Lecture, comme le bouton « Lire » ; un souci se dit dans le bandeau.
    private func lire(_ fichier: FichierNAS) {
        let lecteur = etat.nas.lecteur
        switch etat.nas.lien(pour: fichier, avec: lecteur) {
        case .pret(let lien):
            openURL(lien) { acceptee in
                if acceptee {
                    etat.nas.noterLecture(fichier)
                } else {
                    etat.confirmer("\(lecteur.nom) n'a pas ouvert la vidéo : est-elle installée ? Sinon, choisis l'autre app dans Réglages › Lecture.", symbole: "exclamationmark.triangle")
                    etat.journal.noter(.lecture, "\(lecteur.nom) n'a pas pu ouvrir la vidéo.", conseil: "Vérifie que \(lecteur.nom) est installée, ou choisis l'autre app dans Réglages › Lecture.")
                }
            }
        case .motDePasseManquant:
            etat.confirmer("Mot de passe du NAS manquant : enregistre-le dans Réglages › NAS.", symbole: "exclamationmark.triangle")
        case .titreInconnu:
            etat.confirmer("Infuse ne connaît pas ce fichier : VLC le lit tel quel (Réglages › Lecture).", symbole: "exclamationmark.triangle")
        }
    }

    /// L'identifiant n'est demandé qu'au toucher (gardé ensuite) : une étagère de cartes ne réveille pas Wikidata.
    private func ouvrir(plateforme id: Int, nom: String) async {
        await LancementPlateforme.ouvrir(plateforme: id, nom: nom, titre: titre, reference: reference, etat: etat, openURL: openURL)
    }
}

/// ▶︎ sur une grande carte (6.1) : la lecture d'un toucher, sans passer par la fiche. Rien à lancer : pas de bouton, et la
/// carte ouvre la fiche comme avant.
struct BoutonLectureCarte: View {
    let reference: ReferenceTitre
    let titre: String

    @Environment(EtatApp.self) private var etat

    /// Les accès sans le NAS : les plateformes qui ont un lien, la chaîne en direct.
    @MainActor
    static func autresSources(_ reference: ReferenceTitre, titre: String, etat: EtatApp) -> [SourceLecture] {
        etat.ou.badges(reference).compactMap { badge in
            switch badge {
            case .nas: nil
            case .plateforme(let id, let nom, _): LiensPlateformes.lien(plateforme: id, titre: titre) == nil ? nil : .plateforme(id: id, nom: nom)
            case .tele(let chaine, _): etat.ou.chaineBlueTV(reference).map { .blueTV(idGuide: $0, chaine: chaine) }
            }
        }
    }

    /// Un film sur le NAS : son fichier se lance de la carte. Une série se lance par épisode, depuis sa fiche.
    @MainActor
    static func surNAS(_ reference: ReferenceTitre, etat: EtatApp) -> Bool {
        reference.type == .film && etat.ou.badges(reference).contains(.nas)
    }

    @MainActor
    static func aUneSource(_ reference: ReferenceTitre, titre: String, etat: EtatApp) -> Bool {
        surNAS(reference, etat: etat) || !autresSources(reference, titre: titre, etat: etat).isEmpty
    }

    var body: some View {
        let autres = Self.autresSources(reference, titre: titre, etat: etat)
        if Self.surNAS(reference, etat: etat) {
            AvecFichierNAS(reference: reference, titre: titre, autres: autres)
        } else if !autres.isEmpty {
            ChoixLecture(reference: reference, titre: titre, sources: autres)
        }
    }
}

/// Le fichier d'un film du NAS, cherché seulement pour les cartes qui en ont un.
private struct AvecFichierNAS: View {
    let reference: ReferenceTitre
    let titre: String
    let autres: [SourceLecture]
    @Query private var fichiers: [FichierNAS]

    init(reference: ReferenceTitre, titre: String, autres: [SourceLecture]) {
        self.reference = reference
        self.titre = titre
        self.autres = autres
        let id: Int? = reference.tmdbID
        let type = reference.type.rawValue
        _fichiers = Query(filter: #Predicate<FichierNAS> { $0.tmdbID == id && $0.typeBrut == type }, sort: \FichierNAS.chemin)
    }

    var body: some View {
        ChoixLecture(reference: reference, titre: titre, sources: fichiers.prefix(1).map(SourceLecture.nas) + autres)
    }
}

/// Ouvrir un titre sur sa plateforme (6.3). Deux attentes s'y cachaient, sans rien à l'écran : la page exacte du
/// titre, que Séance demande à Wikidata — une requête réseau, une seconde d'ordinaire, plusieurs en 4G ou quand le
/// service traîne —, puis l'ouverture de l'app elle-même, qui passe par un lien universel. Le sablier dit maintenant
/// ce qui se passe, et l'attente est bornée : passé deux secondes et demie, la plateforme s'ouvre sur sa recherche,
/// et la réponse en retard remplit la réserve pour la fois suivante.
@MainActor
enum LancementPlateforme {
    static let attenteMax = Duration.milliseconds(2500)

    static func ouvrir(plateforme id: Int, nom: String, titre: String, reference: ReferenceTitre,
                       etat: EtatApp, openURL: OpenURLAction) async {
        let identifiants = await etat.pendantLOuverture(de: nom, etape: "Séance retrouve la page de « \(titre) » sur \(nom)…") {
            await identifiantsRapides(reference)
        }
        guard let lien = LiensPlateformes.lien(plateforme: id, titre: titre, reference: reference, identifiants: identifiants) else { return }
        let direct = identifiants.map { LiensPlateformes.direct(plateforme: id, reference: reference, identifiants: $0) != nil } ?? false
        etat.annoncerOuverture(nom, etape: direct ? "Ouverture du titre dans \(nom)…" : "\(nom) n'a pas de page connue pour ce titre : Séance ouvre sa recherche.")
        openURL(lien) { acceptee in
            etat.ouverture = nil
            PlateformesApprises.noter(id, ouverte: acceptee)
            if !acceptee { etat.confirmer("\(nom) ne s'ouvre pas d'ici : lance l'app et cherche « \(titre) »", symbole: "exclamationmark.triangle") }
        }
    }

    /// L'identifiant s'il arrive à temps ; sinon rien, et la recherche fera l'affaire. La requête n'est pas annulée :
    /// elle finira de remplir la réserve.
    static func identifiantsRapides(_ reference: ReferenceTitre) async -> IdentifiantsPlateformes? {
        let recherche = Task { await EtatApp.identifiants.identifiants([reference])[reference] }
        return await withTaskGroup(of: Reponse.self) { groupe in
            groupe.addTask { Reponse(identifiants: await recherche.value) }
            groupe.addTask { try? await Task.sleep(for: attenteMax); return Reponse(identifiants: nil) }
            let premiere = await groupe.next()
            groupe.cancelAll()
            return premiere?.identifiants
        }
    }

    private struct Reponse: Sendable {
        let identifiants: IdentifiantsPlateformes?
    }
}

/// Le sablier d'une ouverture au-dehors (6.3) : ce qui s'ouvre, et ce que Séance fait pendant ce temps.
struct SablierOuverture: View {
    let ouverture: EtatApp.Ouverture

    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(Theme.accent)
            Text("Ouverture de \(ouverture.plateforme)…").font(.headline)
            Text(ouverture.etape)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ouverture de \(ouverture.plateforme). \(ouverture.etape)")
    }
}

extension SablierOuverture {
    /// Le voile et le sablier, posés une fois pour toutes à la racine de l'app.
    struct Calque: ViewModifier {
        @Environment(EtatApp.self) private var etat

        func body(content: Content) -> some View {
            content
                .overlay {
                    if let ouverture = etat.ouverture {
                        ZStack {
                            Color.black.opacity(0.28).ignoresSafeArea()
                            SablierOuverture(ouverture: ouverture)
                        }
                        .transition(.opacity)
                    }
                }
                .animation(.snappy, value: etat.ouverture)
        }
    }
}

/// Ouvrir une chaîne dans blue TV (6.3). Son app ne s'ouvre pas sur une chaîne mais sur une émission : Séance demande
/// d'abord au catalogue public de Swisscom ce qui passe en ce moment, puis ouvre `tvguide://…` — l'adresse que le
/// lecteur web de blue TV utilise lui-même pour passer à l'app. Sans réponse, l'app s'ouvre sur son guide ; sans app
/// (le Mac), c'est le lecteur web tv.blue.ch.
@MainActor
enum LancementBlueTV {
    static func ouvrir(chaine idGuide: String, nom: String, etat: EtatApp, openURL: OpenURLAction) async {
        guard let numero = LiensChaines.numero(chaine: idGuide) else { return }
        #if targetEnvironment(macCatalyst)
        let siteDabord = true
        #else
        let siteDabord = false
        #endif
        if !siteDabord {
            let emission = await etat.pendantLOuverture(de: "blue TV", etape: "Séance demande à blue TV ce qui passe sur \(nom) en ce moment…") {
                await CatalogueBlueTV(transport: URLSession.shared).emission(chaine: numero)
            }
            if let lien = LiensChaines.appBlueTV(emission: emission) {
                etat.annoncerOuverture("blue TV", etape: "\(nom) en direct.")
                if await ouvre(lien, openURL: openURL) { etat.ouverture = nil; return }
            }
        }
        if let site = LiensChaines.siteBlueTV(chaine: idGuide) {
            etat.annoncerOuverture("blue TV", etape: "L'app n'a pas répondu : Séance passe par tv.blue.ch.")
            if await ouvre(site, openURL: openURL) { etat.ouverture = nil; return }
        }
        etat.ouverture = nil
        etat.confirmer("blue TV ne s'ouvre pas d'ici : lance l'app et choisis \(nom)", symbole: "exclamationmark.triangle")
    }

    private static func ouvre(_ lien: URL, openURL: OpenURLAction) async -> Bool {
        await withCheckedContinuation { suite in
            openURL(lien) { acceptee in suite.resume(returning: acceptee) }
        }
    }
}

/// L'habillage d'un grand bouton d'action, du même dessin que « Regarder maintenant » du NAS.
struct EtiquetteGrandBouton: View {
    let symbole: String
    let texte: String

    var body: some View {
        Label(texte, systemImage: symbole)
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundStyle(.black)
            .background(Theme.degradeAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Le badge lui-même, en coin d'affiche.
struct BadgeOu: View {
    let reference: ReferenceTitre

    @Environment(EtatApp.self) private var etat

    var body: some View {
        let badges = etat.ou.badges(reference)
        HStack(spacing: 4) {
            ForEach(badges, id: \.self) { badge in
                switch badge {
                case .nas: pastille("externaldrive.fill")
                case .plateforme(_, _, let logo): BadgeOu.logo(logo)
                case .tele: pastille("tv.fill")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badges.map(BadgeOu.libelle).joined(separator: ", "))
        .accessibilityHidden(badges.isEmpty)
        // Dans une cellule qui assemble son libellé (une grille d'affiches), le titre s'annonce avant l'endroit où
        // regarder : « John Wick, sur ton NAS » et non l'inverse.
        .accessibilitySortPriority(-1)
    }

    static func libelle(_ badge: EtatOu.Badge) -> String {
        switch badge {
        case .nas: "Sur ton NAS"
        case .plateforme(_, let nom, _): nom
        case .tele(let chaine, let quand): "\(chaine), \(quand)"
        }
    }

    static func logo(_ chemin: String?) -> some View {
        ImageDistante(url: ImageTMDB.url(chemin, .logo), coins: 6)
            .frame(width: 24, height: 24)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 3)
    }

    private func pastille(_ symbole: String) -> some View {
        Image(systemName: symbole)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Theme.accentClair)
            .frame(width: 24, height: 24)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1))
    }
}

/// En tête de fiche : où regarder ce titre, d'un coup d'œil — les mêmes pastilles que sur les affiches, avec leur nom.
/// Le détail (location, achat, prochaines diffusions) reste dans le bloc « Où regarder », plus bas.
struct RangeeOu: View {
    let reference: ReferenceTitre

    @Environment(EtatApp.self) private var etat

    var body: some View {
        let badges = etat.ou.badges(reference)
        if !badges.isEmpty {
            Flux(espacement: 8) {
                ForEach(badges, id: \.self) { badge in
                    HStack(spacing: 6) {
                        switch badge {
                        case .nas: Image(systemName: "externaldrive.fill").foregroundStyle(Theme.accentClair)
                        case .plateforme(_, _, let logo): BadgeOu.logo(logo).frame(width: 20, height: 20)
                        case .tele: Image(systemName: "tv.fill").foregroundStyle(Theme.accentClair)
                        }
                        Text(BadgeOu.libelle(badge)).font(.caption.weight(.semibold)).lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 30)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.trait))
                }
            }
            .padding(.horizontal, 20)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Où regarder : " + badges.map(BadgeOu.libelle).joined(separator: ", "))
            .task(id: reference) { etat.ou.demander(reference, client: etat.tmdb) }
        }
    }
}
