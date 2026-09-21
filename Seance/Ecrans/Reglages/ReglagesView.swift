import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Les pages de réglages, ouvertes par valeur (`destinationsTitres()` les déclare à la racine de chaque pile).
/// Un lien « par vue » vers Réglages, depuis la barre d'outils de Profil, figeait l'iPhone : SwiftUI remettait
/// la destination à jour à chaque rendu, sans fin, jusqu'à ce qu'iOS tue l'app.
enum DestinationReglage: Hashable {
    case reglages, prenom, famille, apparence, tmdb, claude, plateformes, tele, nas, videosPerso, lecture, alertes, sauvegarde, lettre, aPropos, versions, journal, apercuWidgets
}

struct PageReglage: View {
    let destination: DestinationReglage

    var body: some View {
        switch destination {
        case .reglages: ReglagesView().navigationBarTitleDisplayMode(.inline)
        case .prenom: ReglagesPrenomView()
        case .famille: FamilleView()
        case .apparence: ReglagesApparenceView()
        case .tmdb: ReglagesTMDBView()
        case .claude: ReglagesClaudeView()
        case .plateformes: ReglagesPlateformesView()
        case .tele: ReglagesTeleView()
        case .nas: ReglagesNASView()
        case .videosPerso: ReglagesVideosPersoView()
        case .lecture: ReglagesLectureView()
        case .alertes: ReglagesAlertesView()
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

/// Une ligne de la carte « État de Séance » : verte quand c'est en ordre, orange avec son action quand il manque quelque chose.
private struct LigneEtat: View {
    let titre: String
    let detail: String
    let enOrdre: Bool
    var action: String?

    @Environment(\.dynamicTypeSize) private var tailleTexte

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: enOrdre ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.headline)
                .foregroundStyle(enOrdre ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(titre).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(tailleTexte.isAccessibilitySize ? 3 : 1)
                // En texte agrandi, l'action passe sous le libellé : à côté, elle le coupait en deux.
                if tailleTexte.isAccessibilitySize { pastilleAction.padding(.top, 4) }
            }
            Spacer(minLength: 4)
            if !tailleTexte.isAccessibilitySize { pastilleAction }
            // Chaque ligne s'ouvre : celles qui sont en ordre le disent d'un chevron.
            if enOrdre || action == nil { Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary).padding(.top, 3) }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(titre), \(detail), \(enOrdre ? "en ordre" : "à régler")")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var pastilleAction: some View {
        if let action, !enOrdre {
            Text(action)
                .font(.caption.weight(.bold))
                .fixedSize()
                .padding(.horizontal, 10).frame(minHeight: 28)
                .background(Theme.accent.opacity(0.2), in: Capsule())
                .foregroundStyle(Theme.accentClair)
        }
    }
}

