import SeanceDonnees
import SeanceKit
import SeanceNAS
import AVKit
import SwiftUI
import VLCKit

/// Le lecteur de l'Apple TV (6.6) : le moteur de VLC, dans Séance. Jusqu'ici la TV passait la main à Infuse ou à
/// VLC, qui lisaient bien — mais au retour on se retrouvait chez eux, pas sur la page d'où l'on venait. Ici, la
/// touche Retour referme le lecteur et rend la main à Séance, exactement là où on l'a quitté.
///
/// La vidéo reste sur le NAS : elle passe par le relais local, comme sur l'iPhone.
struct LecteurVLCTV: View {
    let video: VideoPerso
    let acces: ReglagesNAS
    let motDePasse: String
    /// Appelé si même VLC n'y arrive pas : l'écran d'appel propose alors Infuse.
    var surEchec: (String) -> Void = { _ in }
    /// Où commencer, en secondes : « Reprendre à 1:03:12 » (8.0).
    var depart: Double?
    /// Où l'on en est (secondes, durée), toutes les dix secondes et à la fermeture : la reprise le retient.
    var surPosition: (Double, Double) -> Void = { _, _ in }
    /// Le film ou l'épisode du NAS (8.1) : vu vers la fin, puis l'épisode suivant. `nil` pour un souvenir.
    var fichier: FichierNAS?
    /// Lancer l'épisode d'après : l'écran d'appel remplace la vidéo.
    var surSuivant: (FichierNAS) -> Void = { _ in }

    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @State private var vuMarque = false
    @State private var suivant: FichierNAS?
    @State private var compte: Int?

    @Environment(\.dismiss) private var fermer
    @State private var moteur = MoteurVLCTV()
    @State private var relais: RelaisVideo?
    @State private var source: SourceVideoSMB?
    @State private var message: String?
    /// Les commandes (8.0) : la barre de progression et les boutons, comme dans le lecteur d'Apple.
    @State private var commandes = true
    /// Le panneau des langues et sous-titres, par-dessus les commandes.
    @State private var pistes = false
    /// Le petit panneau du son (8.2.4), au-dessus de son bouton — à part du panneau de droite.
    @State private var son = false
    /// Chaque geste relance le compte à rebours qui efface les commandes pendant la lecture.
    @State private var dernierGeste = Date.now
    @FocusState private var focus: Commande?
    /// Sur la barre (8.0) : où l'on veut aller, entre 0 et 1, avant de valider d'un clic.
    @State private var cible: Double?
    /// Des appuis rapprochés sur la barre vont de plus en plus vite.
    @State private var dernierPas = Date.distantPast
    @State private var elan = 1.0

