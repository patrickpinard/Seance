import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI
import UserNotifications

/// État partagé par tous les écrans : le client TMDB, présent seulement si une clé est enregistrée.
@MainActor
@Observable
final class EtatApp {
    private(set) var tmdb: TMDBClient?
    /// Noms des genres TMDB, chargés une fois : ils servent aux filtres, aux phrases et aux statistiques.
    private(set) var nomsGenres: [Int: String] = [:]
    /// Genres TMDB par type, dans l'ordre alphabétique, pour les filtres d'Explorer.
    private(set) var genres: [TypeTitre: [Genre]] = [:]
    /// Fiche demandée par un lien profond ; l'accueil l'ouvre puis remet la demande à zéro.
    var ficheDemandee: ReferenceTitre?
    /// Demandé depuis une fiche acteur : Explorer s'ouvre filtré sur cette personne.
    var filtreExplorerDemande: PersonneFiltre?
    /// Onglet à ouvrir, demandé depuis un autre écran (Ce soir vers Explorer).
    var ongletDemande: OngletRacine?
    /// Demandé par le widget « À venir » : Mes listes s'ouvre sur cet onglet.
    var listeDemandee: MesListesView.Onglet?
    let depot = DepotCles()
    let nas: EtatNAS
    let alertes = EtatAlertes()
    let journal = Journal()
    /// Gardé ici : le centre de notifications ne retient son délégué que faiblement.
    private var delegueNotifications: DelegueNotifications?

    // Télévision (EF-45 à EF-51)
    private(set) var teleEnCours = false
    private(set) var rapportTele: ServiceProgrammesTV.Rapport?
    private(set) var erreurTele: String?
    private(set) var derniereLectureTele = UserDefaults.standard.object(forKey: CleReglage.derniereLectureTele) as? Date

    private enum CleReglage {
        static let derniereLectureTele = "tele.derniereLecture"
        static let chainesLues = "tele.chainesLues"
        static let versionGuide = "tele.version"
    }

    /// À augmenter quand les diffusions enregistrées gagnent des informations : le guide est alors relu
    /// sans attendre 12 heures. Version 2 : images des cartes.
    private static let versionGuide = 2

    init() {
        #if DEBUG
        // Développement : `SIMCTL_CHILD_SEANCE_CLE_TMDB=… xcrun simctl launch …` enregistre la clé
        // dans le trousseau du simulateur, sans qu'elle soit écrite dans le code ni dans le dépôt.
        if let cle = ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"], (try? depot.coffre.lire(.tmdb)) == nil {
            try? depot.coffre.enregistrer(cle, pour: .tmdb)
        }
        #endif
        nas = EtatNAS(coffre: depot.coffre)
        nas.journal = journal
        alertes.journal = journal
        let delegue = DelegueNotifications { [weak self] url in
            self?.ficheDemandee = LienProfond.reference(url)
        }
        UNUserNotificationCenter.current().delegate = delegue
        delegueNotifications = delegue
        tmdb = try? depot.client()
    }

    /// Les deux référentiels de genres, films et séries, en un seul dictionnaire.
    func chargerGenres() async {
        guard nomsGenres.isEmpty, let tmdb else { return }
        async let films = tmdb.genres(.film)
        async let series = tmdb.genres(.serie)
        let listeFilms = (try? await films) ?? []
        let listeSeries = (try? await series) ?? []
        let tous = listeFilms + listeSeries
        let ordre: (Genre, Genre) -> Bool = { $0.nom.localizedStandardCompare($1.nom) == .orderedAscending }
        genres = [.film: listeFilms.sorted(by: ordre), .serie: listeSeries.sorted(by: ordre)]
        nomsGenres = Dictionary(tous.map { ($0.id, $0.nom) }, uniquingKeysWith: { premier, _ in premier })
    }

    /// Au lancement : chaînes par défaut au premier démarrage, puis programmes TV s'ils datent.
    func demarrer(contexte: ModelContext) async {
        _ = try? ServiceProgrammesTV.preparerChaines(contexte)
        await actualiserTele(contexte: contexte)
        await nas.analyser(contexte: contexte, tmdb: tmdb, automatique: true)
        // Après la télé : les passages des titres suivis entrent dans les alertes.
        await alertes.planifier(contexte: contexte, tmdb: tmdb)
    }

    /// Retour dans l'app : programmes TV s'ils datent, puis alertes et « À venir » s'ils datent d'une heure.
    func revenirAuPremierPlan(contexte: ModelContext) async {
        await actualiserTele(contexte: contexte)
        await alertes.planifierSiAncien(contexte: contexte, tmdb: tmdb)
    }

    /// Réveil en arrière-plan (tâche « rafraîchissement ») : programmes TV puis alertes.
    func rafraichirEnFond(conteneur: ModelContainer) async {
        await actualiserTele(contexte: conteneur.mainContext)
        await alertes.planifier(contexte: conteneur.mainContext, tmdb: tmdb)
    }

    /// Relit le guide TV si la dernière lecture a plus de 12 h ou si les chaînes cochées ont changé ;
    /// `force` passe outre, pour le bouton des réglages.
    func actualiserTele(contexte: ModelContext, force: Bool = false) async {
        guard !teleEnCours, let service = service(contexte),
              let actives = try? ServiceProgrammesTV.chainesActives(contexte) else { return }
        let lues = UserDefaults.standard.stringArray(forKey: CleReglage.chainesLues)
        let versionAJour = UserDefaults.standard.integer(forKey: CleReglage.versionGuide) == Self.versionGuide
        guard force || !versionAJour || ServiceProgrammesTV.doitActualiser(
            derniereLecture: derniereLectureTele, chainesLues: lues, chainesActives: actives
        ) else { return }

        teleEnCours = true
        erreurTele = nil
        defer { teleEnCours = false }
        do {
            rapportTele = try await service.actualiser()
            let maintenant = Date.now
            derniereLectureTele = maintenant
            UserDefaults.standard.set(maintenant, forKey: CleReglage.derniereLectureTele)
            UserDefaults.standard.set(actives, forKey: CleReglage.chainesLues)
            UserDefaults.standard.set(Self.versionGuide, forKey: CleReglage.versionGuide)
        } catch is CancellationError {
            return
        } catch {
            erreurTele = "Le programme TV n'a pas pu être lu."
            journal.noter(.tele, "Le programme TV n'a pas pu être lu.", erreur: error,
                          conseil: Journal.conseil(error) ?? "Le guide XML TV Fr est peut-être indisponible : Séance réessaiera plus tard.")
        }
    }

    private func service(_ contexte: ModelContext) -> ServiceProgrammesTV? {
        guard let tmdb else { return nil }
        return ServiceProgrammesTV(contexte: contexte, guide: GuideTVClient(), rattachement: RattachementGuide(recherche: tmdb))
    }

    /// Teste la clé contre TMDB avant de l'enregistrer : une clé refusée ne remplace pas la précédente.
    func enregistrerCle(_ texte: String) async throws {
        let propre = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = TMDBClient(identifiants: .depuis(propre))
        _ = try await client.genres(.film)
        try depot.coffre.enregistrer(propre, pour: .tmdb)
        tmdb = client
    }

    func supprimerCle() throws {
        try depot.coffre.supprimer(.tmdb)
        tmdb = nil
    }
}
