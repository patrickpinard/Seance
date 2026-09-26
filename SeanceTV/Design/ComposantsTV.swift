import SeanceKit
import SeanceDonnees
import SwiftData
import SwiftUI
import UIKit

/// Image distante, gardée en mémoire : sur la TV, on revient sans cesse sur les mêmes étagères.
struct ImageTV: View {
    let url: URL?
    var symboleVide = "film"

    @State private var image: UIImage?

    /// 8.1 : la même mémoire que l'iPhone — 150 Mo au plus, une requête par image —, à la taille d'un écran 4K.
    static let memoire = MemoireImages(coteMax: 2200) { url in
        try? await URLSession.shared.data(from: url).0
    }

    var body: some View {
        Rectangle().fill(Theme.surface)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if !symboleVide.isEmpty {
                    Image(systemName: symboleVide).font(.system(size: 44)).foregroundStyle(.tertiary)
                }
            }
            .clipped()
            .task(id: url) { await charger() }
    }

    private func charger() async {
        guard let url else { image = nil; return }
        if let connue = Self.memoire.enMemoire(url) { image = connue; return }
        image = nil
        for tentative in 0..<3 {
            if let lue = await Self.memoire.image(url) {
                image = lue
                return
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(600 * (tentative + 1)))
        }
    }
}

/// Une affiche 2:3 qui se choisit à la télécommande : elle grandit quand elle a le focus, et son titre s'allume.
struct AfficheTV: View {
    let titre: String
    let sousTitre: String?
    let cheminAffiche: String?
    var marque: String?

    static let largeur: CGFloat = 250

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ImageTV(url: ImageTMDB.url(cheminAffiche, .afficheGrande))
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    if let marque {
                        Image(systemName: marque)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.accentClair)
                            .padding(10)
                            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .padding(10)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(titre).font(.system(size: 26, weight: .semibold)).lineLimit(2, reservesSpace: true)
                if let sousTitre {
                    Text(sousTitre).font(.system(size: 22)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: Self.largeur)
    }
}

/// Une grande carte 16/9, image plein cadre et texte dessus : la soirée, un passage TV.
struct CarteLargeTV: View {
    let surtitre: String?
    let titre: String
    let detail: String?
    let cheminImage: String?
    /// Un symbole en coin : sur ton NAS, déjà vu — les mêmes marques que sur l'iPhone.
    var marque: String?
    /// Une carte de grille, plus petite que celle d'une étagère d'accueil.
    var largeur: CGFloat = CarteLargeTV.largeur
    /// Souvenirs (6.2) : pas d'image, un halo orange et ce grand SF Symbol à droite, comme sur l'iPhone.
    var icone: String?
    /// La première image de la vidéo (6.4), quand Séance a pu la tirer du NAS : elle remplace le halo à icône.
    var vignette: Image?
    /// Le ▶︎ blanc en bas à droite (charte 8.0) : la carte lance la vidéo.
    var lectureEnCoin = false
    /// Le titre, pour dire où le regarder (6.3) : les logos des plateformes, le NAS, la chaîne.
    var reference: ReferenceTitre?
    /// La part déjà vue (8.0, « Reprendre ») : une fine barre blanche en bas de la carte.
    var progression: Double?
    /// Un passage en cours à la TV : la pastille rouge « EN DIRECT » devant la ligne d'origine.
    var enDirect = false

    @Environment(EtatTV.self) private var etatTV

    static let largeur: CGFloat = 620
    /// Trois par rangée sur un écran de télévision, avec les marges.
    static let largeurGrille: CGFloat = 520

    /// Où on le regarde, pour la ligne d'origine quand l'appelant n'en donne pas (maquette 8.0) : « Sur ton NAS »,
    /// ou le nom court de la plateforme.
    private var origine: String? {
        guard let reference else { return nil }
        for badge in etatTV.ou.badges(reference) {
            switch badge {
            case .nas: return "Sur ton NAS"
            case .plateforme(_, let nom, _): return Self.nomCourt(nom)
            case .tele: continue
            }
        }
        return nil
    }

