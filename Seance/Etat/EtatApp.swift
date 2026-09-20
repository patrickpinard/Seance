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
    /// Facultatif : sans clé, « Idées pour ce soir » classe les titres sur l'appareil (EF-27).
    private(set) var claude: ClientClaude?
    /// « Prévoir pour une soirée… » et « Ajouter à une liste… », demandés depuis une fiche, un clic droit ou
    /// Mes listes : la feuille s'ouvre au-dessus de l'écran en cours.
    var titreADater: TitreChoisi?
    var titrePourListe: TitreChoisi?
    /// ⌘F ou une demande d'un autre écran : Explorer s'ouvre, le champ de recherche actif.
    var rechercheDemandee = false
    /// Date d'expiration de l'installation (compte Apple gratuit : 7 jours), lue dans le profil de l'app.
    let expirationInstallation = ProfilInstallation.dateExpirationDeLApp()
    /// Noms des genres : ceux livrés avec l'app, remplacés par ceux de TMDB une fois chargés. Ils servent aux
    /// filtres, aux phrases et aux statistiques, qui n'affichent ainsi jamais « Genre 28 ».
    private(set) var nomsGenres: [Int: String] = GenresParDefaut.noms
    /// Genres par type, dans l'ordre alphabétique, pour les filtres d'Explorer.
    private(set) var genres: [TypeTitre: [Genre]] = [.film: EtatApp.alphabetique(GenresParDefaut.films),
                                                     .serie: EtatApp.alphabetique(GenresParDefaut.series)]
    private var genresTMDBCharges = false
    /// Message bref après une action rapide sur une affiche (« Ajouté à À voir »), effacé tout seul.
    private(set) var confirmation: Confirmation?

    /// Fiche demandée par un lien profond ; l'accueil l'ouvre puis remet la demande à zéro.
    var ficheDemandee: ReferenceTitre?
    /// Demandé depuis une fiche acteur : Explorer s'ouvre filtré sur cette personne.
    var filtreExplorerDemande: PersonneFiltre?
    /// `seance://tele` : l'accueil ouvre le programme TV puis remet la demande à zéro.
    var programmeTeleDemande = false
    /// Onglet à ouvrir, demandé depuis un autre écran (Ce soir vers Explorer).
    var ongletDemande: OngletRacine?
    /// Demandé par le widget « À venir » : Mes listes s'ouvre sur cet onglet.
    var listeDemandee: MesListesView.Onglet?
    let depot = DepotCles()
    let nas: EtatNAS
    /// Le second accès au NAS, facultatif : les vidéos personnelles (EF-157).
    let videosPerso: EtatVideosPerso
    let alertes = EtatAlertes()
    /// Badges « où regarder » des affiches.
    static let cacheTMDB = CacheTMDB(dossier: DossiersSeance.reponsesTMDB)
    let ou = EtatOu()
    /// Images de fond et durées des titres, pour les grandes cartes.
    let decors = EtatDecors()
    /// Synchronisation entre appareils par un dossier d'iCloud Drive.
    let synchro = EtatSynchro()
    /// Une sauvegarde « .seance » reçue par AirDrop ou ouverte depuis Fichiers : l'import se confirme.
    var sauvegardeRecue: URL?
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
        videosPerso = EtatVideosPerso(coffre: depot.coffre)
        nas.journal = journal
        alertes.journal = journal
        let delegue = DelegueNotifications { [weak self] url in
            // Le rappel d'une soirée prévue ouvre « Ce soir » ; les autres alertes, la fiche du titre.
            if LienProfond.onglet(url) == .ceSoir {
                self?.ongletDemande = .ceSoir
            } else {
                self?.ficheDemandee = LienProfond.reference(url)
            }
        }
        UNUserNotificationCenter.current().delegate = delegue
        delegueNotifications = delegue
        // Les réponses de TMDB passent par un cache sur disque : plus rapide, et l'app reste utilisable sans réseau.
        Self.cacheTMDB.purger()
        tmdb = try? depot.client(transport: Self.cacheTMDB)
        #if DEBUG
        // Tests d'interface : un TMDB de théâtre, qui répond avec des réponses enregistrées (voir FauxTMDB).
        if let dossier = FauxTMDB.dossierDemande {
            tmdb = TMDBClient(identifiants: .cleAPI("demonstration"), transport: FauxTMDB(dossier: dossier), tentativesMax: 1)
        }
        #endif
        claude = try? depot.clientClaude()
    }

    /// Les deux référentiels de genres, films et séries, en un seul dictionnaire.
    func chargerGenres() async {
        guard !genresTMDBCharges, let tmdb else { return }
        async let films = tmdb.genres(.film)
        async let series = tmdb.genres(.serie)
        let listeFilms = (try? await films) ?? []
        let listeSeries = (try? await series) ?? []
        // Sans réponse, les noms livrés avec l'app restent, et TMDB sera réinterrogé au prochain appel.
        guard !listeFilms.isEmpty || !listeSeries.isEmpty else { return }
        genresTMDBCharges = true
        genres = [.film: Self.alphabetique(GenresParDefaut.fusionner(listeFilms, defaut: GenresParDefaut.films)),
                  .serie: Self.alphabetique(GenresParDefaut.fusionner(listeSeries, defaut: GenresParDefaut.series))]
        nomsGenres = GenresParDefaut.noms.merging((listeFilms + listeSeries).map { ($0.id, $0.nom) }) { _, tmdb in tmdb }
    }

    private static func alphabetique(_ genres: [Genre]) -> [Genre] {
        genres.sorted { $0.nom.localizedStandardCompare($1.nom) == .orderedAscending }
    }

    struct Confirmation: Equatable, Identifiable {
        let id = UUID()
        let texte: String
        let symbole: String
        /// Présent pour une action qu'on peut regretter : le message propose alors « Annuler ».
        let annuler: (@MainActor () -> Void)?
        /// « Annuler » d'ordinaire ; « Encore un » quand le bouton propose une suite plutôt qu'un retour en arrière.
        var libelleAction = "Annuler"

        static func == (a: Confirmation, b: Confirmation) -> Bool { a.id == b.id }
    }

    /// Affiche la confirmation deux secondes, ou cinq quand elle propose d'annuler.
    func confirmer(_ texte: String, symbole: String, libelleAction: String = "Annuler", annuler: (@MainActor () -> Void)? = nil) {
        let message = Confirmation(texte: texte, symbole: symbole, annuler: annuler, libelleAction: libelleAction)
        confirmation = message
        Task {
            try? await Task.sleep(for: .seconds(annuler == nil ? 2 : 5))
            if confirmation == message { confirmation = nil }
        }
    }

    /// Annule l'action du message affiché, puis le retire.
    func annulerDerniereAction() {
        guard let message = confirmation, let annuler = message.annuler else { return }
        annuler()
        // Une suite (« Encore un ») n'annule rien : le message s'efface simplement.
        guard message.libelleAction == "Annuler" else { confirmation = nil; return }
        let annule = Confirmation(texte: "Annulé", symbole: "arrow.uturn.backward", annuler: nil)
        confirmation = annule
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if confirmation == annule { confirmation = nil }
        }
    }

    /// La clé Claude n'est pas testée contre l'API : un appel d'essai coûterait une vraie demande.
    /// Seule sa forme est vérifiée.
    func enregistrerCleClaude(_ cle: String) throws {
        let propre = cle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard propre.hasPrefix("sk-ant-"), propre.count > 20 else { throw ErreurCle.formatInattendu }
        try depot.coffre.enregistrer(propre, pour: .claude)
        claude = ClientClaude(cle: propre)
    }

    func supprimerCleClaude() throws {
        try depot.coffre.supprimer(.claude)
        claude = nil
    }

    enum ErreurCle: Error, LocalizedError {
        case formatInattendu

        var errorDescription: String? {
            "Une clé Claude commence par « sk-ant- »."
        }
    }

    /// Au lancement : chaînes par défaut au premier démarrage, puis programmes TV s'ils datent.
    func demarrer(contexte: ModelContext) async {
        _ = try? ServiceProgrammesTV.preparerChaines(contexte)
        await actualiserTele(contexte: contexte)
        await nas.analyser(contexte: contexte, tmdb: tmdb, automatique: true)
        // Après la TV : les passages des titres suivis entrent dans les alertes.
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
        #if DEBUG
        // En démonstration, le guide est fictif : le vrai le remplacerait, et les captures changeraient chaque jour.
        if Demonstration.active { return }
        #endif
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
        // Le test de la clé va droit au réseau : une réponse gardée ne prouverait rien.
        _ = try await TMDBClient(identifiants: .depuis(propre)).genres(.film)
        try depot.coffre.enregistrer(propre, pour: .tmdb)
        tmdb = TMDBClient(identifiants: .depuis(propre), transport: Self.cacheTMDB)
    }

    func supprimerCle() throws {
        try depot.coffre.supprimer(.tmdb)
        tmdb = nil
    }
}
