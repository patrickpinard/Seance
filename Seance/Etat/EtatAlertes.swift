import BackgroundTasks
import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI
import UserNotifications

/// Alertes pop-up de l'iPhone (EF-81 à EF-85) : autorisation, programmation des notifications locales,
/// alerte d'essai et réglages. Aucun envoi par email : tout reste sur l'iPhone.
@MainActor
@Observable
final class EtatAlertes {
    private(set) var reglages: ReglagesAlertes
    private(set) var autorisation: UNAuthorizationStatus = .notDetermined
    private(set) var prochaines: [NotificationPrevue] = []
    private(set) var enCours = false
    private(set) var erreur: String?
    private(set) var derniereMiseAJour: Date?

    /// Identifiant déclaré dans `BGTaskSchedulerPermittedIdentifiers`.
    static let tacheFond = "ch.patrick.seance.rafraichissement"
    /// iOS garde au plus 64 notifications en attente par app.
    private static let maximumEnAttente = 60
    private static let prefixe = "seance.alerte."
    private let centre = UNUserNotificationCenter.current()
    /// Renseigné par l'état de l'app : les problèmes vont au journal d'À propos.
    var journal: Journal?

    private enum Cle {
        static let reglages = "alertes.reglages"
    }

    /// Les alertes qui parlent d'un titre portent un bouton « Ajouter à ma soirée » : sur l'iPhone (appui long sur
    /// l'alerte), et sur l'Apple Watch qui la recopie. Le bouton agit sans ouvrir l'app.
    nonisolated static let categorieTitre = "seance.titre"
    nonisolated static let actionSoiree = "seance.action.soiree"

    init() {
        let soiree = UNNotificationAction(identifier: Self.actionSoiree, title: "Ajouter à ma soirée", options: [],
                                          icon: UNNotificationActionIcon(systemImageName: "moon.stars"))
        centre.setNotificationCategories([UNNotificationCategory(identifier: Self.categorieTitre, actions: [soiree], intentIdentifiers: [])])
        reglages = UserDefaults.standard.data(forKey: Cle.reglages)
            .flatMap { try? JSONDecoder().decode(ReglagesAlertes.self, from: $0) } ?? ReglagesAlertes()
    }

    func modifier(_ changement: (inout ReglagesAlertes) -> Void) {
        changement(&reglages)
        UserDefaults.standard.set(try? JSONEncoder().encode(reglages), forKey: Cle.reglages)
    }

    func actualiserAutorisation() async {
        autorisation = await centre.notificationSettings().authorizationStatus
    }