    enum Commande: Hashable { case ecran, barre, reculer, lecture, avancer, son, pistes, quitter, sonPlus }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let message {
                VStack(spacing: 24) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 64)).foregroundStyle(Theme.accentClair)
                    Text(message)
                        .font(.system(size: 30))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 1100)
                    Text("Touche Retour pour revenir.").font(.system(size: 24)).foregroundStyle(Theme.texte2)
                }
                .foregroundStyle(.white)
            } else {
                VueVLCTV(moteur: moteur).ignoresSafeArea()
                // Commandes cachées : tout l'écran reçoit la télécommande. Gauche et droite reculent ou avancent de
                // 10 secondes, un clic ou le haut et le bas font revenir les commandes.
                Color.clear
                    .contentShape(Rectangle())
                    .focusable(!commandes && !pistes)
                    .focused($focus, equals: .ecran)
                    // 8.1 : gauche et droite font apparaître la barre et y déplacent le repère, de plus en plus vite si
                    // l'on insiste ou si l'on garde le doigt appuyé ; le saut se fait seul un instant après.
                    .onMoveCommand { direction in
                        switch direction {
                        case .left, .right:
                            montrer()
                            focus = .barre
                            deplacer(direction)
                        default: montrer()
                        }
                    }
                    .onTapGesture { montrer() }
                    .ignoresSafeArea()
                if moteur.enChargement {
                    VStack(spacing: 18) {
                        ProgressView().tint(.white).controlSize(.large)
                        Text(video.nom).font(.system(size: 26)).foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if commandes, !pistes, message == nil {
                barreCommandes.transition(.opacity)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if son, commandes, !pistes, message == nil {
                VStack(spacing: 18) {
                    Text(moteur.muet ? "Son coupé" : "Volume \(moteur.volume) %")
                        .font(.system(size: 26, weight: .semibold).monospacedDigit())
                    HStack(spacing: 18) {
                        Button { moteur.volume -= 10; dernierGeste = .now } label: { Image(systemName: "speaker.minus") }
                            .buttonStyle(BoutonRondTV())
                            .accessibilityLabel("Moins fort")
                        Button { moteur.volume += 10; dernierGeste = .now } label: { Image(systemName: "speaker.plus") }
                            .buttonStyle(BoutonRondTV())
                            .focused($focus, equals: .sonPlus)
                            .accessibilityLabel("Plus fort")
                        Button { moteur.muet.toggle(); dernierGeste = .now } label: {
                            Image(systemName: moteur.muet ? "speaker.wave.2" : "speaker.slash")
                        }
                        .buttonStyle(BoutonRondTV())
                        .accessibilityLabel(moteur.muet ? "Remettre le son" : "Couper le son")
                        SortieAudioTV().frame(width: 70, height: 70)
                    }
                }
                .foregroundStyle(.white)
                .padding(28)
                .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(.leading, 90)
                .padding(.bottom, 260)
                .focusSection()
                .transition(.opacity)
            }
        }
        .overlay(alignment: .trailing) {
            if pistes { PanneauPistesTV(moteur: moteur) { fermerPistes() }.transition(.move(edge: .trailing)) }
        }
        .animation(.easeOut(duration: 0.25), value: commandes)
        .animation(.easeOut(duration: 0.25), value: pistes)
        // Retour : referme d'abord le panneau, puis les commandes ; commandes cachées, quitte la lecture.
        .onExitCommand {
            if cible != nil { cible = nil } else if son { son = false; focus = .son } else if pistes { fermerPistes() } else if commandes, moteur.enLecture { cacher() } else { fermer() }
        }
        .onPlayPauseCommand { moteur.basculerLecture(); montrer() }
        .overlay(alignment: .bottomTrailing) { carteSuivant }
        .onChange(of: Int(moteur.secondes)) { _, _ in marquerVuSiFini() }
        .onChange(of: moteur.termine) { _, termine in
            guard termine else { return }
            marquerVuSiFini(force: true)
            if suivant != nil { compte = FinDeLecture.delaiEpisodeSuivant } else { fermer() }
        }
        .task(id: compte) {
            guard let restant = compte else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, compte != nil else { return }
            if restant <= 1 { lireSuivant() } else { compte = restant - 1 }
        }
        .onChange(of: focus) { dernierGeste = .now }
        .task {
            if let fichier {
                suivant = FinDeFichierNAS.episodeSuivant(fichier, contexte: contexte)
                moteur.preferences = PreferencesPistes.lire(profil: ConteneurTV.famille.actif.id)
            }
            await ouvrir()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                if moteur.duree > 0 { surPosition(moteur.secondes, moteur.duree) }
            }
        }
        // Six secondes sans geste pendant la lecture : les commandes s'effacent.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if commandes, !pistes, !son, cible == nil, moteur.enLecture, Date.now.timeIntervalSince(dernierGeste) > 6 { cacher() }
            }
        }
        .onAppear { focus = .lecture }
        .onDisappear {
            if moteur.duree > 0 { surPosition(moteur.secondes, moteur.duree) }
            Task { await ranger() }
        }
    }

    /// L'épisode d'après : proposé dès le générique, lancé tout seul à la fin après un compte à rebours.
    @ViewBuilder
    private var carteSuivant: some View {
        if let suivant, message == nil, compte != nil || (vuMarque && commandes) {
            VStack(alignment: .trailing, spacing: 16) {
                if let compte {
                    Text("Épisode suivant dans \(compte) s").font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                }
                Button { lireSuivant() } label: { Label(Self.libelle(suivant), systemImage: "forward.end.fill") }
                    .buttonStyle(BoutonTV(principal: true))
            }
            .padding(.trailing, 90)
            .padding(.bottom, compte == nil ? 320 : 90)
            .focusSection()
        }
    }

    static func libelle(_ fichier: FichierNAS) -> String {
        guard let saison = fichier.saison, let episode = fichier.episode else { return "Épisode suivant" }
        return String(format: "Épisode suivant · S%02dE%02d", saison, episode)
    }

    private func lireSuivant() {
        guard let suivant else { return }
        compte = nil
        if moteur.duree > 0 { surPosition(moteur.secondes, moteur.duree) }
        surSuivant(suivant)
    }

    /// Au-delà de 90 % (ou dans le générique d'un long film), le film ou l'épisode compte comme vu, sans question.
    private func marquerVuSiFini(force: Bool = false) {
        guard !vuMarque, let fichier, let sujet = FinDeFichierNAS.lecture(fichier),
              force || FinDeLecture.presqueFini(secondes: moteur.secondes, duree: moteur.duree) else { return }
        vuMarque = true
        let duree = moteur.duree
        Task {
            if (try? await FinDeFichierNAS.marquerVu(sujet, dureeSecondes: duree, contexte: contexte, tmdb: etat.tmdb)) == true {
                etat.dire("« \(sujet.libelle) » marqué vu")
            }
        }
    }

    /// La barre du bas : le titre, la progression avec le temps écoulé et restant, puis les boutons.
    private var barreCommandes: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(video.nom).font(.system(size: 34, weight: .bold)).foregroundStyle(.white).lineLimit(1)
            barreProgression
            HStack(spacing: 30) {
                Button { moteur.reculer(); dernierGeste = .now } label: { Image(systemName: "gobackward.10") }
                    .buttonStyle(BoutonRondTV())
                    .focused($focus, equals: .reculer)
                    .accessibilityLabel("Reculer de 10 secondes")
                Button { moteur.basculerLecture(); dernierGeste = .now } label: {
                    Image(systemName: moteur.enLecture ? "pause.fill" : "play.fill")
                }
                .buttonStyle(BoutonRondTV())
                .focused($focus, equals: .lecture)
                .accessibilityLabel(moteur.enLecture ? "Pause" : "Lecture")
                Button { moteur.avancer(); dernierGeste = .now } label: { Image(systemName: "goforward.10") }
                    .buttonStyle(BoutonRondTV())
                    .focused($focus, equals: .avancer)
                    .accessibilityLabel("Avancer de 10 secondes")
                Button {
                    son.toggle()
                    dernierGeste = .now
                    if son { focus = .sonPlus }
                } label: { Image(systemName: moteur.muet ? "speaker.slash.fill" : "speaker.wave.2.fill") }
                    .buttonStyle(BoutonRondTV())
                    .focused($focus, equals: .son)
                    .accessibilityLabel("Son")
                Spacer()
                Button { pistes = true } label: { Label("Son, langue et image", systemImage: "slider.horizontal.3") }
                    .buttonStyle(BoutonTV())
                    .focused($focus, equals: .pistes)
                Button { fermer() } label: { Label("Quitter", systemImage: "xmark") }
                    .buttonStyle(BoutonTV())
                    .focused($focus, equals: .quitter)
            }
            .focusSection()
        }
        .padding(.horizontal, 90)
        .padding(.top, 60)
        .padding(.bottom, 50)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    /// La bande de progression (8.0) : on y monte depuis les boutons ; gauche et droite déplacent un repère — de plus en
    /// plus vite si l'on insiste —, un clic y saute, Retour ou un autre bouton l'abandonne.
    private var barreProgression: some View {
        let surLaBarre = focus == .barre
        let actuelle = min(max(moteur.position, 0), 1)
        return VStack(spacing: 10) {
            // Un bouton au style neutre (8.2) : ni le focus ni le clic ne soulèvent ni n'agrandissent la barre — tvOS le
            // faisait pour une vue simplement « focusable ».
            Button {
                if let cible { moteur.allerA(cible) }
                cible = nil
                dernierGeste = .now
            } label: {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white).frame(width: geo.size.width * actuelle)
                    if surLaBarre {
                        let repere = cible ?? actuelle
                        VStack(spacing: 8) {
                            Text(moteur.temps(a: repere))
                                .font(.system(size: 26, weight: .bold).monospacedDigit())
                                .foregroundStyle(.black)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(.white, in: Capsule())
                                .fixedSize()
                            Circle().fill(.white).frame(width: 30, height: 30)
                        }
                        .offset(x: geo.size.width * repere - 60, y: -28)
                        .frame(width: 120)
                    }
                }
                .frame(height: geo.size.height)
            }
            // 8.2 : la barre garde sa taille quand on y va — l'effet de focus de tvOS l'agrandissait et l'écartait de tout
            // l'écran ; seul le repère avec le temps dit qu'on est dessus.
            .frame(height: 10)
            .contentShape(Rectangle())
            }
            .buttonStyle(StyleBarreTV())
            .focusEffectDisabled()
            .focused($focus, equals: .barre)
            .onMoveCommand { direction in deplacer(direction) }
            .accessibilityLabel("Progression, \(moteur.tempsAffiche)")
            HStack {
                Text(moteur.tempsAffiche)
                Spacer()
                Text(moteur.resteAffiche)
            }
            .font(.system(size: 24, weight: .semibold).monospacedDigit())
            .foregroundStyle(Theme.texte2)
        }
        .onChange(of: surLaBarre) { _, dessus in if !dessus { cible = nil } }
        // Le repère posé, la vidéo y saute d'elle-même après un instant sans appui : plus besoin de cliquer.
        .task(id: cible) {
            guard let visee = cible else { return }
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled, cible == visee else { return }
            moteur.allerA(visee)
            cible = nil
            elan = 1
            dernierGeste = .now
        }
    }

    /// Un pas sur la barre : 10 secondes, ou un centième du film s'il est long. Des appuis rapprochés — ou le doigt
    /// gardé sur la télécommande, qui les répète — multiplient le pas, jusqu'à cinq minutes d'un coup.
    private func deplacer(_ direction: MoveCommandDirection) {
        guard moteur.duree > 0 else { return }
        let maintenant = Date.now
        elan = maintenant.timeIntervalSince(dernierPas) < 0.5 ? min(elan * 1.6, 300 / max(10, moteur.duree / 100)) : 1
        dernierPas = maintenant
        let pas = max(10 / moteur.duree, 0.01) * elan
        let depart = cible ?? min(max(moteur.position, 0), 1)
        switch direction {
        case .left: cible = max(depart - pas, 0)
        case .right: cible = min(depart + pas, 1)
        default: break
        }
        dernierGeste = .now
    }

    /// Fait revenir les commandes, le focus sur Lecture / Pause ; après un saut, elles montrent où l'on en est.
    private func montrer() {
        dernierGeste = .now
        guard !commandes else { return }
        commandes = true
        focus = .lecture
    }

    private func cacher() {
        commandes = false
        focus = .ecran
    }

    private func fermerPistes() {
        pistes = false
        dernierGeste = .now
        focus = .pistes
    }

    /// D'abord VLC seul, directement sur le partage en SMB (8.1, comme l'iPhone depuis la 7.0) : il lit par gros
    /// blocs, en avance. Le relais HTTP, plus lent, ne sert plus que si VLC n'arrive pas à ouvrir le partage.
    private func ouvrir() async {
        guard relais == nil, message == nil else { return }
        if let adresse = acces.url(chemin: video.chemin) {
            moteur.lire(adresse, depart: depart, options: [":smb-user=\(acces.utilisateur)", ":smb-pwd=\(motDePasse)", ":network-caching=3000"]
                        + OptionsVLC.pour(video.chemin))
            if await moteur.demarre(dans: .seconds(12)) { return }
            moteur.arreter()
        }
        await ouvrirParLeRelais()
    }

    private func ouvrirParLeRelais() async {
        let nouvelle = SourceVideoSMB(reglages: acces, motDePasse: motDePasse, chemin: video.chemin)
        await nouvelle.ouvrir()
        source = nouvelle
        let extensionFichier = (video.chemin as NSString).pathExtension.lowercased()
        let nouveau = RelaisVideo(source: nouvelle, typeMIME: Self.typeMIME(extensionFichier))
        do {
            let adresse = try await nouveau.demarrer()
            relais = nouveau
            moteur.lire(adresse, depart: depart, options: [":network-caching=3000"] + OptionsVLC.pour(video.chemin))
        } catch {
            let texte = ErreurNAS.message(error)
            message = texte
            surEchec(texte)
            await nouvelle.fermer()
        }
    }

    static func typeMIME(_ extensionFichier: String) -> String {
        switch extensionFichier {
        case "mp4", "m4v": "video/mp4"
        case "mov", "qt": "video/quicktime"
        case "mkv": "video/x-matroska"
        case "avi": "video/x-msvideo"
        case "wmv": "video/x-ms-wmv"
        case "mpg", "mpeg": "video/mpeg"
        default: "application/octet-stream"
        }
    }

    private func ranger() async {
        moteur.arreter()
        await relais?.arreter()
        relais = nil
        await source?.fermer()
        source = nil
    }
}

