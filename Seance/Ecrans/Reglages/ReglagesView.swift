import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Les pages de réglages, ouvertes par valeur (`destinationsTitres()` les déclare à la racine de chaque pile).
/// Un lien « par vue » vers Réglages, depuis la barre d'outils de Profil, figeait l'iPhone : SwiftUI remettait
/// la destination à jour à chaque rendu, sans fin, jusqu'à ce qu'iOS tue l'app.
enum DestinationReglage: Hashable {
    case reglages, prenom, famille, centrale, apparence, tmdb, claude, plateformes, tele, nas, videosPerso, lecture, alertes, alertesRecues, sauvegarde, lettre, aPropos, versions, journal, apercuWidgets
}

struct PageReglage: View {
    let destination: DestinationReglage

    var body: some View {
        switch destination {
        case .reglages: ReglagesView().navigationBarTitleDisplayMode(.inline)
        case .prenom: ReglagesPrenomView()
        case .famille: FamilleView()
        case .centrale: ReglagesCentraleView()
        case .apparence: ReglagesApparenceView()
        case .tmdb: ReglagesTMDBView()
        case .claude: ReglagesClaudeView()
        case .plateformes: ReglagesPlateformesView()
        case .tele: ReglagesTeleView()
        case .nas: ReglagesNASView()
        case .videosPerso: ReglagesVideosPersoView()
        case .lecture: ReglagesLectureView()
        case .alertes: ReglagesAlertesView()
        case .alertesRecues: AlertesRecuesView()
        case .sauvegarde: ReglagesSauvegardeView()
        case .lettre: ReglagesLettreView()
        case .aPropos: AProposView(contenu: .application)
        case .versions: AProposView(contenu: .versions)
        case .journal: AProposView(contenu: .journal)
        case .apercuWidgets:
            #if DEBUG
            ApercuWidgetsView()
            #else
            EmptyView()
            #endif
        }
    }
}

/// Une ligne de la liste des réglages (7.0, piste A) : le symbole dans l'orange de Séance, le nom, la valeur à droite ;
/// pour ce que Séance surveille, un point vert (en ordre) ou orange (à régler).
struct LigneReglage: View {
    let titre: String
    let symbole: String
    let valeur: String
    var enOrdre: Bool?

    @Environment(\.dynamicTypeSize) private var tailleTexte

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbole)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.accentClair)
                .frame(width: 28)
                .accessibilityHidden(true)
            let disposition = tailleTexte.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 8))
            disposition {
                Text(titre).font(.body).foregroundStyle(Color.primary)
                if !tailleTexte.isAccessibilitySize { Spacer(minLength: 8) }
                Text(valeur)
                    .font(.subheadline)
                    .foregroundStyle(enOrdre == false ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                    .lineLimit(tailleTexte.isAccessibilitySize ? 3 : 1)
                    .multilineTextAlignment(tailleTexte.isAccessibilitySize ? .leading : .trailing)
            }
            if let enOrdre {
                Circle().fill(enOrdre ? Color.green : Color.orange).frame(width: 9, height: 9).accessibilityHidden(true)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(titre), \(valeur)\(enOrdre.map { $0 ? ", en ordre" : ", à régler" } ?? "")")
        .accessibilityAddTraits(.isButton)
    }
}

/// Une tuile de réglage (EF-169) : le symbole dans l'orange de Séance, le titre, l'état courant. Les icônes aux sept
/// couleurs, façon Réglages d'iOS, juraient avec le reste de l'app.
struct TuileReglage: View {
    let titre: String
    let symbole: String
    let valeur: String
    /// L'état demande une action : il s'écrit en orange.
    var alerte = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbole)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.accentClair)
                .frame(height: 26, alignment: .leading)
                .accessibilityHidden(true)
            Text(titre).font(.subheadline.weight(.semibold)).lineLimit(2)
            Text(valeur)
                .font(.caption)
                .foregroundStyle(alerte ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.trait))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(titre), \(valeur)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Réglages en tableau de bord : en tête, ce qui est en ordre et ce qui manque, chaque point menant à son réglage ;
