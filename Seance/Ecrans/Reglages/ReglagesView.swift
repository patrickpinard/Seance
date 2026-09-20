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
    @Query(filter: #Predicate<Abonnement> { $0.actif }, sort: \Abonnement.nom) private var abonnements: [Abonnement]
    @Query(filter: #Predicate<Chaine> { $0.active }) private var chaines: [Chaine]
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

                // Piste B (EF-169) : l'état ci-dessus est l'unique entrée de ce qu'il surveille — TMDB, plateformes, télé,
                // NAS, lecture, alertes, sauvegarde. Dessous, seulement le reste, en tuiles : plus aucun réglage en double.
                rubrique("Toi") {
                    tuile(.prenom, "Prénom et idées", "person.fill",
                          "\(Prenom.lire(prenom) ?? "Prénom à saisir") · \(Format.pluriel(NombreIdees.lire(nombreIdees), "idée"))")
                    tuile(.apparence, "Apparence", Apparence.lire(apparence).symbole, Apparence.lire(apparence).nom)
                    // L'accueil se personnalise dans sa feuille, la même que depuis l'accueil : un seul réglage, deux portes.
                    Button { accueil = true } label: { TuileReglage(titre: "Accueil", symbole: "house.fill", valeur: libelleAccueil) }
                        .buttonStyle(.plain)
                }
                rubrique("Tes appareils") {
                    Button { nouvelAppareil = true } label: {
                        TuileReglage(titre: "Nouvel appareil", symbole: "iphone.and.arrow.forward", valeur: "Reprendre tes données, ta clé et ton NAS")
                    }
                    .buttonStyle(.plain)
                    Button { envoiAppleTV = true } label: {
                        TuileReglage(titre: "Mon Apple TV", symbole: "appletv.fill", valeur: "Un code sur la TV, et tout y arrive")
                    }
                    .buttonStyle(.plain)
                }
                rubrique("L'app") {
                    tuile(.claude, "Claude", "sparkles", etat.claude == nil ? "Facultatif" : "Connecté")
                    tuile(.aPropos, "À propos", "info.circle.fill",
                          expirationProche ?? (etat.journal.entrees.isEmpty ? "Versions, journal, espace utilisé" : "Journal : \(Format.pluriel(etat.journal.entrees.count, "entrée"))"),
                          alerte: expirationProche != nil)
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
                    Text(manques == 0 ? "Tout est branché. Touche une ligne pour l'ouvrir." : "Touche une ligne pour l'ouvrir ; les orange restent à régler.")
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
            #if !targetEnvironment(macCatalyst)
            // Un seul lecteur : « Lire » n'ouvre que celui-ci, partout dans l'app.
            ligne(.lecture, "Lecture", "Tes vidéos du NAS s'ouvrent dans \(etat.nas.lecteur.nom)", true, nil)
            #endif
            ligne(.alertes, "Alertes", alertesActives ? "Épisodes, sorties et passages à la télé" : "Rien ne te sera annoncé", alertesActives, "Activer")
            ligne(.sauvegarde, "Sauvegarde et synchronisation", etat.synchro.nomDossier.map { "Dossier « \($0) »" } ?? "Fichier, AirDrop ou dossier iCloud Drive",
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