    /// Demande l'autorisation une seule fois ; ensuite, seuls les Réglages d'iOS la changent.
    @discardableResult
    func demanderAutorisation() async -> Bool {
        let accordee = (try? await centre.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await actualiserAutorisation()
        return accordee
    }

    var autorisees: Bool {
        autorisation == .authorized || autorisation == .provisional || autorisation == .ephemeral
    }

    /// Recalcule les alertes et les échéances « À venir » des titres surveillés, puis remplace les
    /// notifications en attente si les alertes sont autorisées.
    func planifier(contexte: ModelContext, tmdb: TMDBClient?) async {
        guard !enCours, let tmdb else { return }
        await actualiserAutorisation()
        enCours = true
        erreur = nil
        defer { enCours = false }
        do {
            let notifications = try await ServiceAlertes(contexte: contexte).calculer(source: tmdb, reglages: reglages)
            prochaines = Array(notifications.prefix(Self.maximumEnAttente))
            derniereMiseAJour = .now
            programmerTacheFond()
            guard autorisees else { return }
            let enAttente = await centre.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefixe) }
            centre.removePendingNotificationRequests(withIdentifiers: enAttente)
            for notification in prochaines {
                try await centre.add(requete(notification))
            }
        } catch {
            self.erreur = "Les alertes n'ont pas pu être préparées."
            journal?.noter(.alertes, "Les alertes n'ont pas pu être préparées.", erreur: error)
        }
    }

    /// Au retour dans l'app : un recalcul par heure au plus.
    func planifierSiAncien(contexte: ModelContext, tmdb: TMDBClient?) async {
        if let derniereMiseAJour, Date.now.timeIntervalSince(derniereMiseAJour) < 3600 { return }
        await planifier(contexte: contexte, tmdb: tmdb)
    }

    /// La veille de l'expiration de l'installation (compte Apple gratuit), à l'heure des alertes : penser à réinstaller.
    /// Identifiant hors du préfixe des alertes, pour que leur recalcul ne l'efface pas.
    func programmerRappelExpiration(_ expiration: Date?) async {
        centre.removePendingNotificationRequests(withIdentifiers: ["seance.expiration"])
        guard let expiration, autorisees else { return }
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = reglages.fuseau
        guard let veille = calendrier.date(byAdding: .day, value: -1, to: expiration) else { return }
        var composants = calendrier.dateComponents([.year, .month, .day], from: veille)
        composants.hour = reglages.heure
        composants.minute = reglages.minute
        guard let date = calendrier.date(from: composants), date > .now else { return }
        let contenu = UNMutableNotificationContent()
        contenu.title = "Séance expire demain"
        contenu.body = "Relance outils/installer.sh sur le Mac pour la prolonger de 7 jours. Tes données restent sur l'appareil."
        contenu.sound = .default
        let declencheur = UNCalendarNotificationTrigger(dateMatching: calendrier.dateComponents(in: reglages.fuseau, from: date), repeats: false)
        try? await centre.add(UNNotificationRequest(identifier: "seance.expiration", content: contenu, trigger: declencheur))
    }

    /// Une soirée prévue à l'avance : le jour venu, à l'heure des alertes, un rappel de ce qui est au programme.
    /// Identifiants hors du préfixe des alertes, pour que leur recalcul ne les efface pas.
    func programmerRappelsSoirees(contexte: ModelContext) async {
        let anciens = await centre.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("seance.soiree.") }
        centre.removePendingNotificationRequests(withIdentifiers: anciens)
        await actualiserAutorisation()
        guard autorisees, let prevues = try? ServiceSoiree(contexte: contexte).aVenir() else { return }
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = reglages.fuseau
        for (soiree, titres) in Dictionary(grouping: prevues, by: \.soiree) {
            guard let jour = ServiceSoiree.jour(soiree, fuseau: reglages.fuseau) else { continue }
            var composants = calendrier.dateComponents([.year, .month, .day], from: jour)
            composants.hour = reglages.heure
            composants.minute = reglages.minute
            guard let date = calendrier.date(from: composants), date > .now else { continue }
            let contenu = UNMutableNotificationContent()
            contenu.title = "Ta soirée de ce soir"
            contenu.body = titres.map(\.titre).joined(separator: ", ")
            contenu.sound = .default
            contenu.threadIdentifier = "seance"
            contenu.userInfo = ["lien": "seance://cesoir"]
            let declencheur = UNCalendarNotificationTrigger(dateMatching: composants, repeats: false)
            try? await centre.add(UNNotificationRequest(identifier: "seance.soiree.\(soiree)", content: contenu, trigger: declencheur))
        }
    }

    // MARK: Rappels de passages TV

    /// Les passages TV dont tu as touché la cloche : « me le rappeler un quart d'heure avant ». Pour n'importe quel
    /// titre du programme, suivi ou non. Identifiants hors du préfixe des alertes : leur recalcul ne les efface pas.
    private(set) var rappelsTele: Set<String> = []
    private static let prefixeRappelTele = "seance.rappel.tele."
    static let avanceRappelTele: TimeInterval = 15 * 60

    static func cleRappel(chaine: String, debut: Date) -> String {
        "\(chaine)|\(Int(debut.timeIntervalSince1970))"
    }

    func aUnRappel(chaine: String, debut: Date) -> Bool {
        rappelsTele.contains(Self.cleRappel(chaine: chaine, debut: debut))
    }

    /// Relit les rappels encore programmés : ceux qui ont sonné ont disparu d'eux-mêmes.
    func actualiserRappelsTele() async {
        rappelsTele = Set(await centre.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix(Self.prefixeRappelTele) }.map { String($0.dropFirst(Self.prefixeRappelTele.count)) })
    }

    /// Pose ou retire le rappel d'un passage. Renvoie `nil` si les notifications sont refusées, sinon le nouvel état.
    func basculerRappelTele(titre: String, nomChaine: String, chaine: String, debut: Date, reference: ReferenceTitre?) async -> Bool? {
        let cle = Self.cleRappel(chaine: chaine, debut: debut)
        if rappelsTele.contains(cle) {
            centre.removePendingNotificationRequests(withIdentifiers: [Self.prefixeRappelTele + cle])
            rappelsTele.remove(cle)
            return false
        }
        if autorisation == .notDetermined { await demanderAutorisation() }
        await actualiserAutorisation()
        guard autorisees else { return nil }
        let contenu = UNMutableNotificationContent()
        let heure = debut.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "fr_CH")))
        contenu.title = "\(titre) commence bientôt"
        contenu.body = "Sur \(nomChaine) à \(heure)."
        contenu.sound = .default
        contenu.threadIdentifier = "seance"
        contenu.userInfo = ["lien": reference.map { "seance://\($0.type.rawValue)/\($0.tmdbID)" } ?? "seance://tele", "titre": titre]
        if reference != nil { contenu.categoryIdentifier = Self.categorieTitre }
        // Un quart d'heure avant ; pour un passage imminent, dans quelques secondes.
        let delai = max(5, debut.addingTimeInterval(-Self.avanceRappelTele).timeIntervalSinceNow)
        let declencheur = UNTimeIntervalNotificationTrigger(timeInterval: delai, repeats: false)
        do {
            try await centre.add(UNNotificationRequest(identifier: Self.prefixeRappelTele + cle, content: contenu, trigger: declencheur))
            rappelsTele.insert(cle)
            return true
        } catch {
            journal?.noter(.general, "Le rappel d'un passage TV n'a pas pu être programmé.", erreur: error)
            return nil
        }
    }

    /// EF-84 : une alerte d'essai dans 5 secondes, pour vérifier l'affichage.
    func envoyerEssai() async {
        if autorisation == .notDetermined { await demanderAutorisation() }
        let contenu = UNMutableNotificationContent()
        contenu.title = "Séance"
        contenu.body = "Les alertes fonctionnent : tu seras prévenu des nouveaux épisodes, des sorties et des passages à la TV."
        contenu.sound = .default
        let declencheur = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try? await centre.add(UNNotificationRequest(identifier: "seance.essai", content: contenu, trigger: declencheur))
    }

    private func requete(_ notification: NotificationPrevue) -> UNNotificationRequest {
        let contenu = UNMutableNotificationContent()
        contenu.title = notification.titre
        contenu.body = notification.corps
        contenu.sound = .default
        contenu.threadIdentifier = "seance"
        // Toucher l'alerte ouvre la fiche du titre, ou du premier titre d'un regroupement.
        if let reference = notification.reference {
            contenu.userInfo = ["lien": "seance://\(reference.type.rawValue)/\(reference.tmdbID)"]
            contenu.categoryIdentifier = Self.categorieTitre
        }
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = reglages.fuseau
        let composants = calendrier.dateComponents(in: reglages.fuseau, from: notification.date)
        let declencheur = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(year: composants.year, month: composants.month, day: composants.day,
                                         hour: composants.hour, minute: composants.minute),
            repeats: false
        )
        return UNNotificationRequest(identifier: Self.prefixe + notification.identifiant, content: contenu, trigger: declencheur)
    }

    /// iOS décide du moment exact ; au plus tôt dans 6 heures.
    private func programmerTacheFond() {
        let demande = BGAppRefreshTaskRequest(identifier: Self.tacheFond)
        demande.earliestBeginDate = Date.now.addingTimeInterval(6 * 3600)
        try? BGTaskScheduler.shared.submit(demande)
    }
}

