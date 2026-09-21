import SeanceKit
import SwiftUI
import UIKit

/// Image distante avec silhouette pendant le chargement (UX-12, UX-13).
///
/// `AsyncImage` abandonnait une image interrompue (défilement rapide, carrousels paresseux, Wi-Fi
/// chargé) et ne réessayait jamais : certaines affiches restaient grises. Ici, le chargement est
/// relancé à chaque apparition, réessayé trois fois, et les images déjà vues viennent du cache.
struct ImageDistante: View {
    let url: URL?
    var coins: CGFloat = 12
    /// Ce qui tient la place d'une image absente : une pellicule, ou une silhouette pour une personne.
    var symboleVide = "film"

    @State private var image: UIImage?
    @State private var echec = false

    init(url: URL?, coins: CGFloat = 12, symboleVide: String = "film") {
        self.url = url
        self.coins = coins
        self.symboleVide = symboleVide
        _image = State(initialValue: url.flatMap { CacheImages.partage.enMemoire($0) })
    }

    /// L'image remplit la place proposée sans jamais imposer sa propre taille : une image de fond
    /// large ne doit pas élargir l'écran.
    var body: some View {
        Rectangle().fill(Theme.surface)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
                } else if url == nil || echec {
                    Image(systemName: symboleVide).foregroundStyle(.tertiary)
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: coins, style: .continuous))
            .task(id: url) { await charger() }
    }

    private func charger() async {
        guard let url else {
            image = nil
            return
        }
        if let connue = CacheImages.partage.enMemoire(url) {
            image = connue
            return
        }
        image = nil
        echec = false
        for tentative in 0..<3 {
            if let chargee = await CacheImages.partage.charger(url) {
                withAnimation(.easeOut(duration: 0.2)) { image = chargee }
                return
            }
            // Vue sortie de l'écran : on reprendra à sa prochaine apparition.
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(800 * (tentative + 1)))
        }
        echec = true
    }
}

/// Affiches et fonds TMDB : décodés une fois, gardés en mémoire, et sur disque par `URLCache`.
final class CacheImages: @unchecked Sendable {
    static let partage = CacheImages()

    private let memoire = NSCache<NSURL, UIImage>()
    private let cacheDisque: URLCache
    private let session: URLSession
    /// Préchargements en cours, pour ne pas demander deux fois la même image.
    private var enCours: Set<URL> = []
    private let verrou = NSLock()

