import Foundation
import Observation
import SeanceDonnees
import SeanceKit
import SwiftData
#if targetEnvironment(macCatalyst)
import ServiceManagement
#endif

/// Le Mac, centrale de la maison (Séance 6.0). Séance n'a pas de serveur : l'e-mail de la semaine, la synchronisation et
/// la relecture du guide TV et du NAS n'avancent que lorsqu'une app est ouverte. Sur un Mac qui reste allumé, Séance
/// peut tenir ce rôle : ouverte à l'ouverture de session, elle passe tous les quarts d'heure — synchronise l'iCloud
/// Drive et le NAS (et fait ainsi le pont entre l'Apple TV et l'iPhone), relit le guide et la bibliothèque, recalcule les
/// alertes, et envoie l'e-mail à l'heure dite. Tant qu'elle veille, le Mac ne se met pas en veille de lui-même.
@MainActor
@Observable
final class EtatCentrale {
    static var disponible: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    private(set) var active: Bool
    private(set) var dernierPassage: Date?
    private(set) var enCours = false
    /// Ce que le dernier passage a fait, en une phrase.
    private(set) var bilan: String?
    private(set) var ouvertureDeSession = false
    private(set) var erreurOuverture: String?

    private static let cleActive = "centrale.active"
    private static let cleDernier = "centrale.dernierPassage"
    /// Un passage tous les quarts d'heure : assez pour que l'e-mail parte à l'heure et que la TV ne reste pas sans nouvelles.
    static let intervalle: TimeInterval = 15 * 60

    @ObservationIgnored private var veille: (any NSObjectProtocol)?
    @ObservationIgnored private var boucle: Task<Void, Never>?

    init() {
        active = Self.disponible && UserDefaults.standard.bool(forKey: Self.cleActive)
        dernierPassage = UserDefaults.standard.object(forKey: Self.cleDernier) as? Date
        lireOuvertureDeSession()
    }

    /// À l'ouverture de l'app, et à chaque changement du réglage.
    func demarrer(etat: EtatApp, conteneur: @escaping @MainActor () -> ModelContainer?) {
        boucle?.cancel()
        boucle = nil
        if let veille { ProcessInfo.processInfo.endActivity(veille) }
        veille = nil
        guard active else { return }
        #if DEBUG
        if Demonstration.coupeeDuMonde { return }
        #endif
        // Ni sieste de l'app, ni mise en veille du Mac par inactivité : c'est ce que faisait `caffeinate` à la main.
        veille = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                       reason: "Séance veille sur la maison : synchronisation, alertes, e-mail de la semaine")
        boucle = Task { [weak self] in
            while !Task.isCancelled {
                // Un changement de profil recrée l'état de l'app : l'ancienne centrale s'arrête d'elle-même.
                guard let self else { return }
                if let conteneur = conteneur() { await self.passer(etat: etat, contexte: conteneur.mainContext) }
                try? await Task.sleep(for: .seconds(Self.intervalle))
            }
        }
    }

    func regler(active nouvelle: Bool, etat: EtatApp, conteneur: @escaping @MainActor () -> ModelContainer?) {
        active = nouvelle && Self.disponible
        UserDefaults.standard.set(active, forKey: Self.cleActive)
        demarrer(etat: etat, conteneur: conteneur)
    }

    /// Un passage : dans l'ordre où les choses dépendent les unes des autres.
    func passer(etat: EtatApp, contexte: ModelContext) async {
        guard !enCours else { return }
        enCours = true
        defer { enCours = false }
        var faits: [String] = []
        await etat.synchro.synchroniser(etat: etat, contexte: contexte)
        if etat.synchro.derniereSynchro.map({ Date.now.timeIntervalSince($0) < 60 }) == true { faits.append("synchronisation") }
        await etat.actualiserTele(contexte: contexte)
        await etat.nas.analyser(contexte: contexte, tmdb: etat.tmdb, automatique: true)
        await etat.alertes.planifier(contexte: contexte, tmdb: etat.tmdb)
        faits.append("guide TV, NAS et alertes")
        // 8.11 : les vignettes des souvenirs, fabriquées ici et déposées sur le NAS pour l'iPhone, l'iPad et la TV.
        if etat.videosPerso.actif, let motDePasse = etat.videosPerso.motDePasse(films: etat.nas.reglages) {
            let deposees = await etat.videosPerso.vignettes.preparerSurLeNAS(etat.videosPerso.videos, acces: etat.videosPerso.reglages.acces,
                                                                              motDePasse: motDePasse)
            if deposees > 0 { faits.append("\(deposees) vignette\(deposees > 1 ? "s" : "") de souvenirs") }
        }
        let avant = etat.lettre.dernierEnvoi
        await etat.lettre.envoyerSiDu(etat: etat, contexte: contexte)
        if etat.lettre.dernierEnvoi != avant { faits.append("e-mail de la semaine envoyé") }
        dernierPassage = .now
        UserDefaults.standard.set(Date.now, forKey: Self.cleDernier)
        bilan = faits.joined(separator: ", ").prefix(1).uppercased() + faits.joined(separator: ", ").dropFirst()
    }

    // MARK: Ouverture à l'ouverture de session

    private func lireOuvertureDeSession() {
        #if targetEnvironment(macCatalyst)
        ouvertureDeSession = SMAppService.mainApp.status == .enabled
        #endif
    }

    func reglerOuvertureDeSession(_ voulue: Bool) {
        #if targetEnvironment(macCatalyst)
        do {
            if voulue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            erreurOuverture = nil
        } catch {
            erreurOuverture = "macOS a refusé : ajoute Séance à la main dans Réglages Système › Général › Ouverture."
        }
        lireOuvertureDeSession()
        #endif
    }
}
