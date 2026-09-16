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

    init() {
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

    /// EF-84 : une alerte d'essai dans 5 secondes, pour vérifier l'affichage.
    func envoyerEssai() async {
        if autorisation == .notDetermined { await demanderAutorisation() }
        let contenu = UNMutableNotificationContent()
        contenu.title = "Séance"
        contenu.body = "Les alertes fonctionnent : tu seras prévenu des nouveaux épisodes, des sorties et des passages à la télé."
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
        guard let texte = response.notification.request.content.userInfo["lien"] as? String,
              let url = URL(string: texte) else { return }
        await ouvrir(url)
    }
}