    private init() {
        memoire.countLimit = 400
        let configuration = URLSessionConfiguration.default
        cacheDisque = URLCache(memoryCapacity: 30 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024, directory: DossiersSeance.images)
        configuration.urlCache = cacheDisque
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 20
        configuration.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: configuration)
    }

    /// « Vider » dans À propos : les affiches se rechargeront à l'affichage.
    func vider() {
        memoire.removeAllObjects()
        cacheDisque.removeAllCachedResponses()
    }

    func enMemoire(_ url: URL) -> UIImage? {
        memoire.object(forKey: url as NSURL)
    }

    /// Charge en avance les images qu'on va faire défiler — les grandes cartes de l'accueil surtout : quand la
    /// rangée arrive à l'écran, l'image est déjà là. Ce qui est connu ou déjà en route n'est pas redemandé, et
    /// le chargement se fait en tâche de fond, derrière ce que l'écran affiche déjà.
    func precharger(_ urls: [URL], limite: Int = 12) {
        for url in retenir(urls, limite: limite) {
            Task(priority: .utility) {
                _ = await charger(url)
                terminer(url)
            }
        }
    }

    /// Réserve les images à charger : celles qui manquent et que personne ne charge déjà.
    private func retenir(_ urls: [URL], limite: Int) -> [URL] {
        verrou.lock()
        defer { verrou.unlock() }
        var retenues: [URL] = []
        for url in urls where enMemoire(url) == nil && !enCours.contains(url) {
            guard retenues.count < limite else { break }
            enCours.insert(url)
            retenues.append(url)
        }
        return retenues
    }

    private func terminer(_ url: URL) {
        verrou.lock()
        enCours.remove(url)
        verrou.unlock()
    }

    /// `nil` en cas d'échec ou d'annulation : l'appelant décide de réessayer.
    func charger(_ url: URL) async -> UIImage? {
        guard let (donnees, reponse) = try? await session.data(from: url),
              (reponse as? HTTPURLResponse)?.statusCode ?? 200 < 400,
              let image = await UIImage(data: donnees)?.byPreparingForDisplay()
        else { return nil }
        memoire.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// Anneau de note TMDB (UX-03, UX-04).
struct AnneauNote: View {
    let pourcentage: Int
    var diametre: CGFloat = 36

    var body: some View {
        let couleur = Theme.couleurNote(pourcentage)
        ZStack {
            Circle().fill(.black.opacity(0.85))
            Circle().stroke(couleur.opacity(0.25), lineWidth: diametre * 0.085)
                .padding(diametre * 0.09)
            Circle().trim(from: 0, to: CGFloat(pourcentage) / 100)
                .stroke(couleur, style: StrokeStyle(lineWidth: diametre * 0.085, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(diametre * 0.09)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(pourcentage)").font(.system(size: diametre * 0.32, weight: .bold))
                Text("%").font(.system(size: diametre * 0.16, weight: .semibold)).baselineOffset(diametre * 0.1)
            }
            .foregroundStyle(.white)
        }
        .frame(width: diametre, height: diametre)
        .accessibilityElement()
        .accessibilityLabel("note \(pourcentage) %")
    }
}

/// Carrousel horizontal d'images. Sur le Mac, la molette d'une souris défile à la verticale et un clic ne fait pas
/// glisser : des flèches ‹ › apparaissent sur les bords, tant qu'il reste quelque chose à voir de ce côté.
/// Posé sur une rangée, un bouton laissait passer le clic à l'affiche du dessous, qui ouvrait sa fiche : tant que le
/// pointeur survole une flèche, la rangée ignore les clics.
struct DefilementHorizontal<Contenu: View>: View {
    @ViewBuilder var contenu: Contenu

    @State private var position = ScrollPosition(edge: .leading)
    @State private var geometrie = Geometrie()
    @State private var survolFleche = false

    private struct Geometrie: Equatable {
        var decalage: CGFloat = 0
        var visible: CGFloat = 0
        var total: CGFloat = 0

        var auDebut: Bool { decalage <= 1 }
        var aLaFin: Bool { decalage + visible >= total - 1 }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            contenu
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: Geometrie.self) { g in
            Geometrie(decalage: g.contentOffset.x, visible: g.containerSize.width, total: g.contentSize.width)
        } action: { _, nouvelle in
            geometrie = nouvelle
        }
        #if targetEnvironment(macCatalyst)
        .allowsHitTesting(!survolFleche)
        .overlay(alignment: .leading) {
            if !geometrie.auDebut {
                FlecheDefilement(sens: .gauche, survol: $survolFleche) { defiler(-1) }
                    .padding(.leading, 8)
            }
        }
        .overlay(alignment: .trailing) {
            if !geometrie.aLaFin {
                FlecheDefilement(sens: .droite, survol: $survolFleche) { defiler(1) }
                    .padding(.trailing, 8)
            }
        }
        #endif
    }

    /// Avance ou recule des quatre cinquièmes de la largeur visible : la dernière carte reste en vue.
    private func defiler(_ sens: CGFloat) {
        let maximum = max(0, geometrie.total - geometrie.visible)
        let cible = min(max(0, geometrie.decalage + sens * geometrie.visible * 0.8), maximum)
        withAnimation(.snappy) { position.scrollTo(x: cible) }
    }
}

/// Flèche ‹ › des carrousels et du bandeau, pour le Mac. `survol` dit au contenu du dessous d'ignorer les clics.
struct FlecheDefilement: View {
    enum Sens { case gauche, droite }

    let sens: Sens
    @Binding var survol: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: sens == .gauche ? "chevron.left" : "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.7), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 6)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
        // Une flèche qui disparaît sous le pointeur (bout de la rangée) ne doit pas laisser la rangée inerte.
        .onDisappear { survol = false }
        .help(sens == .gauche ? "Précédents" : "Suivants")
        .accessibilityLabel(sens == .gauche ? "Faire défiler vers la gauche" : "Faire défiler vers la droite")
    }
}