    /// Le ▶︎ blanc : sur une carte qui lance la lecture, ou d'un titre que tu peux regarder (NAS, plateforme).
    private var jouable: Bool {
        if lectureEnCoin { return true }
        guard let reference else { return false }
        return etatTV.ou.badges(reference).contains { if case .tele = $0 { false } else { true } }
    }

    static func nomCourt(_ nom: String) -> String {
        switch nom {
        case "Amazon Prime Video", "Amazon Prime Video with Ads": "Prime Video"
        case "Disney Plus": "Disney+"
        case "Apple TV Plus", "Apple TV+": "Apple TV+"
        case "Netflix basic with Ads", "Netflix Standard with Ads": "Netflix"
        default: nom
        }
    }

    /// Le texte suit la taille de la carte : une petite carte de grille ne s'étouffe pas sous un grand titre.
    private var echelle: CGFloat { min(max(largeur / Self.largeurGrille, 0.72), 1.15) }

    var body: some View {
        let surtitre = self.surtitre ?? origine
        let lectureEnCoin = jouable
        let k = echelle
        return Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if let vignette {
                    vignette.resizable().scaledToFill().clipped()
                } else if let icone {
                    FondSouvenirTV(symbole: icone)
                } else {
                    ImageTV(url: ImageTMDB.url(cheminImage, .fondGrand))
                }
            }
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.25), .black.opacity(0.88)], startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomTrailing) {
                // Charte 8.0 : ni logos ni marque sur les cartes — la ligne d'origine dit où ; le ▶︎ blanc, en bas à
                // droite comme sur l'iPhone, dit que la carte lance la lecture.
                if lectureEnCoin {
                    Image(systemName: "play.fill")
                        .font(.system(size: 26 * k, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 64 * k, height: 64 * k)
                        .background(.white, in: Circle())
                        .padding(22 * k)
                        .padding(.bottom, progression == nil ? 0 : 12)
                }
            }
            .task(id: reference) {
                guard let reference else { return }
                etatTV.ou.demander(reference, client: etatTV.tmdb)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    if surtitre != nil || enDirect {
                        // Charte 8.0 : la ligne d'origine en blanc atténué ; l'orange est réservé à ce qui se touche.
                        HStack(spacing: 10) {
                            if enDirect {
                                Text("EN DIRECT").font(.system(size: 20, weight: .heavy)).foregroundStyle(.white)
                                    .padding(.horizontal, 10).padding(.vertical, 3)
                                    .background(Theme.rouge, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            if let surtitre { Text(surtitre).font(.system(size: 24 * k, weight: .heavy)).foregroundStyle(.white.opacity(0.78)).lineLimit(1) }
                        }
                    }
                    Text(titre).font(.system(size: 36 * k, weight: .bold)).lineLimit(2)
                    if let detail {
                        Text(detail).font(.system(size: 24 * k)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                    }
                }
                .foregroundStyle(.white)
                .padding(24 * k)
                .padding(.trailing, lectureEnCoin ? 70 * k : 0)
                .padding(.bottom, progression == nil ? 0 : 10)
            }
            .overlay(alignment: .bottom) {
                if let progression {
                    GeometryReader { cadre in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.25))
                            Capsule().fill(.white).frame(width: cadre.size.width * progression)
                        }
                    }
                    .frame(height: 6)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }
            }
            .frame(width: largeur)
            .accessibilityElement(children: .combine)
    }
}

/// Où regarder, en coin de carte sur la TV (6.3) : le logo de chaque plateforme de tes abonnements, le disque du NAS,
/// l'écran d'une chaîne — les mêmes marques que sur l'iPhone, en plus grand.
struct BadgeOuTV: View {
    let reference: ReferenceTitre

    @Environment(EtatTV.self) private var etat

