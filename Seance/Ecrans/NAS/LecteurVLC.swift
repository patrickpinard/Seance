#if !targetEnvironment(macCatalyst)
import SeanceDonnees
import SeanceKit
import SeanceNAS
import AVFoundation
import AVKit
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
    /// 8.0 : le lecteur est posé par la racine, par-dessus l'app, pour pouvoir passer en image dans l'image.
    let lecture: LectureEnCours
    private var video: VideoPerso { lecture.video }
    /// Hors de la maison (8.1), l'adresse du NAS par le VPN ou Tailscale, s'il y en a une.
    private var acces: ReglagesNAS { etat.reseau.horsMaison ? lecture.acces.horsDeLaMaison : lecture.acces }
    private var motDePasse: String { lecture.motDePasse }

    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @State private var moteur = MoteurVLC()
    /// 8.1 : vu vers la fin sans question, puis l'épisode suivant du NAS, après un compte à rebours.
    @State private var vuMarque = false
    @State private var suivant: FichierNAS?
    @State private var compte: Int?
    /// « Lire sur l'Apple TV » (8.1) : les TV où Séance est ouverte, trouvées sur le réseau de la maison.
    @State private var televiseurs: [EmetteurConfig.Televiseur] = []
    @State private var choixTV = false
    @State private var envoiTV = false
    /// La vidéo a repris où l'on s'était arrêté : « Depuis le début » reste proposé quelques secondes.
    @State private var reprise: PositionLecture?
    @State private var relais: RelaisVideo?
    @State private var source: SourceVideoSMB?
    @State private var message: String?
    @State private var commandesVisibles = true
    /// Change à chaque toucher : relance le compte à rebours qui masque les commandes.
    @State private var dernierGeste = 0
    /// Le panneau des réglages de lecture ; ouvert, les commandes restent affichées.
    @State private var panneau = false
    /// Le petit panneau du son, au-dessus de son bouton (8.2.4 : à part du grand panneau, comme en 8.2).
    @State private var panneauSon = false

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
                        if etat.reseau.horsMaison {
                            Label(lecture.acces.hoteDistant == nil ? "Réseau mobile : le NAS de la maison risque de ne pas répondre"
                                                                   : "Réseau mobile : par l'adresse hors de la maison",
                                  systemImage: "antenna.radiowaves.left.and.right")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.75))
                                .multilineTextAlignment(.center)
                        }
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
        .overlay(alignment: .bottom) { if commandesVisibles, message == nil, compte == nil { commandes } }
        .overlay(alignment: .bottomTrailing) { carteSuivant }
        .overlay(alignment: .bottom) {
            if panneauSon, commandesVisibles, message == nil {
                PanneauSon(moteur: moteur) { dernierGeste += 1 }
                    .padding(.horizontal, 20)
                    // Au-dessus de la barre d'avancement, sans la toucher (8.2.8).
                    .padding(.bottom, 240)
                    .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
            }
        }
        // Deux boutons distincts (8.0) : la croix arrête la lecture ; « Continuer dans Séance » la passe en image
        // dans l'image et rend la main à l'app, la vidéo continuant dans sa petite fenêtre.
        .overlay(alignment: .top) {
            if commandesVisibles || message != nil {
                HStack {
                    Button { fermer() } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                    .accessibilityLabel("Fermer la lecture")
                    Spacer()
                    if message == nil, !televiseurs.isEmpty {
                        Button { televiseurs.count == 1 ? envoyer(a: televiseurs[0]) : (choixTV = true) } label: {
                            Label(envoiTV ? "Envoi…" : "Sur l'Apple TV", systemImage: "appletv")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .frame(height: 44)
                                .background(.black.opacity(0.55), in: Capsule())
                        }
                        .disabled(envoiTV)
                        .accessibilityHint("La vidéo continue sur la TV, là où tu en es")
                        .confirmationDialog("Sur quelle Apple TV ?", isPresented: $choixTV, titleVisibility: .visible) {
                            ForEach(televiseurs) { tv in Button(tv.nom) { envoyer(a: tv) } }
                        }
                    }
                    if message == nil, moteur.imageDisponible {
                        Button { moteur.passerEnImage() } label: {
                            Label("Continuer dans Séance", systemImage: "pip.enter")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .frame(height: 44)
                                .background(.black.opacity(0.55), in: Capsule())
                        }
                        .accessibilityHint("La vidéo continue dans une petite fenêtre pendant que tu navigues")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
        }
        .overlay(alignment: .bottom) {
            if let reprise, message == nil {
                Button {
                    etat.nas.oublierPosition(video.chemin)
                    moteur.allerA(0)
                    self.reprise = nil
                } label: {
                    Label("Repris à \(PositionsLecture.horodatage(reprise.secondes)) · Depuis le début", systemImage: "gobackward")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(.white, in: Capsule())
                }
                .padding(.bottom, commandesVisibles ? 190 : 40)
                .transition(.opacity)
            }
        }
        .task(id: moteur.enChargement) {
            // « Depuis le début » reste proposé six secondes une fois la lecture partie.
            guard reprise != nil, !moteur.enChargement else { return }
            try? await Task.sleep(for: .seconds(6))
            withAnimation { reprise = nil }
        }
        // Toutes les dix secondes : où l'on en est, pour « Reprendre » sur tous les appareils.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                noterPosition()
            }
        }
        .onChange(of: moteur.enImage) { _, enImage in etat.lectureEnImage = enImage }
        // Vers la fin : vu, sans question (8.1).
        .onChange(of: Int(moteur.secondes)) { _, _ in marquerVuSiFini() }
        // Tout à la fin : l'épisode suivant après dix secondes, sinon le lecteur se referme.
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
        // Commandes et croix s'effacent après trois secondes de lecture sans toucher (7.0) ; un toucher les ramène.
        .task(id: Minuterie(geste: dernierGeste, enLecture: moteur.enLecture && !moteur.enChargement && !panneau && !panneauSon, visibles: commandesVisibles)) {
            guard commandesVisibles, !panneau, !panneauSon, moteur.enLecture, !moteur.enChargement else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { commandesVisibles = false }
        }
        .gesture(
            DragGesture(minimumDistance: 60).onEnded { glissement in
                if glissement.translation.height > 80 { fermer() }
            }
        )
        // Le panneau de lecture (8.2.1) sort à droite de l'image, comme sur l'Apple TV : la vidéo reste visible.
        .overlay(alignment: .trailing) {
            if panneau {
                PanneauLecture(moteur: moteur) {
                    withAnimation(.snappy) { panneau = false }
                    dernierGeste += 1
                }
                .transition(.move(edge: .trailing))
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(commandesVisibles ? .automatic : .hidden)
        // 8.3 : comme sur l'Apple TV, l'écran ne se verrouille pas pendant la lecture : VLC n'empêche pas la veille.
        .onChange(of: moteur.enLecture, initial: true) { _, lit in UIApplication.shared.isIdleTimerDisabled = lit }
        .onAppear {
            Plantages.page("Lecteur")
            OrientationLecture.ouvrir()
            // Un lecteur, pour iOS : le son sort même en silencieux, et l'image dans l'image est permise.
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        .task {
            // Les Apple TV où Séance est ouverte : le bouton n'apparaît que s'il y en a une.
            for await trouves in EmetteurLecture.chercher() { televiseurs = trouves }
        }
        .task {
            if let fichier = lecture.fichier {
                suivant = FinDeFichierNAS.episodeSuivant(fichier, contexte: contexte)
                moteur.preferences = PreferencesPistes.lire(profil: ProfilsFamille().actif.id)
            }
            await ouvrir()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            OrientationLecture.fermer()
            Task { await ranger() }
        }
    }

    /// Langue, sous-titres, vitesse et cadrage, dans un panneau : un menu se refermait à chaque rafraîchissement du
    /// lecteur, et disparaissait avec les commandes au bout de trois secondes.
    private var menuReglages: some View {
        Button { withAnimation(.snappy) { panneau = true } } label: {
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
                // Le son (8.1) : un bouton, et non plus un second curseur qu'on prenait pour la barre d'avancement.
                Button { withAnimation(.snappy) { panneauSon.toggle() }; dernierGeste += 1 } label: {
                    Image(systemName: moteur.muet ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(moteur.muet ? "Son coupé, régler le son" : "Régler le son")
                SortieAudio().frame(width: 44, height: 44).accessibilityLabel("Sortie audio, AirPlay")
                menuReglages
            }
            .font(.title3)
            .foregroundStyle(.white)
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
        #if DEBUG
        if ProcessInfo.processInfo.environment["SEANCE_LIRE_FICHIER"] == video.chemin {
            moteur.depart = ProcessInfo.processInfo.environment["SEANCE_LIRE_DEPART"].flatMap(Double.init)
            return moteur.lire(URL(fileURLWithPath: video.chemin), mkv: OptionsVLC.estMKV(video.chemin))
        }
        #endif
        if let position = etat.nas.positions.aReprendre(video.chemin) {
            reprise = position
            moteur.depart = position.secondes
        }
        if let adresse = acces.url(chemin: video.chemin) {
            moteur.lire(adresse, options: [":smb-user=\(acces.utilisateur)", ":smb-pwd=\(motDePasse)", ":network-caching=3000"]
                        + OptionsVLC.pour(video.chemin), mkv: OptionsVLC.estMKV(video.chemin))
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
            moteur.lire(adresse, options: [":network-caching=3000"] + OptionsVLC.pour(video.chemin), mkv: OptionsVLC.estMKV(video.chemin))
        } catch {
            // Hors de la maison sans adresse pour y arriver : la vraie raison, plutôt qu'une erreur réseau.
            let texte = etat.reseau.horsMaison && lecture.acces.hoteDistant == nil
                ? "Tu n'es pas sur le Wi-Fi de la maison : le NAS n'y répond pas. Pour lire hors de chez toi, ajoute son adresse par ton VPN ou Tailscale dans Réglages › NAS › « Hors de la maison »."
                : ErreurNAS.message(error)
            message = texte
            lecture.surEchec(texte)
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

    /// L'épisode d'après : proposé dès le générique, lancé tout seul à la fin après un compte à rebours.
    @ViewBuilder
    private var carteSuivant: some View {
        if let suivant, message == nil, compte != nil || (vuMarque && commandesVisibles) {
            VStack(alignment: .trailing, spacing: 10) {
                if let compte {
                    Text("Épisode suivant dans \(compte) s").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                }
                HStack(spacing: 10) {
                    if compte != nil {
                        Button("Annuler") { compte = nil; fermer() }
                            .buttonStyle(StyleBoutonSecondaire())
                    }
                    Button { lireSuivant() } label: {
                        Label(Self.libelle(suivant), systemImage: "forward.end.fill")
                    }
                    .buttonStyle(StyleBoutonPrincipal(pleineLargeur: false))
                }
            }
            .padding(20)
            .padding(.bottom, compte == nil ? 170 : 20)
            .transition(.opacity)
        }
    }

    static func libelle(_ fichier: FichierNAS) -> String {
        guard let saison = fichier.saison, let episode = fichier.episode else { return "Épisode suivant" }
        return String(format: "Épisode suivant · S%02dE%02d", saison, episode)
    }

    private func lireSuivant() {
        guard let suivant else { return }
        compte = nil
        noterPosition()
        etat.lire(suivant)
    }

    /// Au-delà de 90 % (ou dans le générique d'un long film), le film ou l'épisode compte comme vu.
    private func marquerVuSiFini(force: Bool = false) {
        guard !vuMarque, let fichier = lecture.fichier, let sujet = FinDeFichierNAS.lecture(fichier),
              force || FinDeLecture.presqueFini(secondes: moteur.secondes, duree: moteur.duree) else { return }
        vuMarque = true
        let duree = moteur.duree
        Task {
            if (try? await FinDeFichierNAS.marquerVu(sujet, dureeSecondes: duree, contexte: contexte, tmdb: etat.tmdb)) == true {
                etat.confirmer("« \(sujet.libelle) » marqué vu", symbole: "checkmark.circle")
                // 8.2 : « Qui regarde avec toi ? » — les autres personnes l'ont vu aussi.
                let tmdb = etat.tmdb
                VuEnsemble.demander(etat, reference: sujet.reference, titre: sujet.libelle) { autre in
                    _ = try await FinDeFichierNAS.marquerVu(sujet, dureeSecondes: duree, contexte: autre, tmdb: tmdb)
                }
            }
        }
    }

    /// La vidéo part sur la TV, à la seconde où l'on en est ; le lecteur de l'iPhone se referme.
    private func envoyer(a televiseur: EmetteurConfig.Televiseur) {
        guard let secret = etat.nas.motDePasse else { return }
        let commande = CommandeLecture(chemin: video.chemin, souvenir: lecture.fichier == nil,
                                       depart: moteur.secondes > 5 ? moteur.secondes : nil, expediteur: UIDevice.current.name)
        envoiTV = true
        Task {
            do {
                try await EmetteurLecture.envoyer(commande, a: televiseur, secret: secret)
                fermer()
                etat.confirmer("« \(video.nom) » continue sur \(televiseur.nom)", symbole: "appletv")
            } catch {
                envoiTV = false
                etat.confirmer("L'Apple TV n'a pas répondu : Séance y est-elle ouverte, avec le même NAS ?", symbole: "exclamationmark.triangle")
            }
        }
    }

    /// Fermer : la lecture s'arrête, sa position est retenue.
    private func fermer() {
        noterPosition()
        etat.lectureEnImage = false
        etat.lecture = nil
    }

    private func noterPosition() {
        guard moteur.duree > 0 else { return }
        etat.nas.noterPosition(video.chemin, secondes: moteur.secondes, duree: moteur.duree)
    }

    private func ranger() async {
        moteur.liberer()
        await relais?.arreter()
        relais = nil
        await source?.fermer()
        source = nil
    }
}

/// Les réglages de la lecture en cours : ce que le fichier propose, lu à l'ouverture du panneau.
private struct PanneauLecture: View {
    let moteur: MoteurVLC
    let fermer: () -> Void
    @State private var audio: [MoteurVLC.Piste] = []
    @State private var texte: [MoteurVLC.Piste] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Lecture").font(.headline)
                Spacer()
                Button("OK", action: fermer).fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
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
            .scrollContentBackground(.hidden)
            .tint(.primary)
        }
        .frame(width: 340)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
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

/// Le petit panneau du son. 8.2.7 (demande de Patrick) : à l'horizontale, centré au-dessus des commandes — debout, il
/// sortait de l'écran.
private struct PanneauSon: View {
    let moteur: MoteurVLC
    let geste: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill").font(.caption).foregroundStyle(.white.opacity(0.8)).accessibilityHidden(true)
            VolumeCouche().frame(maxWidth: 240).frame(height: 34).accessibilityLabel("Volume")
            Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundStyle(.white.opacity(0.8)).accessibilityHidden(true)
            Button { moteur.muet.toggle(); geste() } label: {
                Image(systemName: moteur.muet ? "speaker.slash.fill" : "speaker.slash")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(moteur.muet ? Theme.accent : .white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(moteur.muet ? "Remettre le son" : "Couper le son")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.black.opacity(0.75), in: Capsule())
    }
}

/// Le curseur du volume de l'appareil, couché : le curseur d'Apple, le seul qui règle vraiment le son.
private struct VolumeCouche: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let vue = MPVolumeView()
        vue.tintColor = UIColor(Theme.accent)
        return vue
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

/// Le choix de la sortie audio : AirPlay, écouteurs, enceinte.
private struct SortieAudio: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let vue = AVRoutePickerView()
        vue.tintColor = .white
        vue.activeTintColor = UIColor(Theme.accent)
        vue.prioritizesVideoDevices = false
        return vue
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}


/// La vue où VLC dessine. `VLCVideoView` est une vue UIKit : SwiftUI la reçoit telle quelle.
private struct VueVLC: UIViewRepresentable {
    let moteur: MoteurVLC

    func makeUIView(context: Context) -> UIView {
        let vue = VueImageDansLImage(moteur: moteur)
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
    /// Secondes depuis le début, et durée (0 tant qu'elle n'est pas connue) : la reprise les retient.
    private(set) var secondes: Double = 0
    private(set) var duree: Double = 0
    /// Où reprendre, appliqué une fois la lecture partie.
    var depart: Double?
    /// L'image dans l'image (8.0) : prête quand VLC a donné sa fenêtre ; `enImage` quand elle est à l'écran.
    private(set) var imageDisponible = false
    private(set) var enImage = false
    private var fenetreImage: (any VLCPictureInPictureWindowControlling)?
    /// Remplissage de la mémoire tampon, en pour cent, pour le sablier.
    private(set) var tampon: Double = 0
    /// Langue et sous-titres voulus (8.1), posés une fois que VLC a décrit les pistes.
    var preferences: PreferencesPistes?
    private var pistesPosees = false
    /// Vrai quand la vidéo est allée jusqu'au bout.
    private(set) var termine = false
    private var derniereFraction = 0.0
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

    /// Un MKV à vérifier (8.3) : s'il a des pixels non carrés, on repart avec FFmpeg (`OptionsVLC.anamorphique`).
    private var mkvAVerifier = false
    private var adresseLue: URL?
    private var optionsLues: [String] = []

    func lire(_ adresse: URL, options: [String] = [], mkv: Bool = false) {
        observateur?.cancel()
        enChargement = true
        adresseLue = adresse
        optionsLues = options
        mkvAVerifier = mkv && !options.contains(OptionsVLC.ffmpeg)
        let media = VLCMedia(url: adresse)
        for option in options { media?.addOption(option) }
        lecteur.media = media
        let delegue = DelegueMoteurVLC { [weak self] pourcent in self?.tampon = pourcent }
        self.delegue = delegue
        lecteur.delegate = delegue
        lecteur.play()
        enLecture = true
        pistesPosees = false
        termine = false
        derniereFraction = 0
        observateur = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard let self else { return }
                self.position = self.lecteur.position
                self.enLecture = self.lecteur.isPlaying
                // La fin : VLC s'arrête de lui-même après la dernière image.
                if self.lecteur.state == .stopped, self.derniereFraction > 0.97 { self.termine = true }
                if self.lecteur.isPlaying { self.derniereFraction = Double(self.lecteur.position) }
                if self.mkvAVerifier, self.lecteur.isPlaying, let anamorphique = OptionsVLC.anamorphique(self.lecteur) {
                    self.mkvAVerifier = false
                    if anamorphique, let adresse = self.adresseLue {
                        if self.secondes > 1 { self.depart = self.secondes }
                        return self.lire(adresse, options: self.optionsLues + [OptionsVLC.ffmpeg])
                    }
                }
                if !self.pistesPosees, let preferences = self.preferences, self.lecteur.isPlaying {
                    self.pistesPosees = self.lecteur.appliquer(preferences)
                }
                self.enChargement = !self.termine && (self.lecteur.state == .opening
                    || (!self.lecteur.isPlaying && self.lecteur.position == 0))
                self.tempsAffiche = self.lecteur.time.stringValue
                self.secondes = Double(self.lecteur.time.intValue) / 1000
                self.duree = Double(self.lecteur.media?.length.intValue ?? 0) / 1000
                if let depart = self.depart, self.duree > 0, self.lecteur.isPlaying {
                    self.lecteur.time = VLCTime(int: Int32(depart * 1000))
                    self.depart = nil
                }
                self.fenetreImage?.invalidatePlaybackState()
            }
        }
    }

    // MARK: Image dans l'image

    /// VLC donne sa fenêtre d'image dans l'image quand elle est prête.
    func recevoir(_ fenetre: any VLCPictureInPictureWindowControlling) {
        fenetreImage = fenetre
        imageDisponible = true
        fenetre.stateChangeEventHandler = { [weak self] commence in
            Task { @MainActor in self?.enImage = commence }
        }
    }

    func passerEnImage() {
        fenetreImage?.startPictureInPicture()
    }

    // Ce que la fenêtre d'image dans l'image demande au lecteur.
    func jouer() { lecteur.play(); enLecture = true }
    func mettreEnPause() { lecteur.pause(); enLecture = false }
    func deplacer(de millisecondes: Int64) {
        lecteur.time = VLCTime(int: Int32(max(0, Int64(lecteur.time.intValue) + millisecondes)))
    }
    var longueurMs: Int64 { Int64(lecteur.media?.length.intValue ?? 0) }
    var tempsMs: Int64 { Int64(lecteur.time.intValue) }
    var deplacable: Bool { lecteur.isSeekable }
    var joue: Bool { lecteur.isPlaying }

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

    /// Le son coupé dans le lecteur, sans toucher au volume de l'appareil.
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

    func avancer() { lecteur.jumpForward(10) }
    func reculer() { lecteur.jumpBackward(10) }

    func arreter() {
        observateur?.cancel()
        observateur = nil
        lecteur.stop()
        enLecture = false
    }

    /// La lecture est finie pour de bon (8.2.7) : le lecteur de VLC part au cimetière, relâché plus tard sur le fil
    /// principal plutôt que depuis le fil de VLC.
    func liberer() {
        arreter()
        CimetiereVLC.garder(lecteur)
    }
}

/// La vue où VLC dessine, capable d'image dans l'image (VLCKit 4) : elle donne à VLC de quoi piloter la lecture depuis
/// la petite fenêtre, et reçoit la fenêtre quand elle est prête.
private final class VueImageDansLImage: UIView, VLCPictureInPictureDrawable {
    let moteur: MoteurVLC
    private lazy var controleur = ControleurImage(moteur: moteur)

    init(moteur: MoteurVLC) {
        self.moteur = moteur
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    /// VLC pose sa propre vue de dessin dans celle-ci, à la taille du moment, et ne la suit pas quand l'iPhone passe à
    /// l'horizontale : l'image restait petite dans un coin, ou déformée. Elle suit maintenant chaque changement de taille.
    override func layoutSubviews() {
        super.layoutSubviews()
        for vue in subviews where vue.frame != bounds { vue.frame = bounds }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for couche in layer.sublayers ?? [] where couche.frame != bounds { couche.frame = bounds }
        CATransaction.commit()
    }

    nonisolated func mediaController() -> any VLCPictureInPictureMediaControlling {
        MainActor.assumeIsolated { controleur }
    }

    nonisolated func pictureInPictureReady() -> (((any VLCPictureInPictureWindowControlling)?) -> Void)? {
        nonisolated(unsafe) let moteur = MainActor.assumeIsolated { self.moteur }
        return { recue in
            guard let recue else { return }
            nonisolated(unsafe) let fenetre = recue
            Task { @MainActor in moteur.recevoir(fenetre) }
        }
    }
}

/// Ce que la fenêtre d'image dans l'image demande : lecture, pause, avance, durée. Elle appelle sur le fil principal.
private final class ControleurImage: NSObject, VLCPictureInPictureMediaControlling, @unchecked Sendable {
    let moteur: MoteurVLC

    init(moteur: MoteurVLC) {
        self.moteur = moteur
    }

    private func surLeFilPrincipal<T: Sendable>(_ action: @MainActor () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated(action) }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(action) }
    }

    func play() { surLeFilPrincipal { moteur.jouer() } }
    func pause() { surLeFilPrincipal { moteur.mettreEnPause() } }
    func seek(by offset: Int64, completion: @escaping () -> Void) {
        surLeFilPrincipal { moteur.deplacer(de: offset) }
        completion()
    }
    func mediaLength() -> Int64 { surLeFilPrincipal { moteur.longueurMs } }
    func mediaTime() -> Int64 { surLeFilPrincipal { moteur.tempsMs } }
    func isMediaSeekable() -> Bool { surLeFilPrincipal { moteur.deplacable } }
    func isMediaPlaying() -> Bool { surLeFilPrincipal { moteur.joue } }
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