/// Une grande carte de réglage, dans le dessin des cartes de « Ce soir » : une affiche de tes titres floutée en fond, le
/// symbole de l'app en orange, le nom en gros, l'état en pastille (« En ordre », « À régler ») et sa valeur dessous.
struct CarteReglage: View {
    let titre: String
    let symbole: String
    let detail: String
    let enOrdre: Bool
    var cheminAffiche: String?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Label(enOrdre ? "En ordre" : "À régler", systemImage: enOrdre ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(enOrdre ? Color.green : Color.orange)
                    .padding(.horizontal, 8).frame(minHeight: 22)
                    .background(.black.opacity(0.55), in: Capsule())
                Text(titre).font(.title3.weight(.heavy)).lineLimit(2)
                Text(detail).font(.footnote).foregroundStyle(.white.opacity(0.8)).lineLimit(2).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: symbole)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.degradeAccent)
                .frame(width: 48)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background {
            ZStack {
                Theme.surface
                if let cheminAffiche {
                    ImageDistante(url: ImageTMDB.url(cheminAffiche, .affiche), coins: 0).blur(radius: 6).accessibilityHidden(true)
                }
                LinearGradient(colors: [.black.opacity(0.9), .black.opacity(0.62), .black.opacity(0.3)], startPoint: .leading, endPoint: .trailing)
            }
        }
        .surImage()
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(enOrdre ? Color.white.opacity(0.1) : Color.orange.opacity(0.55), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(titre), \(detail), \(enOrdre ? "en ordre" : "à régler")")
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
            VStack(alignment: .leading, spacing: 24) {
                etatDeSeance

                // Piste B (EF-169) : l'état ci-dessus est l'unique entrée de ce qu'il surveille — TMDB, plateformes, TV,
                // NAS, lecture, alertes, sauvegarde. Dessous, seulement le reste, en tuiles : plus aucun réglage en double.
                rubrique("Toi") {
                    tuile(.prenom, "Prénom et idées", "person.fill",
                          "\(Prenom.lire(prenom) ?? "Prénom à saisir") · \(Format.pluriel(NombreIdees.lire(nombreIdees), "idée"))")
                    tuile(.apparence, "Apparence", Apparence.lire(apparence).symbole, Apparence.lire(apparence).nom)
                    tuile(.lettre, "E-mail de la semaine", "envelope.fill",
                          !etat.lettre.reglages.actif ? "Tes sorties, chaque semaine" : etat.lettre.pret ? Format.pluriel(etat.lettre.adresses.count, "destinataire") : "À terminer",
                          alerte: etat.lettre.reglages.actif && !etat.lettre.pret)
                    // L'accueil se personnalise dans sa feuille, la même que depuis l'accueil : un seul réglage, deux portes.
                    Button { accueil = true } label: { TuileReglage(titre: "Accueil", symbole: "house.fill", valeur: libelleAccueil) }
                        .buttonStyle(.plain)
                }
                rubrique("La maison") {
                    tuile(.famille, "Famille", "person.2.fill",
                          ProfilsFamille().aPlusieursProfils ? ProfilsFamille().profils.map { $0.prenom.isEmpty ? "Moi" : $0.prenom }.joined(separator: ", ")
                                                             : "Un profil par personne : listes, notes, idées")
                }
                rubrique("Tes appareils") {
                    Button { nouvelAppareil = true } label: {
                        TuileReglage(titre: "Nouvel appareil", symbole: "iphone.and.arrow.forward", valeur: "Reprendre tes données, ta clé et ton NAS")
                    }
                    .buttonStyle(.plain)
                    Button { envoiAppleTV = true } label: {
                        TuileReglage(titre: "Envoyer à un appareil", symbole: "appletv.fill", valeur: "Apple TV, iPad, Mac : un code, et tout y arrive")
                    }
                    .buttonStyle(.plain)
                }
                rubrique("L'app") {
                    tuile(.claude, "Claude", "sparkles", etat.claude == nil ? "Facultatif" : "Connecté")
                    // Trois portes au lieu d'une page à onglets : ce que fait Séance, ce qui a changé, ce qui s'est passé.
                    tuile(.aPropos, "Séance", "info.circle.fill", expirationProche ?? "Ce qu'elle fait, ses sources, l'espace utilisé",
                          alerte: expirationProche != nil)
                    tuile(.versions, "Versions", "clock.arrow.circlepath", "Version \(NoteVersion.historique.first?.numero ?? "") · ce qui a changé")
                    tuile(.journal, "Journal", "list.bullet.rectangle",
                          etat.journal.entrees.isEmpty ? "Rien à signaler" : Format.pluriel(etat.journal.entrees.count, "entrée"))
                    #if DEBUG
                    if ApercuWidgetsView.actif { tuile(.apercuWidgets, "Aperçu des widgets", "square.grid.2x2.fill", "Développement") }
                    #endif
                }
            }
            .padding(.vertical, 16)
            .frame(maxWidth: 1180, alignment: .leading)
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

    private func rubrique(_ titre: String, @ViewBuilder _ tuiles: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TitreSection(titre)
            LazyVGrid(columns: Self.colonnes, spacing: 12) { tuiles() }
                .padding(.horizontal, 20)
        }
    }

    private func tuile(_ destination: DestinationReglage, _ titre: String, _ symbole: String, _ valeur: String, alerte: Bool = false) -> some View {
        NavigationLink(value: destination) {
            TuileReglage(titre: titre, symbole: symbole, valeur: valeur, alerte: alerte)
        }
        .buttonStyle(.plain)
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
            PointEtat(destination: .tele, titre: "Télévision", symbole: "tv.fill",
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
                               detail: "Tes vidéos du NAS s'ouvrent dans \(etat.nas.lecteur.nom)", enOrdre: true, action: nil))
        #endif
        liste.append(PointEtat(destination: .alertes, titre: "Alertes", symbole: "bell.fill",
                               detail: alertesActives ? "Épisodes, sorties et passages à la TV" : "Rien ne te sera annoncé", enOrdre: alertesActives, action: "Activer les alertes"))
        liste.append(PointEtat(destination: .sauvegarde, titre: "Sauvegarde et synchronisation", symbole: "arrow.triangle.2.circlepath",
                               detail: etat.synchro.nomDossier.map { "Dossier « \($0) »" } ?? "Fichier, AirDrop ou dossier iCloud Drive", enOrdre: true, action: nil))
        if let expiration = etat.expirationInstallation {
            let libelle = ProfilInstallation.libelle(expiration: expiration)
            liste.append(PointEtat(destination: .aPropos, titre: "Installation", symbole: "clock.fill",
                                   detail: libelle.prefix(1).uppercased() + libelle.dropFirst(), enOrdre: expiration.timeIntervalSinceNow > 2 * 86_400, action: "Voir l'installation"))
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

    /// Grandes cartes : une par ligne sur l'iPhone, deux ou trois sur l'iPad et le Mac.
    private static let colonnesCartes = [GridItem(.adaptive(minimum: 300, maximum: 520), spacing: 12, alignment: .top)]

    /// Piste B de la maquette du 20 septembre 2026, avec l'en-tête de la piste C : en tête, où en est Séance et le geste du
    /// moment ; dessous, une grande carte par réglage surveillé, dans le dessin des cartes de « Ce soir ».
    private var etatDeSeance: some View {
        let points = points
        let manques = points.filter { !$0.enOrdre }
        return VStack(alignment: .leading, spacing: 14) {
            heros(points: points, manques: manques)
            LazyVGrid(columns: Self.colonnesCartes, spacing: 12) {
                ForEach(Array(points.enumerated()), id: \.element.id) { rang, point in
                    NavigationLink(value: point.destination) {
                        CarteReglage(titre: point.titre, symbole: point.symbole, detail: point.detail, enOrdre: point.enOrdre, cheminAffiche: affiche(rang))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func heros(points: [PointEtat], manques: [PointEtat]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(manques.isEmpty ? "Séance est prête" : "\(Format.pluriel(manques.count, "réglage", "réglages")) à compléter")
                    .font(.title2.weight(.heavy))
                Text(manques.isEmpty ? "Tout est branché." : "Le reste est branché. Les cartes orange restent à régler.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .accessibilityElement(children: .combine)
            // Le geste du moment : ce qui manque d'abord, sinon synchroniser.
            if let premier = manques.first, let action = premier.action {
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
            Flux(espacement: 6) {
                ForEach(points) { point in
                    HStack(spacing: 5) {
                        Circle().fill(point.enOrdre ? Color.green : Color.orange).frame(width: 8, height: 8)
                        Text(point.titre).font(.caption2.weight(.semibold))
                    }
                    .padding(.horizontal, 9).frame(minHeight: 24)
                    .background(.black.opacity(0.45), in: Capsule())
                }
            }
            .accessibilityHidden(true)
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
    @ViewBuilder
    private var boutonSynchroniser: some View {
        if etat.synchro.estPrete(nas: etat.nas.estConfigure) {
            Button {
                Task { await etat.synchro.synchroniser(etat: etat, contexte: contexte) }
            } label: {
                HStack(spacing: 10) {
                    if etat.synchro.enCours { ProgressView().tint(.black) } else { Image(systemName: "arrow.triangle.2.circlepath") }
                    Text(etat.synchro.enCours ? "Synchronisation…" : "Synchroniser mes appareils maintenant").font(.subheadline.weight(.bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Theme.degradeAccent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(etat.synchro.enCours)
            .accessibilityIdentifier("synchroniserMaintenant")
            if let message = etat.synchro.dernierMessage {
                Text(message).font(.caption).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
            } else if let derniere = etat.synchro.derniereSynchro {
                Text("Dernière synchronisation \(derniere.formatted(.relative(presentation: .named))). Tes réglages voyagent aussi.")
                    .font(.caption).foregroundStyle(.white.opacity(0.75))
            }
        } else {
            NavigationLink(value: DestinationReglage.sauvegarde) {
                Label("Synchroniser mes appareils : choisir le dossier iCloud Drive", systemImage: "icloud")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentClair)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func ligne(_ destination: DestinationReglage, _ titre: String, _ detail: String, _ enOrdre: Bool, _ action: String?) -> some View {
        NavigationLink(value: destination) {
            LigneEtat(titre: titre, detail: detail, enOrdre: enOrdre, action: action)
        }
        .buttonStyle(.plain)
    }

    // MARK: Libellés

    private var libelleAccueil: String {
        let sources = (try? JSONDecoder().decode(SourcesAccueil.self, from: sourcesBrutes)) ?? SourcesAccueil()
        return sources.modifiees ? "Personnalisé" : "Sections, nombre de titres, plateformes"
    }

    private var libelleLecteur: String {
        #if targetEnvironment(macCatalyst)
        "Le lecteur vidéo du Mac"
        #else
        "Les vidéos du NAS s'ouvrent dans \(etat.nas.lecteur.nom)"
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