/// Langue et sous-titres (8.0) : un panneau à droite, une ligne par piste que le fichier annonce, cochée quand elle
/// est choisie. Retour le referme.
private struct PanneauPistesTV: View {
    let moteur: MoteurVLCTV
    let fermer: () -> Void
    @State private var audio: [MoteurVLCTV.Piste] = []
    @State private var texte: [MoteurVLCTV.Piste] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("LANGUE").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.texte2)
                if audio.isEmpty {
                    Text("Aucune piste audio annoncée par le fichier").font(.system(size: 26)).foregroundStyle(Theme.texte2)
                }
                ForEach(audio) { piste in
                    ligne(piste.nom, piste.choisie) { moteur.choisirAudio(piste.id); relire() }
                }
                Text("SOUS-TITRES").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.texte2).padding(.top, 24)
                ligne("Sans", !texte.contains { $0.choisie }) { moteur.choisirTexte(nil); relire() }
                ForEach(texte.filter { $0.id != "-1" }) { piste in
                    ligne(piste.nom, piste.choisie) { moteur.choisirTexte(piste.id); relire() }
                }
                Text("VITESSE").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.texte2).padding(.top, 24)
                ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { vitesse in
                    ligne(vitesse == 1 ? "Normale" : "× \(vitesse.formatted(.number.precision(.fractionLength(0...2))))",
                          moteur.vitesse == vitesse) { moteur.vitesse = vitesse }
                }
                Text("IMAGE").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.texte2).padding(.top, 24)
                ligne("Image entière", !moteur.remplir) { moteur.remplir = false }
                ligne("Remplir l'écran", moteur.remplir) { moteur.remplir = true }
            }
            .padding(50)
        }
        .frame(width: 720)
        .frame(maxHeight: .infinity)
        .background(Theme.surface.opacity(0.96))
        .ignoresSafeArea()
        .onAppear { relire() }
    }

    private func ligne(_ nom: String, _ choisie: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(nom).lineLimit(1)
                Spacer()
                if choisie { Image(systemName: "checkmark") }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(BoutonTV())
        .accessibilityAddTraits(choisie ? .isSelected : [])
    }

    private func relire() {
        audio = moteur.pistesAudio()
        texte = moteur.pistesTexte()
    }
}