/// puis, en tuiles, seulement ce que l'état ne couvre pas (piste B, EF-169). Tes goûts et tes statistiques
/// sont dans Profil. Sans pile de navigation : onglet à part sur le Mac, page ouverte depuis Profil sur l'iPhone.
struct ReglagesView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(filter: #Predicate<Abonnement> { $0.actif }, sort: \Abonnement.nom) private var abonnements: [Abonnement]
    @Query(filter: #Predicate<Chaine> { $0.active }) private var chaines: [Chaine]
    /// Leurs affiches habillent les cartes des réglages.
    @Query private var suivis: [Suivi]
    @AppStorage(Prenom.cle) private var prenom = ""
    @AppStorage(NombreIdees.cle) private var nombreIdees = NombreIdees.parDefaut
    @AppStorage(Apparence.cle) private var apparence = Apparence.sombre.rawValue
    @AppStorage("accueil.sources") private var sourcesBrutes = Data()
    @State private var accueil = false
    @State private var nouvelAppareil = false
    @State private var envoiAppleTV = false

    /// Deux tuiles de front sur l'iPhone, davantage sur l'iPad et le Mac.
    private static let colonnes = [GridItem(.adaptive(minimum: 158, maximum: 320), spacing: 12, alignment: .top)]

    var body: some View {
        ScrollView {
            // Piste A de la maquette du 24 septembre 2026 (7.0) : la carte d'état, plus courte, puis une liste groupée
            // comme les Réglages de l'iPhone — une ligne par réglage, sa valeur à droite, un point vert ou orange pour
            // ce que Séance surveille. Les groupes suivent le menu : Où regarder, Toi, La maison, L'app.
            VStack(alignment: .leading, spacing: 22) {
                heros(manques: points.filter { !$0.enOrdre })

                groupe("Où regarder") {
                    ligne(.plateformes, "Plateformes", "play.rectangle.on.rectangle.fill",
                          abonnements.isEmpty ? "Aucune" : abonnements.map(\.nom).formatted(.list(type: .and, width: .narrow)), enOrdre: !abonnements.isEmpty)
                    ligne(.tele, "TV", "tv.fill", chaines.isEmpty ? "Aucune chaîne" : "\(Format.pluriel(chaines.count, "chaîne")) · \(libelleLecture)",
                          enOrdre: !chaines.isEmpty)
                    ligne(.nas, "NAS", "externaldrive.fill", etat.nas.estConfigure ? libelleNAS.prefix(1).uppercased() + libelleNAS.dropFirst() : "À configurer",
                          enOrdre: etat.nas.estConfigure)
                    ligne(.videosPerso, "Vidéos personnelles", "video.fill", libelleVideosPerso,
                          enOrdre: !etat.videosPerso.aConfigurer(films: etat.nas.reglages))
                    ligne(.lecture, "Lecture", "play.circle.fill", libelleLecteur)
                }
                groupe("Toi") {
                    ligne(.prenom, "Prénom et idées", "person.fill",
                          "\(Prenom.lire(prenom) ?? "À saisir") · \(Format.pluriel(NombreIdees.lire(nombreIdees), "idée"))")
                    ligne(.alertes, "Alertes", "bell.fill", libelleAlertes, enOrdre: alertesActives)
                    ligne(.lettre, "E-mail de la semaine", "envelope.fill",
                          !etat.lettre.reglages.actif ? "Désactivé" : etat.lettre.pret ? libelleJoursLettre : "À terminer",
                          enOrdre: etat.lettre.reglages.actif ? etat.lettre.pret : nil)
                    // L'accueil se personnalise dans sa feuille, la même que depuis l'accueil : un seul réglage, deux portes.
                    Button { accueil = true } label: {
                        LigneReglage(titre: "Accueil", symbole: "house.fill", valeur: libelleAccueil)
                    }
                    .buttonStyle(.plain)
                    ligne(.apparence, "Apparence", Apparence.lire(apparence).symbole, Apparence.lire(apparence).nom)
                }
                groupe("La maison") {
                    ligne(.famille, "Famille", "person.2.fill",
                          ProfilsFamille().aPlusieursProfils ? ProfilsFamille().profils.map { $0.prenom.isEmpty ? "Moi" : $0.prenom }.joined(separator: ", ")
                                                             : "Un seul profil")
                    ligne(.sauvegarde, "Appareils et synchronisation", "arrow.triangle.2.circlepath",
                          etat.synchro.nomDossier.map { "« \($0) »" } ?? "Fichier, AirDrop, iCloud Drive")
                    Button { nouvelAppareil = true } label: {
                        LigneReglage(titre: "Nouvel appareil", symbole: "iphone.and.arrow.forward", valeur: "Reprendre données, clé et NAS")
                    }
                    .buttonStyle(.plain)
                    Button { envoiAppleTV = true } label: {
                        LigneReglage(titre: "Envoyer à un appareil", symbole: "appletv.fill", valeur: "Un code à six chiffres")
                    }
                    .buttonStyle(.plain)
                    if EtatCentrale.disponible {
                        ligne(.centrale, "Centrale de la maison", "house.and.flag.fill", etat.centrale.active ? "Active" : "Désactivée")
                    }
                }
                groupe("L'app") {
                    ligne(.tmdb, "TMDB", "film.stack", etat.tmdb == nil ? "Clé à saisir" : "Connecté", enOrdre: etat.tmdb != nil)
                    ligne(.claude, "Claude", "sparkles", etat.claude == nil ? "Facultatif" : "Connecté")
                    // Trois portes au lieu d'une page à onglets : ce que fait Séance, ce qui a changé, ce qui s'est passé.
                    ligne(.aPropos, "Séance", "info.circle.fill", expirationProche ?? "Sources, espace utilisé",
                          enOrdre: expirationProche == nil ? nil : false)
                    ligne(.versions, "Versions", "clock.arrow.circlepath", "Version \(NoteVersion.historique.first?.numero ?? "")")
                    ligne(.journal, "Journal", "list.bullet.rectangle",
                          etat.journal.entrees.isEmpty ? "Rien à signaler" : Format.pluriel(etat.journal.entrees.count, "entrée"))
                    #if DEBUG
                    if ApercuWidgetsView.actif { ligne(.apercuWidgets, "Aperçu des widgets", "square.grid.2x2.fill", "Développement") }
                    #endif
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.fond)
        .navigationTitle("Réglages")
        .task { await etat.alertes.actualiserAutorisation() }
        .sheet(isPresented: $envoiAppleTV) {
            EnvoiAppleTVView { envoiAppleTV = false }
        }
        .sheet(isPresented: $nouvelAppareil) {
            NouvelAppareilView { nouvelAppareil = false }
        }
        .sheet(isPresented: $accueil) {
            ReglageSourcesAccueil(sources: Binding {
                (try? JSONDecoder().decode(SourcesAccueil.self, from: sourcesBrutes)) ?? SourcesAccueil()
            } set: { nouvelles in
                sourcesBrutes = (try? JSONEncoder().encode(nouvelles)) ?? Data()
            }, abonnements: abonnements)
        }
    }

    /// Un groupe de la liste : son titre, puis ses lignes dans un même cadre, séparées d'un filet.
    private func groupe(_ titre: String, @ViewBuilder _ lignes: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titre)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                Group(subviews: lignes()) { lignes in
                    ForEach(Array(lignes.enumerated()), id: \.offset) { rang, ligne in
                        if rang > 0 { Divider().padding(.leading, 52) }
                        ligne
                    }
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.trait))
        }
    }

    /// `enOrdre` : un point vert ou orange, pour ce que Séance surveille ; `nil` pour le reste.
    private func ligne(_ destination: DestinationReglage, _ titre: String, _ symbole: String, _ valeur: String, enOrdre: Bool? = nil) -> some View {
        NavigationLink(value: destination) {
            LigneReglage(titre: titre, symbole: symbole, valeur: valeur, enOrdre: enOrdre)
        }
        .buttonStyle(.plain)
    }

    private var libelleVideosPerso: String {
        if !etat.videosPerso.actif { return "Désactivées" }
        if etat.videosPerso.aConfigurer(films: etat.nas.reglages) { return "Accès à terminer" }
        return etat.videosPerso.videos.isEmpty ? "Pas encore lues" : Format.pluriel(etat.videosPerso.videos.count, "vidéo")
    }

    /// « Lundi, jeudi » : les jours d'envoi de l'e-mail.
    private var libelleJoursLettre: String {
        let noms = Calendar.current.standaloneWeekdaySymbols
        let jours = etat.lettre.reglages.joursRetenus.sorted { (($0 + 5) % 7) < (($1 + 5) % 7) }
        return jours.compactMap { (1...7).contains($0) ? noms[$0 - 1].capitalized : nil }.joined(separator: ", ")
    }

    // MARK: État de Séance

    /// Un réglage que l'état surveille : son nom, son symbole (ceux de l'app), ce qu'il vaut, s'il est en ordre.
    private struct PointEtat: Identifiable {
        let destination: DestinationReglage
        let titre: String
        let symbole: String
        let detail: String
        let enOrdre: Bool
        /// Le verbe du bouton quand il reste à régler : « Saisir », « Choisir », « Activer ».
        let action: String?
        var id: DestinationReglage { destination }
    }

    private var points: [PointEtat] {
        var liste = [
            PointEtat(destination: .tmdb, titre: "TMDB", symbole: "film.stack",
                      detail: etat.tmdb == nil ? "Les fiches et les affiches en viennent" : "Fiches, affiches et plateformes", enOrdre: etat.tmdb != nil, action: "Saisir la clé TMDB"),
            PointEtat(destination: .plateformes, titre: "Plateformes", symbole: "play.tv.fill",
                      detail: abonnements.isEmpty ? "Pour savoir ce que tu peux regarder" : abonnements.map(\.nom).formatted(.list(type: .and, width: .narrow)),
                      enOrdre: !abonnements.isEmpty, action: "Choisir mes plateformes"),
            PointEtat(destination: .tele, titre: "TV", symbole: "tv.fill",
                      detail: chaines.isEmpty ? "Choisis tes chaînes" : "\(chaines.count) chaînes · \(libelleLecture)", enOrdre: !chaines.isEmpty, action: "Choisir mes chaînes"),
            PointEtat(destination: .nas, titre: "NAS", symbole: "externaldrive.fill",
                      detail: etat.nas.estConfigure ? libelleNAS.prefix(1).uppercased() + libelleNAS.dropFirst() : "Tes films déjà téléchargés",
                      enOrdre: etat.nas.estConfigure, action: "Configurer le NAS"),
            // Facultatives : décochées, la carte le dit sans rien réclamer.
            PointEtat(destination: .videosPerso, titre: "Vidéos personnelles", symbole: "video.fill",
                      detail: !etat.videosPerso.actif ? "Désactivées" : etat.videosPerso.aConfigurer(films: etat.nas.reglages) ? "Accès à terminer"
                          : etat.videosPerso.videos.isEmpty ? "Partage « \(etat.videosPerso.reglages.acces.partage) », pas encore lu" : Format.pluriel(etat.videosPerso.videos.count, "vidéo"),
                      enOrdre: !etat.videosPerso.aConfigurer(films: etat.nas.reglages), action: "Terminer l'accès aux vidéos"),
        ]
        #if !targetEnvironment(macCatalyst)
        // Un seul lecteur : « Lire » n'ouvre que celui-ci, partout dans l'app.
        liste.append(PointEtat(destination: .lecture, titre: "Lecture", symbole: "play.circle.fill",
                               detail: etat.nas.nomLecteur, enOrdre: true, action: nil))
        #endif
        liste.append(PointEtat(destination: .alertes, titre: "Alertes", symbole: "bell.fill",
                               detail: alertesActives ? "Épisodes, sorties et passages à la TV" : "Rien ne te sera annoncé", enOrdre: alertesActives, action: "Activer les alertes"))
        liste.append(PointEtat(destination: .sauvegarde, titre: "Sauvegarde et synchronisation", symbole: "arrow.triangle.2.circlepath",
                               detail: etat.synchro.nomDossier.map { "Dossier « \($0) »" } ?? "Fichier, AirDrop ou dossier iCloud Drive", enOrdre: true, action: nil))
        if let expiration = etat.expirationInstallation {
            let libelle = ProfilInstallation.libelle(expiration: expiration)
            liste.append(PointEtat(destination: .aPropos, titre: "Installation", symbole: "clock.fill",
                                   detail: libelle.prefix(1).uppercased() + libelle.dropFirst(), enOrdre: expiration.timeIntervalSinceNow > 2 * 86_400, action: nil))
        }
        return liste
    }

    /// Les affiches de tes titres, pour habiller les cartes : chaque carte garde la sienne d'un jour à l'autre.
    private var affiches: [String] {
        Array(Set(suivis.compactMap(\.cheminAffiche))).sorted()
    }

    private func affiche(_ rang: Int) -> String? {
        affiches.isEmpty ? nil : affiches[(rang * 7 + 3) % affiches.count]
    }

    /// La carte d'état, en tête : ce qui manque, nommé, et les deux gestes du moment.
    private func heros(manques: [PointEtat]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(manques.isEmpty ? "Séance est prête" : "\(Format.pluriel(manques.count, "réglage", "réglages")) à compléter")
                    .font(.title2.weight(.heavy))
                Text(manques.isEmpty ? "Tout est branché."
                     : manques.map(\.titre).formatted(.list(type: .and)) + ". Le reste est branché.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .accessibilityElement(children: .combine)
            // Les gestes du moment, à leur taille : ce qui manque d'abord, puis synchroniser (6.6, à la place de
            // « Voir l'installation », que la carte Installation montre déjà).
            Flux(espacement: 10) {
                if let premier = manques.first(where: { $0.action != nil }), let action = premier.action {
                    NavigationLink(value: premier.destination) {
                        Label(action, systemImage: premier.symbole)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 46)
                            .background(Theme.degradeAccent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                boutonSynchroniser
            }
            etatDeLaSynchro
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                ImageDistante(url: ImageTMDB.url(affiche(0), .fond), coins: 0).blur(radius: 14).opacity(affiches.isEmpty ? 0 : 1).accessibilityHidden(true)
                LinearGradient(colors: [.black.opacity(0.88), .black.opacity(0.62), Theme.accent.opacity(0.28)], startPoint: .leading, endPoint: .trailing)
            }
        }
        .surImage()
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1))
    }

    /// Un seul geste pour mettre tous tes appareils d'accord : listes, soirées, notes, pouces, plateformes, chaînes et
    /// réglages passent par le dossier d'iCloud Drive (et le NAS s'il est activé). Sans dossier choisi, il mène au réglage.
    /// Un bouton à sa taille, pas toute la largeur de l'écran (6.6).
    @ViewBuilder
    private var boutonSynchroniser: some View {
        if etat.synchro.estPrete(nas: etat.nas.estConfigure) {
            Button {
                Task { await etat.synchro.synchroniser(etat: etat, contexte: contexte) }
            } label: {
                HStack(spacing: 8) {
                    if etat.synchro.enCours { ProgressView().tint(.black) } else { Image(systemName: "arrow.triangle.2.circlepath") }
                    Text(etat.synchro.enCours ? "Synchronisation…" : "Synchroniser").font(.subheadline.weight(.bold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .frame(minHeight: 46)
                .background(Theme.degradeAccent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(etat.synchro.enCours)
            .accessibilityLabel(etat.synchro.enCours ? "Synchronisation en cours" : "Synchroniser mes appareils maintenant")
            .accessibilityIdentifier("synchroniserMaintenant")
        } else {
            NavigationLink(value: DestinationReglage.sauvegarde) {
                Label("Synchroniser mes appareils", systemImage: "icloud")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentClair)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 46)
                    .background(Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    /// Sous les boutons : le dernier message de la synchronisation, ou sa date.
    @ViewBuilder
    private var etatDeLaSynchro: some View {
        if etat.synchro.estPrete(nas: etat.nas.estConfigure) {
            if let message = etat.synchro.dernierMessage {
                Text(message).font(.caption).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
            } else if let derniere = etat.synchro.derniereSynchro {
                Text("Dernière synchronisation \(derniere.formatted(.relative(presentation: .named))). Tes réglages voyagent aussi.")
                    .font(.caption).foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    // MARK: Libellés

    private var libelleAccueil: String {
        let sources = (try? JSONDecoder().decode(SourcesAccueil.self, from: sourcesBrutes)) ?? SourcesAccueil()
        return sources.modifiees ? "Personnalisé" : "Sections, nombre de titres, plateformes"
    }

    private var libelleLecteur: String {
        #if targetEnvironment(macCatalyst)
        "Lecteur du Mac"
        #else
        etat.nas.nomLecteur
        #endif
    }

    private var libelleLecture: String {
        etat.derniereLectureTele.map { "guide lu \($0.formatted(.relative(presentation: .named)))" } ?? "guide jamais lu"
    }

    private var libelleNAS: String {
        etat.nas.derniereAnalyse.map { "analysé \($0.formatted(.relative(presentation: .named)))" } ?? "configuré, jamais analysé"
    }

    /// Dans les deux derniers jours avant l'expiration de l'installation, la carte À propos le signale.
    private var expirationProche: String? {
        guard let expiration = etat.expirationInstallation, expiration.timeIntervalSinceNow < 2 * 86_400 else { return nil }
        return "Installation : \(ProfilInstallation.libelle(expiration: expiration))"
    }

    private var alertesActives: Bool {
        switch etat.alertes.autorisation {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    private var libelleAlertes: String {
        switch etat.alertes.autorisation {
        case .authorized, .provisional, .ephemeral: "Activées"
        case .denied: "Désactivées dans les réglages de l'appareil"
        default: "À activer"
        }
    }
}

/// Mise en forme commune des pages de réglages.
extension View {
    func pageReglages(_ titre: String) -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.fond)
            .navigationTitle(titre)
            .navigationBarTitleDisplayMode(.inline)
    }
}