    var body: some View {
        // Deux pastilles au plus (6.4) : à trois mètres, quatre logos empilés dans un coin ne se lisent plus.
        let badges = Array(etat.ou.badges(reference).prefix(2))
        HStack(spacing: 8) {
            ForEach(badges, id: \.self) { badge in
                switch badge {
                case .nas: pastille("externaldrive.fill")
                case .plateforme(_, _, let logo):
                    ImageTV(url: ImageTMDB.url(logo, .logo), symboleVide: "play.tv")
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1))
                case .tele: pastille("tv.fill")
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func pastille(_ symbole: String) -> some View {
        Image(systemName: symbole)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(Theme.accentClair)
            .frame(width: 44, height: 44)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1))
    }
}

/// Le fond d'une carte de souvenir sur la TV (6.2) : le halo orange et la grande icône de l'iPhone.
struct FondSouvenirTV: View {
    let symbole: String

    var body: some View {
        GeometryReader { cadre in
            ZStack {
                Theme.eleve
                // Maquette 8.0, n° 11 : le halo et l'icône orange des souvenirs restent, leur signe distinctif.
                RadialGradient(colors: [Theme.accentClair.opacity(0.36), Theme.accent.opacity(0.10), .clear],
                               center: UnitPoint(x: 0.78, y: 0.42), startRadius: 0, endRadius: cadre.size.width * 0.55)
                Image(systemName: symbole)
                    .resizable()
                    .scaledToFit()
                    .frame(width: cadre.size.width * 0.3, height: cadre.size.height * 0.46)
                    .foregroundStyle(Theme.accentClair)
                    .position(x: cadre.size.width * 0.78, y: cadre.size.height * 0.37)
            }
        }
    }
}

