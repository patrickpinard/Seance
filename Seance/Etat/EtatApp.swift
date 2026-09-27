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
    /// « Vu avec qui ? » (6.1) : la feuille qui inscrit un visionnage chez d'autres personnes de la famille.
    var avecQui: DemandeAvecQui?
    /// « Qui regarde ce soir ? » : les personnes cochées dans les idées du soir, proposées d'office dans « Vu avec qui ? ».
    var invitesDuSoir: [ProfilFamille] = []
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
    /// Préférences (7.0) : plus un onglet, mais le portrait en haut à gauche de chaque page, qui les ouvre en feuille.
    var preferencesOuvertes = false
    /// Sur le Mac (8.2.13) : chaque demande pousse les Préférences en page dans l'accueil.
    var preferencesEnPage = 0
    /// Sur l'iPad et le Mac (8.2.17), Préférences et Réglages s'ouvrent en pages dans la pile courante ; en feuilles
    /// sur l'iPhone seulement.
    static var enPages: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }
    var reglagesEnPage = 0
    /// Réglages en feuille, sur l'iPhone (7.0) : la roue dentée de chaque page.
    var reglagesOuverts = false
    /// Onglet à ouvrir, demandé depuis un autre écran : `.ceSoir`, `.streaming`, `.tele` et `.nas` ouvrent Regarder sur
    /// la bonne source (8.0).
    var ongletDemande: OngletRacine?
    /// Regarder (8.0) : la source choisie (Tout · Streaming · TV · NAS) et le jour de la rangée ; `nil` pour aujourd'hui.
    var sourceRegarder: SourceRegarder = .tout
    var jourRegarder: Date?
    /// Demandé par le widget « À venir » : Mes listes s'ouvre sur cet onglet.
    var listeDemandee: MesListesView.Onglet?
    let depot = DepotCles()
    let nas: EtatNAS
    /// À la maison ou sur le réseau mobile (8.1) : le lecteur choisit l'adresse du NAS en conséquence.
    let reseau = EtatReseau()
    /// Le second accès au NAS, facultatif : les vidéos personnelles (EF-157).
    let videosPerso: EtatVideosPerso
    let alertes = EtatAlertes()
    /// Badges « où regarder » des affiches.
    static let cacheTMDB = CacheTMDB(dossier: DossiersSeance.reponsesTMDB)
    let ou = EtatOu()
    /// Les identifiants des titres chez Netflix, Apple TV et Disney+, lus sur Wikidata (6.1) : de quoi ouvrir le titre
    /// lui-même plutôt que la recherche de la plateforme. En démonstration, rien ne part sur le réseau.
    static let identifiants: ReserveIdentifiants = {
        #if DEBUG
        if Demonstration.active { return ReserveIdentifiants(transport: nil, fichier: nil) }
        #endif
        return ReserveIdentifiants(transport: URLSession.shared, fichier: URL.cachesDirectory.appending(path: "identifiants-plateformes.json"))
    }()
    /// Images de fond et durées des titres, pour les grandes cartes.
    let decors = EtatDecors()
    /// Les documentaires : thèmes cochés et titres du moment (EF-151 à EF-156).
    let documentaires = EtatDocumentaires()
    /// Synchronisation entre appareils par un dossier d'iCloud Drive.
    let synchro = EtatSynchro()
    /// L'e-mail de la semaine, envoyé par le compte de messagerie de l'utilisateur.
    let lettre: EtatLettre
    /// Mac : Séance veille sur la maison (6.0).
    let centrale = EtatCentrale()
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
        lettre = EtatLettre(coffre: depot.coffre)
        lettre.journal = journal
        nas = EtatNAS(coffre: depot.coffre)
        videosPerso = EtatVideosPerso(coffre: depot.coffre)
        nas.journal = journal
        journal.noterPlantages()
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

    /// Ce que Séance est en train d'ouvrir au-dehors (6.3) : Netflix, Disney+, blue TV… Le temps d'y arriver,
    /// l'écran le dit, avec ce que l'app est en train de faire — retrouver la page exacte du titre demande une
    /// requête à Wikidata, qui prend parfois quelques secondes.
    struct Ouverture: Equatable, Identifiable {
        let id = UUID()
        let plateforme: String
        var etape: String
    }

    var ouverture: Ouverture?

    /// Un retour en arrière demandé au clavier (6.4, ⌘[ sur le Mac) : la pile ouverte le consomme.
    var retourDemande = 0

    /// Le titre n'est que sur une plateforme que tu n'as pas cochée (6.5) : la racine pose la question.
    struct PropositionAbonnement: Identifiable, Equatable {
        let id = UUID()
        let plateforme: String
        let identifiant: Int
        let titre: String
        let reference: ReferenceTitre
    }

    var abonnementPropose: PropositionAbonnement?

    /// Ce qui se lit dans Séance (8.0) — un film, un épisode ou un souvenir du NAS —, avec le moteur de VLC. La racine
    /// pose le lecteur par-dessus l'app plutôt qu'en feuille : « Continuer dans Séance » le passe en image dans
    /// l'image, et la vidéo continue pendant qu'on navigue.
    var lecture: LectureEnCours?
    /// La lecture continue dans l'image dans l'image : le lecteur plein écran s'efface.
    var lectureEnImage = false

    /// Un film ou un épisode du NAS, dans le lecteur de Séance.
    func lire(_ fichier: FichierNAS) {
        lectureEnImage = false
        lecture = LectureEnCours(video: VideoPerso(chemin: fichier.chemin, taille: fichier.tailleOctets),
                                 acces: nas.reglages, motDePasse: nas.motDePasse ?? "", fichier: fichier)
    }

    /// Montre le sablier, avec ce que l'app est en train de faire. Un garde-fou l'efface au bout de huit secondes :
    /// une app qui ne rend jamais la main ne doit pas laisser Séance bloquée sous un voile.
    func annoncerOuverture(_ plateforme: String, etape: String) {
        let annonce = Ouverture(plateforme: plateforme, etape: etape)
        ouverture = annonce
        Task {
            try? await Task.sleep(for: .seconds(8))
            if ouverture == annonce { ouverture = nil }
        }
    }

    /// Annonce l'ouverture, fait le travail, puis retire le sablier — même si le travail échoue.
    func pendantLOuverture<T>(de plateforme: String, etape: String, _ travail: () async -> T) async -> T {
        annoncerOuverture(plateforme, etape: etape)
        let resultat = await travail()
        ouverture = nil
        return resultat
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
    /// 8.1 : le guide TV et le NAS en même temps, et non l'un après l'autre — avec la RTS, le guide prend des dizaines
    /// de secondes, que le NAS n'attend plus. Le tout après le premier écran, pour qu'il s'affiche sans attendre.
    func demarrer(contexte: ModelContext) async {
        try? await Task.sleep(for: .milliseconds(500))
        _ = try? ServiceProgrammesTV.preparerChaines(contexte)
        // Sur le fil principal, comme le reste : le magasin n'est pas partagé entre fils, les deux s'entrelacent.
        let bibliotheque = Task { @MainActor in await nas.analyser(contexte: contexte, tmdb: tmdb, automatique: true) }
        // 8.2.11 : un changement de personne annule le démarrage — l'analyse du NAS aussi, qui tournait à part et
        // continuait d'écrire dans le magasin remplacé.
        await withTaskCancellationHandler {
            await actualiserTele(contexte: contexte)
            guard !Task.isCancelled else { return }
            // Après la TV : les passages des titres suivis entrent dans les alertes.
            await alertes.planifier(contexte: contexte, tmdb: tmdb)
            await bibliotheque.value
        } onCancel: {
            bibliotheque.cancel()
        }
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
        // À la maison, le NAS répond : ce que la TV a changé (ou son essai d'alerte) arrive sans ouvrir l'app.
        await synchro.synchroniser(etat: self, contexte: conteneur.mainContext, automatique: true)
        await lettre.envoyerSiDu(etat: self, contexte: conteneur.mainContext)
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

/// Une vidéo du NAS lue dans Séance (8.0) : de quoi l'ouvrir, et que faire si même VLC n'y arrive pas.
struct LectureEnCours: Identifiable {
    let id = UUID()
    let video: VideoPerso
    let acces: ReglagesNAS
    let motDePasse: String
    var surEchec: (String) -> Void = { _ in }
    /// Le film ou l'épisode du NAS (8.1) : marqué vu vers la fin, suivi de l'épisode d'après. `nil` pour un souvenir.
    var fichier: FichierNAS?
}