/// Puce de choix unique (plateforme, saison, type) : même apparence que les critères d'Explorer.
struct PuceFiltre: View {
    let libelle: String
    var active = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(libelle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .foregroundStyle(active ? Color.black : Color.primary)
                .background(active ? AnyShapeStyle(Theme.degradeAccent) : AnyShapeStyle(Theme.surface), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Titre de section avec lien facultatif à droite.
struct TitreSection<Accessoire: View>: View {
    let titre: String
    @ViewBuilder var accessoire: Accessoire

    @Environment(\.dynamicTypeSize) private var tailleTexte

    var body: some View {
        HStack(spacing: 10) {
            // Le titre tient sur une ligne : il rétrécit un peu plutôt que de passer à la ligne ; en texte agrandi, deux.
            Text(titre)
                .font(.title3.weight(.bold))
                .lineLimit(tailleTexte.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
            Spacer(minLength: 4)
            accessoire
        }
        .padding(.horizontal, 20)
    }
}

extension TitreSection where Accessoire == EmptyView {
    init(_ titre: String) {
        self.titre = titre
        accessoire = EmptyView()
    }
}

/// Bouton d'action réduit à son icône, rond : les rangées d'actions restent compactes sur iPhone.
/// Le libellé n'est pas affiché mais reste lu par VoiceOver. Un appui prolongé affiche une bulle
/// qui explique le bouton ; sur Mac, la même explication apparaît au survol.
struct BoutonIcone: View {
    let symbole: String
    let libelle: String
    /// Action principale : fond orange.
    var principal = false
    /// État atteint (vu, dans la liste) : icône orange sur fond teinté.
    var actif = false
    var taille: CGFloat = 46
    /// Phrase de la bulle d'aide ; à défaut, le libellé.
    var explication: String?
    let action: () -> Void

    @State private var bulle = false

    var body: some View {
        RondIcone(symbole: symbole, principal: principal, actif: actif, taille: taille)
            .onTapGesture(perform: action)
            .onLongPressGesture(minimumDuration: 0.45) { bulle = true }
            .sensoryFeedback(.selection, trigger: actif)
            .sensoryFeedback(.impact(weight: .light), trigger: bulle) { _, nouveau in nouveau }
            .popover(isPresented: $bulle, arrowEdge: .bottom) {
                BulleAide(titre: libelle, texte: explication)
            }
            .help(explication ?? libelle)
            .accessibilityElement()
            .accessibilityLabel(libelle)
            .accessibilityHint(explication ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

/// Bulle d'aide d'un bouton : son nom, puis ce qu'il fait.
struct BulleAide: View {
    let titre: String
    var texte: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre).font(.subheadline.weight(.semibold))
            if let texte {
                Text(texte).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: 280, alignment: .leading)
        .presentationCompactAdaptation(.popover)
    }
}

/// L'apparence de `BoutonIcone`, réutilisable comme étiquette d'un menu.
struct RondIcone: View {
    let symbole: String
    var principal = false
    var actif = false
    var taille: CGFloat = 46

    var body: some View {
        Image(systemName: symbole)
            .font(.system(size: taille * 0.38, weight: .bold))
            .contentTransition(.symbolEffect(.replace))
            .frame(width: taille, height: taille)
            .foregroundStyle(principal ? AnyShapeStyle(Color.black) : actif ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.primary))
            .background(
                principal ? AnyShapeStyle(Theme.degradeAccent) : actif ? AnyShapeStyle(Theme.accent.opacity(0.18)) : AnyShapeStyle(Theme.surface),
                in: Circle()
            )
            .overlay(Circle().strokeBorder(actif ? Theme.accent.opacity(0.5) : Color.clear, lineWidth: 1))
            .contentShape(Circle())
    }
}

/// Message d'une section vide ou en erreur, partout le même : icône, phrase, action éventuelle.
struct MessageEtat: View {
    enum Ton { case information, attente, probleme }

    let texte: String
    var symbole = "info.circle"
    var ton = Ton.information
    var libelleAction: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if ton == .attente {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: ton == .probleme ? "exclamationmark.triangle.fill" : symbole)
                    .foregroundStyle(ton == .probleme ? Color.orange : Color.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(texte)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let libelleAction, let action {
                    Button(libelleAction, action: action)
                        .font(.footnote.weight(.semibold))
                        .tint(Theme.accent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 20)
    }
}

/// « Tout voir » à droite d'un titre de section de l'accueil.
struct BoutonToutVoir: View {
    let action: () -> Void

    var body: some View {
        // Un lien d'une ligne : il répond sur 44 points (audit d'accessibilité), sans grandir à l'écran.
        Button(action: action) {
            Text("Tout voir").font(.subheadline.weight(.semibold)).fixedSize().zoneDeToucher(largeur: 44)
        }
        .tint(Theme.accent)
        .padding(.vertical, -12)
    }
}

/// Invite affichée tant que la clé TMDB manque : elle ouvre directement la page de saisie.
struct InviteCleTMDB: View {
    var body: some View {
        ContentUnavailableView {
            Label("Clé TMDB à saisir", systemImage: "key")
        } description: {
            Text("Séance lit les films, séries et plateformes sur TMDB. La clé est gratuite et reste dans le trousseau de l'appareil.")
        } actions: {
            NavigationLink("Saisir ma clé TMDB", value: DestinationReglage.tmdb)
                .buttonStyle(.borderedProminent)
        }
    }
}