/// Une étagère : un titre, et une rangée qu'on parcourt de gauche à droite.
struct EtagereTV<Contenu: View>: View {
    let titre: String
    /// Charte 8.0 : plus de phrase sous le titre d'une étagère — le titre suffit. Gardé pour VoiceOver seulement.
    var sousTitre: String?
    /// « Tout voir » (8.0) : la dernière tuile de la rangée ouvre la page qui montre tout ce que l'étagère résume. En
    /// bout de rangée plutôt qu'à côté du titre : depuis une carte, la télécommande y va tout droit.
    var toutVoir: (() -> Void)?
    /// La largeur des cartes de la rangée, pour que la tuile « Tout voir » ait leur hauteur.
    var largeurCartes: CGFloat = CarteLargeTV.largeurGrille
    @ViewBuilder let contenu: Contenu

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(titre).font(.system(size: 38, weight: .bold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityHint(sousTitre ?? "")
                .padding(.horizontal, MargesTV.bord)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 40) {
                    contenu
                    if let toutVoir {
                        Button(action: toutVoir) {
                            VStack(spacing: 16) {
                                Image(systemName: "arrow.right.circle").font(.system(size: 60, weight: .semibold))
                                Text("Tout voir").font(.system(size: 30, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(width: 300, height: largeurCartes * 9 / 16)
                            .background(Color.white.opacity(0.1))
                        }
                        .buttonStyle(.card)
                        .accessibilityLabel("Tout voir : \(titre)")
                    }
                }
                    .padding(.horizontal, MargesTV.bord)
                    .padding(.vertical, 30)   // la place de l'affiche qui grandit au focus
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

enum MargesTV {
    /// tvOS demande de laisser libre le bord de l'écran, que certains téléviseurs rognent.
    static let bord: CGFloat = 80
}

/// Un écran sans contenu dit ce qu'il montrera et d'où cela viendra (EF-139).
struct VideTV: View {
    let symbole: String
    let titre: String
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbole).font(.system(size: 80)).foregroundStyle(Theme.degradeAccent)
            Text(titre).font(.system(size: 42, weight: .bold))
            Text(message).font(.system(size: 28)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 1100)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 120)
        // Focalisable : une page qui n'a que ce message doit garder la télécommande en main (touche Retour).
        .focusable()
    }
}

/// Le bouton de Séance sur la TV. Le style par défaut de tvOS 26 ne se dessinait pas du tout sur le fond sombre d'une
/// fiche (ni plateau ni libellé) : celui-ci est toujours visible, et devient blanc à libellé noir quand il a le focus,
/// comme dans les apps d'Apple. `principal` : l'action qu'on est venu faire (lire), en orange.
struct BoutonTV: ButtonStyle {
    var principal = false
    /// `nil` : le bouton prend la hauteur de son contenu (une tuile de jour), au lieu des 76 points d'un bouton d'action.
    var hauteur: CGFloat? = 76

    func makeBody(configuration: Configuration) -> some View {
        Corps(configuration: configuration, principal: principal, hauteur: hauteur)
    }

    private struct Corps: View {
        let configuration: Configuration
        let principal: Bool
        let hauteur: CGFloat?
        @Environment(\.isFocused) private var aLeFocus
        @Environment(\.isEnabled) private var actif

        var body: some View {
            configuration.label
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(aLeFocus || principal ? .black : .white)
                .padding(.horizontal, hauteur == nil ? 0 : 34)
                .frame(height: hauteur)
                .background {
                    let forme = RoundedRectangle(cornerRadius: 20, style: .continuous)
                    // Maquette 8.0 de la TV : ce qui est choisi, et le bouton principal, sont blancs ; le focus les
                    // soulève et les borde. L'orange reste aux liens.
                    if aLeFocus || principal {
                        forme.fill(.white)
                    } else {
                        forme.fill(Color.white.opacity(0.14)).overlay(forme.strokeBorder(Color.white.opacity(0.22), lineWidth: 2))
                    }
                }
                .overlay {
                    if aLeFocus, principal {
                        RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.accentClair, lineWidth: 3)
                    }
                }
                .shadow(color: .black.opacity(aLeFocus ? 0.45 : 0), radius: 18, y: 10)
                .scaleEffect(aLeFocus ? 1.08 : (configuration.isPressed ? 0.97 : 1))
                .opacity(actif ? 1 : 0.4)
                .animation(.easeOut(duration: 0.15), value: aLeFocus)
        }
    }
}

/// Un rond de 76 points pour une action qui tient dans une icône (Ce soir, ⋯, les pouces, l'étoile) : blanc au focus,
/// orange quand c'est choisi, gris sinon — les mêmes ronds que sur l'iPhone (charte 8.0).
struct BoutonRondTV: ButtonStyle {
    var choisi = false

    func makeBody(configuration: Configuration) -> some View {
        Corps(configuration: configuration, choisi: choisi)
    }

    private struct Corps: View {
        let configuration: Configuration
        let choisi: Bool
        @Environment(\.isFocused) private var aLeFocus

        var body: some View {
            configuration.label
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(aLeFocus || choisi ? Color.black : Color.white)
                .frame(width: 76, height: 76)
                .background {
                    if aLeFocus || choisi {
                        Circle().fill(.white)
                    } else {
                        Circle().fill(Color.white.opacity(0.14)).overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 2))
                    }
                }
                .overlay { if aLeFocus, choisi { Circle().strokeBorder(Theme.accentClair, lineWidth: 3) } }
                .shadow(color: .black.opacity(aLeFocus ? 0.45 : 0), radius: 14, y: 8)
                .scaleEffect(aLeFocus ? 1.1 : (configuration.isPressed ? 0.95 : 1))
                .animation(.easeOut(duration: 0.15), value: aLeFocus)
        }
    }
}

/// Le prénom de qui regarde, en haut à gauche (6.1) : une capsule discrète, orange sur fond sombre ; au focus, blanche
/// et agrandie comme les autres boutons de la TV.
struct PastilleQuiRegardeTV: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Corps(configuration: configuration)
    }

    private struct Corps: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var aLeFocus

        var body: some View {
            configuration.label
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(aLeFocus ? Color.black : Theme.accentClair)
                .padding(.horizontal, 22)
                .frame(height: 56)
                .background(aLeFocus ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.black.opacity(0.45)), in: Capsule())
                .scaleEffect(aLeFocus ? 1.08 : (configuration.isPressed ? 0.97 : 1))
                .animation(.easeOut(duration: 0.15), value: aLeFocus)
        }
    }
}

