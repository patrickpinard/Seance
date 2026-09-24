#if !targetEnvironment(macCatalyst)
import SeanceKit
import SeanceNAS
import MediaPlayer
import SwiftUI
import VLCKit

/// Le lecteur de secours de Séance (6.5) : le moteur de VLC, qui lit ce qu'AVFoundation refuse — AVI, WMV, MKV,
/// DV de caméscope, MJPEG. Il lit le fichier par le relais local, comme le lecteur d'Apple : la vidéo reste sur le
/// NAS, rien n'est copié sur l'appareil.
///
/// Sur le Mac, Séance garde AVFoundation : le binaire de VLCKit n'a pas de tranche Mac Catalyst. Infuse y prend le
/// relais, et il y fonctionne.
struct LecteurVLC: View {
    let video: VideoPerso
    let acces: ReglagesNAS
    let motDePasse: String
    /// Appelé quand même VLC n'y arrive pas : l'écran d'appel propose alors les apps extérieures.
    var surEchec: (String) -> Void = { _ in }

    @Environment(\.dismiss) private var fermer
    @State private var moteur = MoteurVLC()
    @State private var relais: RelaisVideo?
    @State private var source: SourceVideoSMB?
    @State private var message: String?
    @State private var commandesVisibles = true
    /// Change à chaque toucher : relance le compte à rebours qui masque les commandes.
    @State private var dernierGeste = 0
    /// Le panneau des réglages de lecture ; ouvert, les commandes restent affichées.
    @State private var panneau = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let message {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(Theme.accentClair)
                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 40)
                    Button("Fermer") { fermer() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                }
            } else {
                VueVLC(moteur: moteur).ignoresSafeArea()
                // La vue de VLC, une vue UIKit, avalait les touchers : les commandes masquées ne revenaient plus (7.0).
                // Une couche transparente les reçoit à sa place.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) { commandesVisibles.toggle() }
                        dernierGeste += 1
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(commandesVisibles ? "Masquer les commandes" : "Afficher les commandes")
                if moteur.enChargement {
                    // Le sablier (7.0) : le temps que VLC ouvre le fichier sur le NAS et remplisse sa mémoire tampon.
                    VStack(spacing: 14) {
                        ProgressView().tint(.white).controlSize(.large)
                        Text("Chargement de « \(video.nom) »…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        if moteur.tampon > 0, moteur.tampon < 100 {
                            Text("\(Int(moteur.tampon)) %").font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .padding(24)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .overlay(alignment: .bottom) { if commandesVisibles, message == nil { commandes } }
        .overlay(alignment: .topLeading) {
            if commandesVisibles || message != nil {
            Button { fermer() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .padding(.leading, 20)
            .padding(.top, 24)
            .accessibilityLabel("Fermer le lecteur")
            }
        }
        // Commandes et croix s'effacent après trois secondes de lecture sans toucher (7.0) ; un toucher les ramène.
        .task(id: Minuterie(geste: dernierGeste, enLecture: moteur.enLecture && !moteur.enChargement && !panneau, visibles: commandesVisibles)) {
            guard commandesVisibles, !panneau, moteur.enLecture, !moteur.enChargement else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { commandesVisibles = false }
        }
        .gesture(
            DragGesture(minimumDistance: 60).onEnded { glissement in
                if glissement.translation.height > 80 { fermer() }
            }
        )
        .sheet(isPresented: $panneau, onDismiss: { dernierGeste += 1 }) {
            PanneauLecture(moteur: moteur)
                .presentationDetents([.medium, .large])
        }
        .statusBarHidden()
        .persistentSystemOverlays(commandesVisibles ? .automatic : .hidden)
        .onAppear { OrientationLecture.ouvrir() }
        .task { await ouvrir() }
        .onDisappear {
            OrientationLecture.fermer()
            Task { await ranger() }
        }
    }

    /// Langue, sous-titres, vitesse et cadrage, dans un panneau : un menu se refermait à chaque rafraîchissement du
    /// lecteur, et disparaissait avec les commandes au bout de trois secondes.
    private var menuReglages: some View {
        Button { panneau = true } label: {
            Image(systemName: "slider.horizontal.3")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Langue, sous-titres, vitesse et image")
    }

    private struct Minuterie: Equatable {
        let geste: Int
        let enLecture: Bool
        let visibles: Bool
    }

    /// Les commandes : lecture, position, durée. Le lecteur de VLC n'en fournit aucune — celles-ci sont à nous,
    /// donc aux couleurs de Séance.
    private var commandes: some View {
        VStack(spacing: 10) {
            Slider(value: Binding(get: { moteur.position }, set: { moteur.allerA($0) }), in: 0...1)
                .tint(Theme.accent)
            HStack(spacing: 24) {
                Button { moteur.reculer(); dernierGeste += 1 } label: { Image(systemName: "gobackward.10") }
                Button { moteur.basculerLecture(); dernierGeste += 1 } label: {
                    Image(systemName: moteur.enLecture ? "pause.fill" : "play.fill").font(.title)
                }
                Button { moteur.avancer(); dernierGeste += 1 } label: { Image(systemName: "goforward.10") }
                Spacer()
                Text(moteur.tempsAffiche).font(.caption.monospacedDigit())
                menuReglages
            }
            .font(.title3)
            .foregroundStyle(.white)
            // Le son (7.0) : le curseur du volume de l'appareil, et le choix de la sortie (AirPlay, écouteurs).
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").font(.caption).foregroundStyle(.white.opacity(0.8)).accessibilityHidden(true)
                VolumeSysteme().frame(height: 34)
                Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundStyle(.white.opacity(0.8)).accessibilityHidden(true)
            }
        }
        .padding(18)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
    }

    /// D'abord VLC seul, directement sur le partage (7.0) : son module SMB lit par gros blocs, en avance. Le relais HTTP,
    /// qui demandait au NAS chaque tranche l'une après l'autre, rendait la lecture lente sur l'iPhone ; il ne sert plus
    /// que si VLC n'arrive pas à ouvrir le partage lui-même.
    private func ouvrir() async {
        guard relais == nil, message == nil else { return }
        if let adresse = acces.url(chemin: video.chemin) {
            moteur.lire(adresse, options: [":smb-user=\(acces.utilisateur)", ":smb-pwd=\(motDePasse)", ":network-caching=3000"])
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
            moteur.lire(adresse, options: [":network-caching=3000"])
        } catch {
            let texte = ErreurNAS.message(error)
            message = texte
            surEchec(texte)
            await nouvelle.fermer()
        }
    }

    /// VLC se fie surtout au contenu, mais un type juste lui évite de deviner.
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

/// Les réglages de la lecture en cours : ce que le fichier propose, lu à l'ouverture du panneau.
private struct PanneauLecture: View {
    let moteur: MoteurVLC
    @Environment(\.dismiss) private var fermer
    @State private var audio: [MoteurVLC.Piste] = []
    @State private var texte: [MoteurVLC.Piste] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Langue") {
                    if audio.isEmpty {
                        Text("Aucune piste audio annoncée par le fichier").foregroundStyle(.secondary)
                    }
                    ForEach(audio) { piste in
                        Button {
                            moteur.choisirAudio(piste.id)
                            audio = moteur.pistesAudio()
                        } label: { Coche(piste.nom, piste.choisie) }
                    }
                }
                Section("Sous-titres") {
                    Button {
                        moteur.choisirTexte(nil)
                        texte = moteur.pistesTexte()
                    } label: { Coche("Aucun", !texte.contains(where: \.choisie)) }
                    ForEach(texte) { piste in
                        Button {
                            moteur.choisirTexte(piste.id)
                            texte = moteur.pistesTexte()
                        } label: { Coche(piste.nom, piste.choisie) }
                    }
                    if texte.isEmpty {
                        Text("Ce fichier n'a pas de sous-titres").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Vitesse") {
                    ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { vitesse in
                        Button { moteur.vitesse = vitesse } label: {
                            Coche(vitesse == 1 ? "Normale" : "× \(vitesse.formatted(.number.precision(.fractionLength(0...2))))",
                                  moteur.vitesse == vitesse)
                        }
                    }
                }
                Section("Image") {
                    Button { moteur.remplir = false } label: { Coche("Image entière", !moteur.remplir) }
                    Button { moteur.remplir = true } label: { Coche("Remplir l'écran", moteur.remplir) }
                }
            }
            .tint(.primary)
            .navigationTitle("Lecture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { fermer() } }
            }
        }
        .onAppear {
            audio = moteur.pistesAudio()
            texte = moteur.pistesTexte()
        }
    }
}

/// Une entrée de menu, cochée ou non.
private struct Coche: View {
    let nom: String
    let cochee: Bool

    init(_ nom: String, _ cochee: Bool) {
        self.nom = nom
        self.cochee = cochee
    }

    var body: some View {
        HStack {
            Text(nom).foregroundStyle(Color.primary)
            Spacer()
            if cochee { Image(systemName: "checkmark").foregroundStyle(Theme.accentClair).fontWeight(.semibold) }
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(cochee ? .isSelected : [])
    }
}

/// Le volume de l'appareil, avec le bouton de sortie audio (AirPlay) : le curseur d'Apple, le seul qui règle vraiment le son.
private struct VolumeSysteme: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let vue = MPVolumeView()
        vue.tintColor = UIColor(Theme.accent)
        return vue
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

/// La vue où VLC dessine. `VLCVideoView` est une vue UIKit : SwiftUI la reçoit telle quelle.
private struct VueVLC: UIViewRepresentable {
    let moteur: MoteurVLC

    func makeUIView(context: Context) -> UIView {
        let vue = UIView()
        vue.backgroundColor = .black
        vue.isUserInteractionEnabled = false
        moteur.attacher(a: vue)
        return vue
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Ce que Séance demande au moteur de VLC, et ce qu'elle en lit. Tout passe par le fil principal : `VLCMediaPlayer`
/// n'est pas fait pour être piloté d'ailleurs.
@MainActor
@Observable
final class MoteurVLC {
    private let lecteur = VLCMediaPlayer()
    private var observateur: Task<Void, Never>?

    private(set) var enLecture = false
    private(set) var enChargement = true
    private(set) var position: Double = 0
    private(set) var tempsAffiche = "0:00"
    /// Remplissage de la mémoire tampon, en pour cent, pour le sablier.
    private(set) var tampon: Double = 0
    private var delegue: DelegueMoteurVLC?

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

    func lire(_ adresse: URL, options: [String] = []) {
        observateur?.cancel()
        enChargement = true
        let media = VLCMedia(url: adresse)
        for option in options { media?.addOption(option) }
        lecteur.media = media
        let delegue = DelegueMoteurVLC { [weak self] pourcent in self?.tampon = pourcent }
        self.delegue = delegue
        lecteur.delegate = delegue
        lecteur.play()
        enLecture = true
        observateur = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard let self else { return }
                self.position = self.lecteur.position
                self.enLecture = self.lecteur.isPlaying
                self.enChargement = self.lecteur.state == .opening
                    || (!self.lecteur.isPlaying && self.lecteur.position == 0)
                self.tempsAffiche = self.lecteur.time.stringValue
            }
        }
    }

    func basculerLecture() {
        if lecteur.isPlaying { lecteur.pause() } else { lecteur.play() }
        enLecture = lecteur.isPlaying
    }

    func allerA(_ position: Double) {
        lecteur.position = position
        self.position = position
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

    func choisirTexte(_ id: String?) {
        guard let id else { return lecteur.deselectAllTextTracks() }
        lecteur.textTracks.first { $0.trackId == id }?.isSelectedExclusively = true
    }

    var vitesse: Double = 1 {
        didSet { lecteur.rate = Float(vitesse) }
    }

    /// Remplir l'écran rogne les bords ; sinon l'image entière, avec des bandes noires au besoin.
    var remplir = false {
        didSet { lecteur.videoFitMode = remplir ? .larger : .smaller }
    }

    func avancer() { lecteur.jumpForward(10) }
    func reculer() { lecteur.jumpBackward(10) }

    func arreter() {
        observateur?.cancel()
        observateur = nil
        lecteur.stop()
        enLecture = false
    }
}

/// Reçoit de VLC l'avancement de la mémoire tampon.
private final class DelegueMoteurVLC: NSObject, VLCMediaPlayerDelegate, @unchecked Sendable {
    let surTampon: @MainActor (Double) -> Void

    init(surTampon: @escaping @MainActor (Double) -> Void) {
        self.surTampon = surTampon
    }

    func mediaPlayerBufferingChanged(_ progress: Float) {
        let pourcent = Double(progress) * 100
        Task { @MainActor [surTampon] in surTampon(pourcent) }
    }
}
#endif
