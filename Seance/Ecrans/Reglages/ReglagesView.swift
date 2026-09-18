import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Les pages de réglages, ouvertes par valeur (`destinationsTitres()` les déclare à la racine de chaque pile).
/// Un lien « par vue » vers Réglages, depuis la barre d'outils de Profil, figeait l'iPhone : SwiftUI remettait
/// la destination à jour à chaque rendu, sans fin, jusqu'à ce qu'iOS tue l'app.
enum DestinationReglage: Hashable {
    case reglages, prenom, apparence, tmdb, claude, plateformes, tele, nas, lecture, alertes, sauvegarde, aPropos, apercuWidgets
}

struct PageReglage: View {
    let destination: DestinationReglage

    var body: some View {
        switch destination {
        case .reglages: ReglagesView().navigationBarTitleDisplayMode(.inline)
        case .prenom: ReglagesPrenomView()
        case .apparence: ReglagesApparenceView()
        case .tmdb: ReglagesTMDBView()
        case .claude: ReglagesClaudeView()
        case .plateformes: ReglagesPlateformesView()
        case .tele: ReglagesTeleView()
        case .nas: ReglagesNASView()
        case .lecture: ReglagesLectureView()
        case .alertes: ReglagesAlertesView()
        case .sauvegarde: ReglagesSauvegardeView()
        case .aPropos: AProposView()
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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: enOrdre ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.headline)
                .foregroundStyle(enOrdre ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(titre).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let action, !enOrdre {
                Text(action)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(Theme.accent.opacity(0.2), in: Capsule())
                    .foregroundStyle(Theme.accentClair)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("État, \(titre) : \(detail)\(enOrdre ? "" : ", à régler")")
    }
}

/// Une carte de réglage : icône colorée, titre, état courant.
struct CarteReglage: View {
    let titre: String
    let symbole: String
    let couleur: Color
    let valeur: String
    /// L'état demande une action : il s'écrit en orange.
    var alerte = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbole)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(couleur.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(titre).font(.subheadline.weight(.semibold))
                Text(valeur)
                    .font(.caption)
                    .foregroundStyle(alerte ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(titre), \(valeur)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Réglages en tableau de bord : en tête, ce qui est en ordre et ce qui manque, chaque point menant à son réglage ;
/// puis une carte par réglage, rangée par thème (deux colonnes sur le Mac et l'iPad). Tes goûts et tes statistiques
/// sont dans Profil. Sans pile de navigation : onglet à part sur le Mac, page ouverte depuis Profil sur l'iPhone.
struct ReglagesView: View {
    @Environment(EtatApp.self) private var etat
    @Query(filter: #Predicate<Abonnement> { $0.actif }, sort: \Abonnement.nom) private var abonnements: [Abonnement]
    @Query(filter: #Predicate<Chaine> { $0.active }) private var chaines: [Chaine]
    @AppStorage(Prenom.cle) private var prenom = ""
    @AppStorage(NombreIdees.cle) private var nombreIdees = NombreIdees.parDefaut
    @AppStorage(Apparence.cle) private var apparence = Apparence.sombre.rawValue
    @AppStorage("accueil.sources") private var sourcesBrutes = Data()
    @State private var accueil = false

    private static let colonnes = [GridItem(.adaptive(minimum: 300, maximum: 560), spacing: 12, alignment: .top)]

    private struct Carte: Identifiable {
        let id: DestinationReglage
        let titre: String
        let symbole: String
        let couleur: Color
        let valeur: String
        var alerte = false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                etatDeSeance

                VStack(alignment: .leading, spacing: 10) {
                    TitreSection("Toi")
                    LazyVGrid(columns: Self.colonnes, spacing: 12) {
                        lien(Carte(id: .prenom, titre: "Prénom et idées du soir", symbole: "person.fill", couleur: .pink,
                                   valeur: "\(Prenom.lire(prenom) ?? "Prénom à saisir") · \(Format.pluriel(NombreIdees.lire(nombreIdees), "idée")) à la fois"))
                        lien(Carte(id: .apparence, titre: "Apparence", symbole: Apparence.lire(apparence).symbole, couleur: .indigo,
                                   valeur: Apparence.lire(apparence).nom))
                        // L'accueil se personnalise dans sa feuille, la même que depuis l'accueil : un seul réglage, deux portes.
                        Button { accueil = true } label: {
                            CarteReglage(titre: "Accueil", symbole: "house.fill", couleur: .orange, valeur: libelleAccueil)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                }

                section("Où regarder", [
                    Carte(id: .plateformes, titre: "Plateformes", symbole: "play.rectangle.on.rectangle.fill", couleur: .red,
                          valeur: abonnements.isEmpty ? "Aucune" : abonnements.map(\.nom).formatted(.list(type: .and, width: .narrow)), alerte: abonnements.isEmpty),
                    Carte(id: .tele, titre: "Télévision", symbole: "tv.fill", couleur: .blue,
                          valeur: chaines.isEmpty ? "Aucune chaîne" : "\(chaines.count) chaînes · \(libelleLecture)", alerte: chaines.isEmpty),
                    Carte(id: .nas, titre: "NAS", symbole: "externaldrive.fill", couleur: .green,
                          valeur: etat.nas.estConfigure ? libelleNAS.prefix(1).uppercased() + libelleNAS.dropFirst() : "À configurer", alerte: !etat.nas.estConfigure),
                    Carte(id: .lecture, titre: "Lecture", symbole: "play.circle.fill", couleur: .mint, valeur: libelleLecteur),
                ])
                section("Me prévenir", [
                    Carte(id: .alertes, titre: "Alertes", symbole: "bell.badge.fill", couleur: .orange, valeur: libelleAlertes, alerte: !alertesActives),
                ])
                section("Tes données", [
                    Carte(id: .sauvegarde, titre: "Sauvegarde et synchronisation", symbole: "arrow.triangle.2.circlepath", couleur: .indigo,
                          valeur: etat.synchro.nomDossier.map { "Dossier « \($0) »" } ?? "Fichier, AirDrop ou dossier iCloud Drive"),
                ])
                section("L'app", cartesApp)
            }
            .padding(.vertical, 16)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.fond)
        .navigationTitle("Réglages")
        .task { await etat.alertes.actualiserAutorisation() }
        .sheet(isPresented: $accueil) {
            ReglageSourcesAccueil(sources: Binding {
                (try? JSONDecoder().decode(SourcesAccueil.self, from: sourcesBrutes)) ?? SourcesAccueil()
            } set: { nouvelles in
                sourcesBrutes = (try? JSONEncoder().encode(nouvelles)) ?? Data()
            }, abonnements: abonnements)
        }
    }

    private var cartesApp: [Carte] {
        var cartes = [
            Carte(id: .tmdb, titre: "TMDB", symbole: "film.stack", couleur: .teal, valeur: etat.tmdb == nil ? "Clé à saisir" : "Connecté", alerte: etat.tmdb == nil),
            Carte(id: .claude, titre: "Claude", symbole: "sparkles", couleur: .purple, valeur: etat.claude == nil ? "Facultatif" : "Connecté"),
            Carte(id: .aPropos, titre: "À propos", symbole: "info.circle.fill", couleur: .gray, valeur: expirationProche ?? (etat.journal.entrees.isEmpty ? "Versions, journal, espace utilisé" : "Journal : \(Format.pluriel(etat.journal.entrees.count, "entrée"))"),
                  alerte: expirationProche != nil),
        ]
        #if DEBUG
        if ApercuWidgetsView.actif {
            cartes.append(Carte(id: .apercuWidgets, titre: "Aperçu des widgets", symbole: "square.grid.2x2.fill", couleur: .gray, valeur: "Développement"))
        }
        #endif
        return cartes
    }

    private func lien(_ carte: Carte) -> some View {
        NavigationLink(value: carte.id) {
            CarteReglage(titre: carte.titre, symbole: carte.symbole, couleur: carte.couleur, valeur: carte.valeur, alerte: carte.alerte)
        }
        .buttonStyle(.plain)
    }

    private func section(_ titre: String, _ cartes: [Carte]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TitreSection(titre)
            LazyVGrid(columns: Self.colonnes, spacing: 12) {
                ForEach(cartes) { lien($0) }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: État de Séance

    private var etatDeSeance: some View {
        let manques = [etat.tmdb == nil, abonnements.isEmpty, chaines.isEmpty, !etat.nas.estConfigure, !alertesActives].filter { $0 }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: manques == 0 ? "checkmark.seal.fill" : "wrench.adjustable.fill")
                    .font(.title3)
                    .foregroundStyle(manques == 0 ? AnyShapeStyle(Color.green) : AnyShapeStyle(Theme.degradeAccent))
                VStack(alignment: .leading, spacing: 1) {
                    Text(manques == 0 ? "Séance est prête" : "\(Format.pluriel(manques, "réglage", "réglages")) à compléter")
                        .font(.headline)
                    Text(manques == 0 ? "Plateformes, télé, NAS et alertes : tout est branché." : "Touche une ligne orange pour la régler.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Divider().overlay(Theme.trait)
            ligne(.tmdb, "TMDB", etat.tmdb == nil ? "Les fiches et les affiches en viennent" : "Fiches, affiches et plateformes", etat.tmdb != nil, "Saisir")
            ligne(.plateformes, "Plateformes", abonnements.isEmpty ? "Pour savoir ce que tu peux regarder" : abonnements.map(\.nom).formatted(.list(type: .and, width: .narrow)),
                  !abonnements.isEmpty, "Choisir")
            ligne(.tele, "Télévision", chaines.isEmpty ? "Choisis tes chaînes" : "\(chaines.count) chaînes · \(libelleLecture)", !chaines.isEmpty, "Choisir")
            ligne(.nas, "NAS", etat.nas.estConfigure ? libelleNAS.prefix(1).uppercased() + libelleNAS.dropFirst() : "Tes films déjà téléchargés",
                  etat.nas.estConfigure, "Configurer")
            ligne(.alertes, "Alertes", alertesActives ? "Épisodes, sorties et passages à la télé" : "Rien ne te sera annoncé", alertesActives, "Activer")
            ligne(.sauvegarde, "Synchronisation", etat.synchro.nomDossier.map { "Dossier « \($0) »" } ?? "Facultative : iPhone, iPad et Mac à jour",
                  true, nil)
            if let expiration = etat.expirationInstallation {
                let libelle = ProfilInstallation.libelle(expiration: expiration)
                ligne(.aPropos, "Installation", libelle.prefix(1).uppercased() + libelle.dropFirst(), expiration.timeIntervalSinceNow > 2 * 86_400, "Voir")
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 20)
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

/// L'app qui lit les vidéos du NAS : Infuse ou VLC, avec pour chacune si elle est installée et ce qu'elle demande.
struct ReglagesLectureView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            #if targetEnvironment(macCatalyst)
            Section {
                Label("Le lecteur vidéo par défaut du Mac", systemImage: "play.rectangle.fill")
            } footer: {
                Text("Sur le Mac, Séance ouvre le fichier du NAS dans l'app que macOS associe aux vidéos (IINA, VLC, Infuse…). Pour en changer : dans le Finder, « Lire les informations » sur une vidéo, puis « Ouvrir avec » et « Tout modifier ».")
            }
            #else
            Section {
                ForEach(LecteurVideo.allCases) { lecteur in
                    let installe = UIApplication.shared.canOpenURL(URL(string: "\(lecteur.schema)://")!)
                    Button {
                        etat.nas.choisir(lecteur)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: etat.nas.lecteur == lecteur ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(etat.nas.lecteur == lecteur ? AnyShapeStyle(Theme.accentClair) : AnyShapeStyle(.tertiary))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lecteur.nom).font(.headline).foregroundStyle(Color.primary)
                                Text(installe ? "Installée" : "Pas installée sur cet appareil")
                                    .font(.caption)
                                    .foregroundStyle(installe ? AnyShapeStyle(Color.green) : AnyShapeStyle(Color.orange))
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(lecteur.nom), \(installe ? "installée" : "pas installée")")
                    .accessibilityAddTraits(etat.nas.lecteur == lecteur ? .isSelected : [])
                    if !installe {
                        Button("Installer \(lecteur.nom) depuis l'App Store") { openURL(lecteur.appStore) }
                            .font(.subheadline)
                    }
                }
            } header: {
                Text("Ouvrir les vidéos du NAS avec")
            } footer: {
                Text("Toucher un film ou un épisode « Sur ton NAS » l'ouvre dans cette app ; un appui long propose l'autre.")
            }

            Section("Ce que chaque app demande") {
                Label {
                    Text("**Infuse** ouvre le titre dans sa propre bibliothèque et démarre la lecture : ajoute d'abord le partage de ton NAS dans Infuse, et laisse-le indexer tes films. Un fichier qu'Infuse n'a pas reconnu ne s'ouvre pas ; Séance propose alors VLC.")
                } icon: { Image(systemName: "1.circle.fill").foregroundStyle(Theme.accentClair) }
                Label {
                    Text("**VLC** lit directement le fichier sur le NAS, avec l'adresse et le mot de passe enregistrés dans Réglages › NAS. Rien à préparer dans VLC.")
                } icon: { Image(systemName: "2.circle.fill").foregroundStyle(Theme.accentClair) }
            }
            .font(.subheadline)
            #endif
        }
        .pageReglages("Lecture")
    }
}

/// Sombre, clair, ou comme l'appareil : trois aperçus à toucher.
struct ReglagesApparenceView: View {
    @AppStorage(Apparence.cle) private var apparence = Apparence.sombre.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Apparence.allCases) { choix in
                        let actif = Apparence.lire(apparence) == choix
                        Button {
                            withAnimation(.easeOut(duration: 0.25)) { apparence = choix.rawValue }
                        } label: {
                            VStack(spacing: 10) {
                                apercu(choix)
                                    .frame(height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(actif ? AnyShapeStyle(Theme.degradeAccent) : AnyShapeStyle(Theme.trait), lineWidth: actif ? 3 : 1)
                                    }
                                Label(choix.nom, systemImage: actif ? "checkmark.circle.fill" : choix.symbole)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .foregroundStyle(actif ? AnyShapeStyle(Theme.accentClair) : AnyShapeStyle(.primary))
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Apparence \(choix.nom)")
                        .accessibilityAddTraits(actif ? .isSelected : [])
                    }
                }
                Text("Sombre est l'apparence d'origine de Séance, pensée pour le soir. « Automatique » suit le réglage de ton appareil, et change avec lui. Les grandes images gardent leur texte clair dans les deux cas.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.fond)
        .navigationTitle("Apparence")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Une page miniature : un bandeau, un titre, deux affiches. « Automatique » montre les deux moitiés.
    @ViewBuilder
    private func apercu(_ choix: Apparence) -> some View {
        switch choix {
        case .sombre: miniature(sombre: true)
        case .clair: miniature(sombre: false)
        case .systeme:
            GeometryReader { geometrie in
                ZStack(alignment: .leading) {
                    miniature(sombre: false)
                    miniature(sombre: true)
                        .mask(alignment: .leading) { Rectangle().frame(width: geometrie.size.width / 2) }
                }
            }
        }
    }

    private func miniature(sombre: Bool) -> some View {
        let fond = sombre ? Color(red: 0.04, green: 0.04, blue: 0.055) : Color(red: 0.965, green: 0.96, blue: 0.955)
        let encre = sombre ? Color.white : Color.black
        return VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 5).fill(Theme.degradeAccent).frame(height: 34)
            RoundedRectangle(cornerRadius: 2).fill(encre.opacity(0.75)).frame(width: 46, height: 6)
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4).fill(encre.opacity(0.14)).frame(height: 38)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(fond)
    }
}

/// Ligne de catégorie, dans Réglages et Profil : pastille colorée, titre et état courant à droite.
struct LigneReglage: View {
    let titre: String
    let symbole: String
    let couleur: Color
    let valeur: String?
    /// Pour une ligne-bouton (feuille, plein écran) : le chevron que les liens de navigation ont d'office.
    var chevron = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbole)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(couleur.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(titre)
            Spacer()
            if let valeur {
                Text(valeur).foregroundStyle(.secondary)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        // Dans un bouton sans style, seul le contenu dessiné reçoit les clics : l'espace vide de la ligne aussi, ainsi.
        .contentShape(Rectangle())
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

/// Ton prénom : Séance s'en sert pour te saluer sur l'accueil et quand elle te propose des idées. Il reste sur l'appareil.
struct ReglagesPrenomView: View {
    @AppStorage(Prenom.cle) private var prenom = ""
    @AppStorage(NombreIdees.cle) private var nombreIdees = NombreIdees.parDefaut

    var body: some View {
        Form {
            Section {
                TextField("Ton prénom", text: $prenom)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                if Prenom.lire(prenom) != nil {
                    Button("Effacer", role: .destructive) { prenom = "" }
                }
            } header: {
                Text("Prénom")
            } footer: {
                Text(Prenom.lire(prenom).map { "« \(Prenom.salut($0)) » sur l'accueil, « Des idées pour toi, \($0) » le soir. Ton prénom reste sur cet appareil." }
                     ?? "Séance te saluera par ton prénom sur l'accueil et quand elle te propose des idées. Sans prénom, les phrases restent neutres.")
            }

            Section {
                Picker("Idées à la fois", selection: Binding { NombreIdees.lire(nombreIdees) } set: { nombreIdees = $0 }) {
                    ForEach(NombreIdees.choix, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Idées pour ce soir")
            } footer: {
                Text("Le nombre d'idées que « Idées pour ce soir » te montre à la fois. Celles que tu écartes sont remplacées par les suivantes.")
            }
        }
        .pageReglages("Toi")
    }
}

/// EF-42 : clé TMDB, testée avant d'être enregistrée dans le trousseau.
struct ReglagesTMDBView: View {
    @Environment(EtatApp.self) private var etat
    @State private var jeton = ""
    @State private var enTest = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                if etat.tmdb != nil {
                    LabeledContent("Clé TMDB", value: "enregistrée")
                    Button("Supprimer la clé", role: .destructive) {
                        try? etat.supprimerCle()
                        message = nil
                    }
                } else {
                    SecureField("Clé d'API ou jeton d'accès en lecture", text: $jeton)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task { await tester() }
                    } label: {
                        HStack {
                            Text("Enregistrer et tester")
                            if enTest { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(jeton.isEmpty || enTest)
                    Link("Obtenir une clé sur themoviedb.org", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                Text("TMDB fournit les fiches, les affiches et les plateformes. La clé reste dans le trousseau de l'appareil.")
            }
        }
        .pageReglages("TMDB")
    }

    private func tester() async {
        enTest = true
        defer { enTest = false }
        do {
            try await etat.enregistrerCle(jeton)
            jeton = ""
            message = "Clé acceptée par TMDB."
        } catch ErreurTMDB.identifiantsRefuses {
            message = "TMDB refuse cette clé. Vérifie-la sur themoviedb.org, dans Paramètres › API."
        } catch {
            message = Journal.conseil(error) ?? "Le test n'a pas abouti : vérifie la connexion Internet, puis réessaie."
            etat.journal.noter(.tmdb, "La clé TMDB n'a pas pu être testée.", erreur: error)
        }
    }
}

/// EF-27 : clé Claude facultative, pour que « Idées pour ce soir » lise une envie précisée.
struct ReglagesClaudeView: View {
    @Environment(EtatApp.self) private var etat
    @State private var cleClaude = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                if etat.claude != nil {
                    LabeledContent("Clé Claude", value: "enregistrée")
                    Button("Supprimer la clé", role: .destructive) {
                        try? etat.supprimerCleClaude()
                        message = nil
                    }
                } else {
                    SecureField("Clé d'API (sk-ant-…)", text: $cleClaude)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Enregistrer la clé") {
                        do {
                            try etat.enregistrerCleClaude(cleClaude)
                            cleClaude = ""
                            message = "Clé enregistrée dans le trousseau."
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                    .disabled(cleClaude.isEmpty)
                    Link("Créer une clé sur console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Sans clé, « Idées pour ce soir » classe les titres sur l'appareil, selon tes goûts. Avec une clé, Claude lit l'envie que tu précises et choisit parmi les titres disponibles : environ 0,07 $ par demande.")
            }
        }
        .pageReglages("Claude")
    }
}

/// EF-43 : plateformes auxquelles Patrick est abonné, parmi celles que TMDB connaît en Suisse.
struct ReglagesPlateformesView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query private var abonnements: [Abonnement]
    @State private var catalogue: [FournisseurCatalogue] = []

    var body: some View {
        Form {
            Section {
                if etat.tmdb == nil {
                    Text("Enregistre d'abord la clé TMDB.").foregroundStyle(.secondary)
                } else if catalogue.isEmpty {
                    ProgressView()
                }
                ForEach(catalogue) { fournisseur in
                    Toggle(fournisseur.nom, isOn: liaison(fournisseur))
                }
            } footer: {
                Text("Disponibilités en Suisse fournies par JustWatch, via TMDB.")
            }
        }
        .pageReglages("Plateformes")
        .task(id: etat.tmdb == nil) { await charger() }
    }

    private func charger() async {
        guard let client = etat.tmdb else { return }
        let liste = (try? await client.catalogueFournisseurs(.film)) ?? []
        catalogue = liste.sorted { ($0.priorites["CH"] ?? .max) < ($1.priorites["CH"] ?? .max) }
    }

    private func liaison(_ fournisseur: FournisseurCatalogue) -> Binding<Bool> {
        Binding {
            abonnements.contains { $0.providerID == fournisseur.id && $0.actif }
        } set: { actif in
            if let existant = abonnements.first(where: { $0.providerID == fournisseur.id }) {
                existant.actif = actif
            } else if actif {
                contexte.insert(Abonnement(providerID: fournisseur.id, nom: fournisseur.nom, cheminLogo: fournisseur.cheminLogo))
            }
            try? contexte.save()
        }
    }
}

/// EF-45 à EF-51 : chaînes reçues et lecture du guide.
struct ReglagesTeleView: View {
    @Environment(EtatApp.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query private var chaines: [Chaine]
    @State private var nonReconnusVisibles = false

    var body: some View {
        Form {
            Section {
                if etat.teleEnCours {
                    HStack {
                        Text("Lecture des programmes…")
                        Spacer()
                        ProgressView()
                    }
                } else if let derniere = etat.derniereLectureTele {
                    LabeledContent("Dernière lecture") {
                        Text(derniere, format: .relative(presentation: .named))
                    }
                }
                if let rapport = etat.rapportTele {
                    LabeledContent("Films reconnus", value: "\(rapport.filmsRattaches) sur \(rapport.filmsLus)")
                    LabeledContent("Diffusions à venir", value: "\(rapport.diffusionsEnregistrees)")
                    if !rapport.filmsNonRattaches.isEmpty {
                        DisclosureGroup("Films non reconnus (\(rapport.filmsNonRattaches.count))", isExpanded: $nonReconnusVisibles) {
                            ForEach(rapport.filmsNonRattaches, id: \.self) { titre in
                                Text(titre).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let erreur = etat.erreurTele {
                    Label(erreur, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Actualiser maintenant") {
                    Task { await etat.actualiserTele(contexte: contexte, force: true) }
                }
                .disabled(etat.teleEnCours || etat.tmdb == nil)
            } header: {
                Text("Guide des programmes")
            } footer: {
                Text("Le guide est relu toutes les 12 heures et dès que tu changes de chaînes. Un film n'apparaît que s'il est reconnu dans TMDB sans hésitation.")
            }

            Section {
                ForEach(ChaineGuide.suisses) { chaine in
                    Toggle(chaine.nom, isOn: liaison(chaine))
                }
            } header: {
                Text("Suisse")
            } footer: {
                Text("Avec la RTS, Séance télécharge le guide complet (18 Mo) au lieu du guide TNT (1 Mo).")
            }

            Section {
                ForEach(ChaineGuide.tntParDefaut) { chaine in
                    Toggle(chaine.nom, isOn: liaison(chaine))
                }
            } header: {
                Text("France")
            } footer: {
                Text("Programmes : XML TV Fr, projet bénévole, sans garantie.")
            }
        }
        .pageReglages("Télévision")
        // Les chaînes ont pu changer : le guide est relu en quittant la page, si nécessaire.
        .onDisappear {
            Task { await etat.actualiserTele(contexte: contexte) }
        }
    }

    private func liaison(_ chaine: ChaineGuide) -> Binding<Bool> {
        Binding {
            chaines.contains { $0.identifiantGuide == chaine.id && $0.active }
        } set: { active in
            if let existante = chaines.first(where: { $0.identifiantGuide == chaine.id }) {
                existante.active = active
            } else if active {
                contexte.insert(Chaine(identifiantGuide: chaine.id, nom: chaine.nom, source: .xmltvfr))
            }
            try? contexte.save()
        }
    }
}

/// À propos (EF-44) : l'application, ses sources et les droits d'auteur, et l'historique des versions.
struct AProposView: View {
    @Environment(EtatApp.self) private var etat

    enum Onglet: String, CaseIterable, Identifiable {
        case application = "Séance"
        case versions = "Versions"
        case journal = "Journal"

        var id: String { rawValue }
    }

    @State private var onglet = Onglet.application

    private var numeroVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.9"
    }

    private var version: String {
        let construction = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(numeroVersion) (\(construction))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .accessibilityHidden(true)
                    Text("Séance").font(.title.weight(.heavy))
                    Text(version).font(.footnote).foregroundStyle(.secondary)
                    // Compte Apple gratuit : l'installation expire au bout de 7 jours.
                    if let expiration = etat.expirationInstallation {
                        let bientot = expiration.timeIntervalSinceNow < 2 * 86_400
                        Label("Installation valable jusqu'au \(expiration.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute().locale(Locale(identifier: "fr_CH")))) · \(ProfilInstallation.libelle(expiration: expiration))",
                              systemImage: bientot ? "exclamationmark.triangle.fill" : "clock")
                            .font(.footnote.weight(bientot ? .semibold : .regular))
                            .foregroundStyle(bientot ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                            .multilineTextAlignment(.center)
                        if bientot {
                            Text("Relance outils/installer.sh sur le Mac pour prolonger de 7 jours : tes données restent.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    Picker("Onglet", selection: $onglet) {
                        ForEach(Onglet.allCases) { onglet in
                            Text(onglet.rawValue).tag(onglet)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            switch onglet {
            case .application:
                application
            case .versions:
                ListeVersions(versionInstallee: numeroVersion)
            case .journal:
                SectionsJournal()
            }

            Section {
                Text("© 2026 Patrick Pinard. Tous droits réservés.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.fond)
        .navigationTitle("À propos")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var application: some View {
        Section("L'application") {
            Text("Séance est ton guide personnel des films et séries d'action. Elle te dit où regarder chaque titre en Suisse : sur tes plateformes, à la télévision ou sur ton NAS, ou comment l'obtenir légalement.")
            Text("Elle suit tes séries épisode par épisode, garde la trace de ce que tu as vu et te prévient des nouvelles saisons, des sorties et des passages à la télé. « Idées pour ce soir » propose des titres regardables sur tes plateformes, choisis selon tes goûts, et « Ma soirée » réunit ce que tu gardes pour ce soir.")
            Text("Tes données restent sur ton appareil. Une sauvegarde dans un fichier, depuis Réglages › Sauvegarde, les protège et permet de les reprendre sur un autre appareil.")
        }

        EspaceUtilise()

        Section("Sources des données") {
            Text("Cette application utilise TMDB et les API de TMDB, mais n'est ni approuvée, ni certifiée, ni validée par TMDB.")
            Text("Disponibilités sur les plateformes : JustWatch.")
            Text("Programmes TV de la RTS et des chaînes françaises : XML TV Fr, projet bénévole.")
            Text("Accès au NAS : AMSMB2 et libsmb2, sous licence LGPL.")
        }
    }
}

/// Espace occupé par Séance, par nature de données, et vidage des images en cache.
private struct EspaceUtilise: View {
    @State private var volumetrie: Volumetrie?
    @State private var enVidage = false

    var body: some View {
        Section {
            if let volumetrie {
                LabeledContent("Application", value: Self.format(volumetrie.application))
                LabeledContent("Tes données", value: Self.format(volumetrie.donnees))
                LabeledContent("Fiches, télé et NAS en cache", value: Self.format(volumetrie.cache))
                LabeledContent("Affiches en cache", value: Self.format(volumetrie.images))
                if volumetrie.divers > 0 {
                    LabeledContent("Widgets et journal", value: Self.format(volumetrie.divers))
                }
                LabeledContent {
                    Text(Self.format(volumetrie.total)).fontWeight(.semibold)
                } label: {
                    Text("Total").fontWeight(.semibold)
                }
                Button("Vider les affiches en cache", role: .destructive) {
                    enVidage = true
                    CacheImages.partage.vider()
                    Task {
                        self.volumetrie = await Volumetrie.mesurer()
                        enVidage = false
                    }
                }
                .disabled(enVidage || volumetrie.images == 0)
            } else {
                HStack {
                    Text("Mesure en cours…").foregroundStyle(.secondary)
                    Spacer()
                    ProgressView()
                }
            }
        } header: {
            Text("Espace utilisé")
        } footer: {
            Text("Tes données sont ce que la sauvegarde protège. Le reste se reconstruit tout seul : les affiches se rechargent quand elles s'affichent.")
        }
        .task { volumetrie = await Volumetrie.mesurer() }
    }

    private static func format(_ octets: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: octets, countStyle: .file)
    }
}