/// Une page ouverte depuis une autre doit toujours pouvoir se refermer à la télécommande. tvOS n'envoie la touche
/// Retour (Menu) à une page que si un de ses éléments a le focus : une page faite seulement de texte — « À propos » —
/// laissait la touche partir au système, qui quittait l'app. Ici la page la traite elle-même.
private struct PageOuverte: ViewModifier {
    @Environment(\.dismiss) private var fermer

    func body(content: Content) -> some View {
        content.onExitCommand { fermer() }
    }
}

extension View {
    func pageOuverte() -> some View { modifier(PageOuverte()) }
}

/// Le sélecteur de Séance, version télécommande : des cases de même largeur, l'active en orange à texte noir.
/// Le même geste que sur l'iPhone (charte graphique), avec les tailles de la TV.
struct SelecteurTV<Valeur: Hashable>: View {
    @Binding var selection: Valeur
    let cases: [(valeur: Valeur, nom: String)]
    /// Un SF Symbol devant chaque nom (Mes listes : les mêmes six boutons que sur l'iPhone).
    var symbole: (Valeur) -> String? = { _ in nil }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                ForEach(cases, id: \.valeur) { element in
                    Button { selection = element.valeur } label: {
                        if let nom = symbole(element.valeur) { Label(element.nom, systemImage: nom) } else { Text(element.nom) }
                    }
                        .buttonStyle(BoutonTV(principal: selection == element.valeur))
                }
            }
            .padding(.horizontal, MargesTV.bord)
            .padding(.vertical, 14)
        }
        .scrollClipDisabled()
        .focusSection()
    }
}

/// Une tuile de jour, comme la rangée de jours de l'iPhone : nom, quantième, et ce qu'il y a ce jour-là.
struct TuileJourTV: View {
    let nom: String
    let numero: Int
    /// Gardé pour VoiceOver : la maquette 8.0 ne montre que le jour et son numéro.
    let detail: String

    var body: some View {
        VStack(spacing: 2) {
            Text(nom).font(.system(size: 20, weight: .semibold)).opacity(0.75)
            Text("\(numero)").font(.system(size: 40, weight: .heavy))
        }
        .frame(width: 110, height: 110)
        .accessibilityElement(children: .combine)
        .accessibilityHint(detail)
    }
}

