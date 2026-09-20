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
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("État, \(titre) : \(detail)\(enOrdre ? "" : ", à régler")")
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
    @State private var nouvelAppareil = false
    @State private var envoiAppleTV = false

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
                VStack(alignment: .leading, spacing: 10) {
                    TitreSection("Tes données")
                    LazyVGrid(columns: Self.colonnes, spacing: 12) {
                        lien(Carte(id: .sauvegarde, titre: "Sauvegarde et synchronisation", symbole: "arrow.triangle.2.circlepath", couleur: .indigo,
                                   valeur: etat.synchro.nomDossier.map { "Dossier « \($0) »" } ?? "Fichier, AirDrop ou dossier iCloud Drive"))
                        Button { nouvelAppareil = true } label: {
                            CarteReglage(titre: "Nouvel appareil", symbole: "iphone.and.arrow.forward", couleur: .cyan,
                                         valeur: "Reprendre tes données, ta clé et ton NAS")
                        }
                        .buttonStyle(.plain)
                        Button { envoiAppleTV = true } label: {
                            CarteReglage(titre: "Configurer mon Apple TV", symbole: "appletv.fill", couleur: .gray,
                                         valeur: "Un code sur la TV, et tout y arrive")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                }
                section("L'app", cartesApp)
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

/// Mise en forme commune des pages de réglages.
extension View {
    func pageReglages(_ titre: String) -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.fond)
            .navigationTitle(titre)
            .navigationBarTitleDisplayMode(.inline)
    }
}
