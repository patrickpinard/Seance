import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// État partagé par tous les écrans : le client TMDB, présent seulement si une clé est enregistrée.
@MainActor
@Observable
final class EtatApp {
    private(set) var tmdb: TMDBClient?
    /// Absent tant qu'aucune clé Claude n'est enregistrée : « Ce soir » classe alors en local (EF-27).
    private(set) var claude: ClientClaude?
    /// Noms des genres TMDB, chargés une fois : ils servent aux phrases et à l'invite de Claude.
    private(set) var nomsGenres: [Int: String] = [:]
    /// Fiche demandée par un lien profond ; l'accueil l'ouvre puis remet la demande à zéro.
    var ficheDemandee: ReferenceTitre?
    let depot = DepotCles()

    // Télévision (EF-45 à EF-51)
    private(set) var teleEnCours = false
    private(set) var rapportTele: ServiceProgrammesTV.Rapport?
    private(set) var erreurTele: String?
    private(set) var derniereLectureTele = UserDefaults.standard.object(forKey: CleReglage.derniereLectureTele) as? Date

    private enum CleReglage {
        static let derniereLectureTele = "tele.derniereLecture"
        static let chainesLues = "tele.chainesLues"
    }

    init() {
        #if DEBUG
        // Développement : `SIMCTL_CHILD_SEANCE_CLE_TMDB=… xcrun simctl launch …` enregistre la clé
        // dans le trousseau du simulateur, sans qu'elle soit écrite dans le code ni dans le dépôt.
        if let cle = ProcessInfo.processInfo.environment["SEANCE_CLE_TMDB"], (try? depot.coffre.lire(.tmdb)) == nil {
            try? depot.coffre.enregistrer(cle, pour: .tmdb)
        }
        #endif
        tmdb = try? depot.client()
        claude = try? depot.clientClaude()
    }

    /// Les deux référentiels de genres, films et séries, en un seul dictionnaire.
    func chargerGenres() async {
        guard nomsGenres.isEmpty, let tmdb else { return }
        async let films = tmdb.genres(.film)
        async let series = tmdb.genres(.serie)
        let tous = ((try? await films) ?? []) + ((try? await series) ?? [])
        nomsGenres = Dictionary(tous.map { ($0.id, $0.nom) }, uniquingKeysWith: { premier, _ in premier })
    }

    /// Au lancement : chaînes par défaut au premier démarrage, puis programmes TV s'ils datent.
    func demarrer(contexte: ModelContext) async {
        _ = try? ServiceProgrammesTV.preparerChaines(contexte)
        await actualiserTele(contexte: contexte)
    }

    /// Relit le guide TV si la dernière lecture a plus de 12 h ou si les chaînes cochées ont changé ;
    /// `force` passe outre, pour le bouton des réglages.
    func actualiserTele(contexte: ModelContext, force: Bool = false) async {
        guard !teleEnCours, let service = service(contexte),
              let actives = try? ServiceProgrammesTV.chainesActives(contexte) else { return }
        let lues = UserDefaults.standard.stringArray(forKey: CleReglage.chainesLues)
        guard force || ServiceProgrammesTV.doitActualiser(
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
        } catch is CancellationError {
            return
        } catch {
            erreurTele = "Lecture du guide TV impossible : \(error.localizedDescription)"
        }
    }

    private func service(_ contexte: ModelContext) -> ServiceProgrammesTV? {
        guard let tmdb else { return nil }
        return ServiceProgrammesTV(contexte: contexte, guide: GuideTVClient(), rattachement: RattachementGuide(recherche: tmdb))
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