/// La sortie du son de l'Apple TV : AirPlay vers des enceintes, un HomePod, des écouteurs.
private struct SortieAudioTV: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let vue = AVRoutePickerView()
        vue.tintColor = .white
        vue.activeTintColor = UIColor(Theme.accent)
        return vue
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// La vue où VLC dessine, sur la TV.
private struct VueVLCTV: UIViewRepresentable {
    let moteur: MoteurVLCTV

    func makeUIView(context: Context) -> UIView {
        let vue = UIView()
        vue.backgroundColor = .black
        moteur.attacher(a: vue)
        return vue
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Le moteur, côté TV : lecture, pause, position. Tout sur le fil principal.
@MainActor
@Observable
final class MoteurVLCTV {
    private let lecteur = VLCMediaPlayer()
    private var observateur: Task<Void, Never>?

    private(set) var enLecture = false
    private(set) var enChargement = true
    private(set) var position: Double = 0
    private(set) var tempsAffiche = "0:00"
    /// Secondes depuis le début, et durée de la vidéo (0 tant qu'elle n'est pas connue).
    private(set) var secondes: Double = 0
    private(set) var duree: Double = 0
    /// La position où reprendre, appliquée une fois la durée connue.
    private var depart: Double?
    /// Le volume de VLC (8.2.1), de 0 à 200 % : celui du téléviseur reste à la télécommande.
    var volume: Int = 100 {
        didSet {
            volume = min(max(volume, 0), 200)
            lecteur.audio?.volume = Int32(volume)
        }
    }

    var muet = false {
        didSet { lecteur.audio?.isMuted = muet }
    }

    var vitesse: Double = 1 {
        didSet { lecteur.rate = Float(vitesse) }
    }

    /// Remplir l'écran rogne les bords ; sinon l'image entière, avec des bandes noires au besoin.
    var remplir = false {
        didSet { lecteur.videoFitMode = remplir ? .larger : .smaller }
    }

    /// Langue et sous-titres voulus (8.1), posés une fois que VLC a décrit les pistes.
    var preferences: PreferencesPistes?
    private var pistesPosees = false
    /// Vrai quand la vidéo est allée jusqu'au bout.
    private(set) var termine = false
    private var derniereFraction = 0.0

    func attacher(a vue: UIView) {
        lecteur.drawable = vue
    }

    /// Vrai dès que l'image avance ; faux si VLC échoue ou si rien ne vient dans le délai.
    func demarre(dans delai: Duration) async -> Bool {
        let limite = ContinuousClock.now + delai
        while ContinuousClock.now < limite {
            if lecteur.state == .error { return false }
            if lecteur.isPlaying, lecteur.time.intValue > 0 { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    func lire(_ adresse: URL, depart: Double? = nil, options: [String] = []) {
        observateur?.cancel()
        self.depart = depart
        let media = VLCMedia(url: adresse)
        for option in options { media?.addOption(option) }
        lecteur.media = media
        lecteur.play()
        enLecture = true
        enChargement = true
        pistesPosees = false
        termine = false
        derniereFraction = 0
        observateur = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                self.position = self.lecteur.position
                self.enLecture = self.lecteur.isPlaying
                if self.lecteur.state == .stopped, self.derniereFraction > 0.97 { self.termine = true }
                if self.lecteur.isPlaying { self.derniereFraction = Double(self.lecteur.position) }
                if !self.pistesPosees, let preferences = self.preferences, self.lecteur.isPlaying {
                    self.pistesPosees = self.lecteur.appliquer(preferences)
                }
                self.enChargement = !self.termine && !self.lecteur.isPlaying && self.lecteur.position == 0
                self.tempsAffiche = self.lecteur.time.stringValue
                self.secondes = Double(self.lecteur.time.intValue) / 1000
                self.duree = Double(self.lecteur.media?.length.intValue ?? 0) / 1000
                // Reprendre : dès que VLC connaît la durée, on saute à la position retenue.
                if let depart = self.depart, self.duree > 0, self.lecteur.isPlaying {
                    self.lecteur.time = VLCTime(int: Int32(depart * 1000))
                    self.depart = nil
                }
            }
        }
    }

    func basculerLecture() {
        if lecteur.isPlaying { lecteur.pause() } else { lecteur.play() }
        enLecture = lecteur.isPlaying
    }

    func avancer() { lecteur.jumpForward(10); rafraichir() }

    /// Saute à une position, entre 0 et 1 (la bande de progression).
    func allerA(_ position: Double) {
        lecteur.position = position
        rafraichir()
    }

    /// Le temps à une position de la bande, « 1:03:12 ».
    func temps(a position: Double) -> String {
        let total = Int(duree * position)
        let h = total / 3600, m = total % 3600 / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
    func reculer() { lecteur.jumpBackward(10); rafraichir() }

    /// Le temps restant, « −1:02:10 », une fois la durée connue.
    var resteAffiche: String {
        guard duree > 0 else { return "" }
        let reste = max(Int(duree - secondes), 0)
        let h = reste / 3600, m = reste % 3600 / 60, s = reste % 60
        return h > 0 ? String(format: "−%d:%02d:%02d", h, m, s) : String(format: "−%d:%02d", m, s)
    }

    /// Une piste du fichier : langue audio ou sous-titres.
    struct Piste: Identifiable {
        let id: String
        let nom: String
        let choisie: Bool
    }

    func pistesAudio() -> [Piste] {
        lecteur.audioTracks.map { Piste(id: $0.trackId, nom: $0.trackName, choisie: $0.isSelected) }
    }

    func pistesTexte() -> [Piste] {
        lecteur.textTracks.map { Piste(id: $0.trackId, nom: $0.trackName, choisie: $0.isSelected) }
    }

    func choisirAudio(_ id: String) {
        lecteur.audioTracks.first { $0.trackId == id }?.isSelectedExclusively = true
    }

    /// `nil` : sans sous-titres.
    func choisirTexte(_ id: String?) {
        guard let id else { return lecteur.deselectAllTextTracks() }
        lecteur.textTracks.first { $0.trackId == id }?.isSelectedExclusively = true
    }

    /// Après un saut, la barre suit tout de suite, sans attendre le prochain relevé.
    private func rafraichir() {
        position = lecteur.position
        tempsAffiche = lecteur.time.stringValue
        secondes = Double(lecteur.time.intValue) / 1000
    }

    func arreter() {
        observateur?.cancel()
        observateur = nil
        lecteur.stop()
        enLecture = false
    }
}


/// La barre d'avancement telle quelle : aucun effet de focus ni de clic (8.2).
private struct StyleBarreTV: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}