/// L'appui long sur une carte (maquette 8.0, n° 21) : les gestes de l'iPhone, dans les mêmes mots — Regarder, Voir
/// la fiche, Un autre soir, Terminé, Retirer de la soirée — et, selon la carte, Ma liste, Retirer de Reprendre, Pas pour
/// moi.
struct MenuCarteTV: ViewModifier {
    let reference: ReferenceTitre
    let titre: String
    var cheminAffiche: String?
    /// Le chemin de la vidéo entamée, sur une carte de « Reprendre ».
    var reprise: String?
    /// La soirée où le titre est prévu, sur une carte de « Ta soirée ».
    var soiree: String?

    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Environment(\.ouvrirTV) private var ouvrirTV
    @State private var autreSoir = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if let ouvrirTV {
                    Button { ouvrirTV.regarder(reference) } label: { Label("Regarder", systemImage: "play.fill") }
                    Button { ouvrirTV.fiche(reference) } label: { Label("Voir la fiche", systemImage: "info.circle") }
                }
                Button { autreSoir = true } label: { Label("Un autre soir", systemImage: "calendar.badge.clock") }
                if soiree == nil {
                    let prevu = ((try? contexte.fetch(FetchDescriptor<SelectionSoir>())) ?? [])
                        .contains { $0.reference == reference && $0.soiree == ServiceSoiree.soiree() }
                    if !prevu {
                        Button { ceSoir() } label: { Label("Ce soir", systemImage: "moon.stars") }
                    }
                }
                if reference.type == .film, (try? ServiceSuivi(contexte: contexte).estVu(reference)) != true {
                    Button { Task { await terminer() } } label: { Label("Terminé", systemImage: "checkmark") }
                }
                let suivi = try? ServiceSuivi(contexte: contexte).suivi(reference)
                if suivi == nil {
                    Button { Task { await ajouterALaListe() } } label: { Label("Ma liste", systemImage: "plus") }
                }
                if let reprise {
                    Button(role: .destructive) {
                        etat.oublierPosition(reprise)
                        etat.dire("« \(titre) » retiré de Reprendre")
                    } label: { Label("Retirer de Reprendre", systemImage: "xmark.circle") }
                }
                if let soiree {
                    Button(role: .destructive) {
                        try? ServiceSoiree(contexte: contexte).retirer(reference, soiree: soiree)
                        etat.dire("« \(titre) » retiré de ta soirée")
                    } label: { Label("Retirer de la soirée", systemImage: "minus.circle") }
                } else if reprise == nil, suivi?.statut != .exclu {
                    Button(role: .destructive) {
                        try? ServiceGouts(contexte: contexte).jamais(reference, titre: titre, cheminAffiche: cheminAffiche)
                        etat.dire("« \(titre) » ne te sera plus proposé")
                    } label: { Label("Pas pour moi", systemImage: "hand.thumbsdown") }
                }
            }
            .fullScreenCover(isPresented: $autreSoir) {
                ChoixSoireeTV(titre: titre) { jour in
                    try? ServiceSoiree(contexte: contexte).retenir(reference, titre: titre, cheminAffiche: cheminAffiche,
                                                                  soiree: ServiceSoiree.soiree(jour: jour))
                    etat.dire("« \(titre) » prévu pour ce soir-là")
                }
            }
    }

    private func ceSoir() {
        try? ServiceSoiree(contexte: contexte).retenir(reference, titre: titre, cheminAffiche: cheminAffiche)
        etat.dire("« \(titre) » ajouté à ta soirée")
    }

    /// Ma liste demande la fiche du titre (ses genres, sa durée) : sans clé TMDB, on le dit.
    private func ajouterALaListe() async {
        guard let tmdb = etat.tmdb else { return etat.dire("Il faut la clé TMDB pour ajouter à Ma liste.") }
        let service = ServiceSuivi(contexte: contexte)
        if reference.type == .film, let film = try? await tmdb.film(reference.tmdbID) {
            _ = try? service.suivre(film: film)
        } else if reference.type == .serie, let serie = try? await tmdb.serie(reference.tmdbID) {
            _ = try? service.suivre(serie: serie)
        } else {
            return etat.dire("TMDB ne répond pas : réessaie dans un instant.")
        }
        etat.dire("« \(titre) » ajouté à Ma liste")
    }

    private func terminer() async {
        guard let tmdb = etat.tmdb else { return etat.dire("Il faut la clé TMDB pour marquer un film vu.") }
        guard let film = try? await tmdb.film(reference.tmdbID) else { return etat.dire("TMDB ne répond pas : réessaie dans un instant.") }
        try? ServiceSuivi(contexte: contexte).marquerVu(film: film)
        if let soiree { try? ServiceSoiree(contexte: contexte).retirer(reference, soiree: soiree) }
        etat.dire("« \(titre) » marqué vu")
    }
}

extension View {
    func menuCarteTV(_ reference: ReferenceTitre, titre: String, cheminAffiche: String? = nil, reprise: String? = nil,
                     soiree: String? = nil) -> some View {
        modifier(MenuCarteTV(reference: reference, titre: titre, cheminAffiche: cheminAffiche, reprise: reprise, soiree: soiree))
    }
}