/// Affiche les alertes même quand Séance est ouverte, et ouvre la fiche quand on les touche.
final class DelegueNotifications: NSObject, UNUserNotificationCenterDelegate {
    private let ouvrir: @MainActor @Sendable (URL) -> Void

    init(ouvrir: @escaping @MainActor @Sendable (URL) -> Void) {
        self.ouvrir = ouvrir
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let infos = response.notification.request.content.userInfo
        guard let texte = infos["lien"] as? String, let url = URL(string: texte) else { return }
        if response.actionIdentifier == EtatAlertes.actionSoiree {
            // Depuis l'alerte ou la montre, sans ouvrir l'app : le titre rejoint la soirée de ce soir.
            await Self.ajouterASoiree(url, titreDeSecours: infos["titre"] as? String)
            return
        }
        await ouvrir(url)
    }

    @MainActor
    private static func ajouterASoiree(_ url: URL, titreDeSecours: String?) {
        guard let reference = LienProfond.reference(url), let contexte = ConteneurApp.conteneur?.mainContext else { return }
        let suivi = try? ServiceSuivi(contexte: contexte).suivi(reference)
        guard let titre = suivi?.titre ?? titreDeSecours else { return }
        try? ServiceSoiree(contexte: contexte).retenir(reference, titre: titre, cheminAffiche: suivi?.cheminAffiche)
        PublicationWidgets.recharger()
    }
}
