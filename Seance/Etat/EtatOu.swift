import Foundation
import Observation
import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Où regarder, en un coup d'œil sur les affiches : NAS, plateforme de tes abonnements, ou TV ce soir.
/// Le NAS, la TV et les abonnements viennent du magasin ; les plateformes d'un titre viennent de TMDB, quatre
/// appels à la fois, gardées douze heures sur disque pour ne pas relire tout l'accueil à chaque ouverture.
@MainActor
@Observable
final class EtatOu {
    enum Badge: Hashable {
        case nas
        /// `id` : l'identifiant TMDB de la plateforme, pour ouvrir sa recherche sur le titre (`LiensPlateformes`).
        case plateforme(id: Int, nom: String, logo: String?)
        /// `quand` : « ce soir à 20:55 », « en ce moment », ou le jour et l'heure du prochain passage de la semaine.
        case tele(chaine: String, quand: String)
    }

    struct Plateforme: Codable, Identifiable, Hashable {
        let id: Int
        let nom: String
        let logo: String?
        let priorite: Int
    }

    /// Où s'abonner, pour les plateformes que Séance sait ouvrir. Rien de personnel dans ces adresses.
    static func pageAbonnement(_ id: Int) -> URL? {
        switch id {
        case 8, 1796: URL(string: "https://www.netflix.com/ch-fr/")
        case 350: URL(string: "https://tv.apple.com/ch/channel/tvs.sbd.4000")
        case 337: URL(string: "https://www.disneyplus.com/fr-ch")
        case 119: URL(string: "https://www.primevideo.com")
        case 2: URL(string: "https://tv.apple.com/ch")
        default: nil
        }
    }

    private struct Entree: Codable {
        let lueLe: Date
        let plateformes: [Plateforme]
    }

    private var entrees: [String: Entree] = [:]
    private var nas: Set<ReferenceTitre> = []
    private var tele: [ReferenceTitre: String] = [:]
    /// Le prochain passage de chaque titre dans le guide (sept jours) : chaîne, et quand.
    private var teleSemaine: [ReferenceTitre: (chaine: String, quand: String)] = [:]
    /// Le même passage, avec l'identifiant de la chaîne dans le guide et ses heures : de quoi l'ouvrir dans blue TV (6.1).
    private var passages: [ReferenceTitre: (idGuide: String, debut: Date, fin: Date)] = [:]
    private var abonnements: Set<Int> = []

    @ObservationIgnored private var demandes: Set<ReferenceTitre> = []
    @ObservationIgnored private var attente: [ReferenceTitre] = []
    @ObservationIgnored private var actifs = 0
    /// Les réponses de TMDB pas encore publiées (8.10, bilan de l'Apple TV) : chaque réponse publiée seule redessinait
    /// toutes les cartes affichées — 60 à 100 fois à l'ouverture de l'accueil. Elles partent par lots, toutes les 0,4 s.
    @ObservationIgnored private var tampon: [String: Entree] = [:]
    @ObservationIgnored private var publicationPrevue = false
    private static let validite: TimeInterval = 12 * 3600
    private static let fichier = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "ou-regarder.json")

    init() {
        if let donnees = try? Data(contentsOf: Self.fichier), let lues = try? JSONDecoder().decode([String: Entree].self, from: donnees) {
            let limite = Date.now.addingTimeInterval(-Self.validite)
            entrees = lues.filter { $0.value.lueLe > limite }
        }
    }

    /// Ce que le magasin sait sans réseau : fichiers du NAS rattachés, diffusions de ce soir, plateformes cochées.
    func actualiserLocal(contexte: ModelContext) {
        // Seuls l'identifiant et le type servent ici : les charger seuls évite de matérialiser toute la vidéothèque.
        var fichiers = FetchDescriptor<FichierNAS>(predicate: #Predicate { $0.tmdbID != nil })
        fichiers.propertiesToFetch = [\.tmdbID, \.typeBrut]
        nas = Set(((try? contexte.fetch(fichiers)) ?? []).compactMap(\.reference))
        abonnements = Set(((try? contexte.fetch(FetchDescriptor<Abonnement>(predicate: #Predicate { $0.actif }))) ?? []).map(\.providerID))
        let maintenant = Date.now
        // La soirée en cours se termine à 2 h du matin, comme « Regardable ce soir ».
        let finDeSoiree = Calendar.current.startOfDay(for: maintenant.addingTimeInterval(-2 * 3600)).addingTimeInterval(26 * 3600)
        let chaines = Dictionary(((try? contexte.fetch(FetchDescriptor<Chaine>())) ?? []).map { ($0.identifiantGuide, $0.nom) },
                                 uniquingKeysWith: { premier, _ in premier })
        // Un seul passage sur le guide : la semaine entière — un film d'Explorer › TV qui passe jeudi doit le dire —,
        // dont on tire au passage ce qui tient dans la soirée en cours.
        let aVenir = (try? contexte.fetch(FetchDescriptor<Diffusion>(predicate: #Predicate { $0.fin > maintenant }, sortBy: [SortDescriptor(\.debut)]))) ?? []
        var ceSoir: [ReferenceTitre: String] = [:]
        for diffusion in aVenir where diffusion.debut < finDeSoiree {
            guard let id = diffusion.tmdbID else { continue }
            let reference = ReferenceTitre(type: TypeTitre(rawValue: diffusion.typeBrut) ?? .film, tmdbID: id)
            if ceSoir[reference] == nil { ceSoir[reference] = chaines[diffusion.chaine] ?? ChaineGuide.nom(diffusion.chaine) ?? diffusion.chaine }
        }
        tele = ceSoir
        var semaine: [ReferenceTitre: (chaine: String, quand: String)] = [:]
        var prochains: [ReferenceTitre: (idGuide: String, debut: Date, fin: Date)] = [:]
        for diffusion in aVenir {
            guard let id = diffusion.tmdbID else { continue }
            let reference = ReferenceTitre(type: TypeTitre(rawValue: diffusion.typeBrut) ?? .film, tmdbID: id)
            guard semaine[reference] == nil else { continue }
            let heure = diffusion.debut.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_CH")))
            let quand = diffusion.debut <= maintenant ? "en ce moment"
                : ceSoir[reference] != nil ? "ce soir à \(heure)"
                : diffusion.debut.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "fr_CH"))) + " à \(heure)"
            semaine[reference] = (chaines[diffusion.chaine] ?? ChaineGuide.nom(diffusion.chaine) ?? diffusion.chaine, quand)
            prochains[reference] = (diffusion.chaine, diffusion.debut, diffusion.fin)
        }
        teleSemaine = semaine
        passages = prochains
    }

    /// Tous les endroits où regarder ce titre, dans l'ordre où on y pense : le NAS, tes plateformes (deux au plus),
    /// la TV. Une affiche d'Explorer › TV qui est aussi sur Netflix porte les deux : on ne la croit plus « de streaming ».
    /// Les plateformes qui ont le titre mais que tu n'as pas cochées dans les réglages (6.5). Séance ne les met pas
    /// en avant — seuls tes abonnements comptent —, mais elle peut dire « il est aussi sur Apple TV+ » plutôt que de
    /// laisser croire qu'il est introuvable.
    func horsAbonnement(_ reference: ReferenceTitre) -> [Plateforme] {
        (entrees[Self.cle(reference)]?.plateformes ?? [])
            .filter { !abonnements.contains($0.id) }
            .sorted { $0.priorite < $1.priorite }
    }

    func badges(_ reference: ReferenceTitre) -> [Badge] {
        var resultat: [Badge] = []
        if nas.contains(reference) { resultat.append(.nas) }
        // Celles dont le lien s'ouvre vraiment passent devant (6.0) ; à égalité, l'ordre de TMDB.
        let plateformes = (entrees[Self.cle(reference)]?.plateformes ?? []).filter { abonnements.contains($0.id) }
            .sorted { (PlateformesApprises.fiable($0.id) ? 0 : 1, $0.priorite) < (PlateformesApprises.fiable($1.id) ? 0 : 1, $1.priorite) }
        resultat += plateformes.prefix(2).map { .plateforme(id: $0.id, nom: $0.nom, logo: $0.logo) }
        if let passage = teleSemaine[reference] { resultat.append(.tele(chaine: passage.chaine, quand: passage.quand)) }
        return resultat
    }

    /// Vrai quand les plateformes du titre ont été lues : « dans aucun de tes abonnements » peut alors se dire.
    func plateformesConnues(_ reference: ReferenceTitre) -> Bool {
        entrees[Self.cle(reference)] != nil
    }

    var aDesAbonnements: Bool { !abonnements.isEmpty }

    /// Au moins une plateforme cochée sait ouvrir un titre précis (Netflix, Apple TV, Disney+) : les identifiants de
    /// Wikidata valent alors la peine d'être demandés (6.1).
    var aUnePlateformeDirecte: Bool { !abonnements.isDisjoint(with: LiensPlateformes.avecLienDirect) }

    /// La chaîne à ouvrir dans blue TV (6.1) : seulement quand le passage a commencé ou commence dans le quart d'heure —
    /// ouvrir la chaîne plus tôt montrerait autre chose. Renvoie l'identifiant de la chaîne dans le guide ; c'est
    /// `LancementBlueTV` qui en fait une adresse, après avoir demandé ce qui passe (6.3).
    func chaineBlueTV(_ reference: ReferenceTitre, maintenant: Date = .now) -> String? {
        guard BlueTV.actif, let passage = passages[reference],
              passage.debut <= maintenant.addingTimeInterval(15 * 60), passage.fin > maintenant,
              LiensChaines.numero(chaine: passage.idGuide) != nil else { return nil }
        return passage.idGuide
    }

    /// Le badge d'une affiche : le NAS d'abord, puis la première plateforme cochée, puis la TV de ce soir.
    func badge(_ reference: ReferenceTitre) -> Badge? {
        if nas.contains(reference) { return .nas }
        if let plateforme = entrees[Self.cle(reference)]?.plateformes.filter({ abonnements.contains($0.id) }).min(by: { $0.priorite < $1.priorite }) {
            return .plateforme(id: plateforme.id, nom: plateforme.nom, logo: plateforme.logo)
        }
        if let chaine = tele[reference] { return .tele(chaine: chaine, quand: teleSemaine[reference]?.quand ?? "ce soir") }
        return nil
    }

    /// Demande les plateformes d'un titre affiché, s'il n'est pas déjà connu ; sans abonnement coché, rien à chercher.
    func demander(_ reference: ReferenceTitre, client: TMDBClient?) {
        guard let client, !abonnements.isEmpty, !demandes.contains(reference) else { return }
        if let entree = entrees[Self.cle(reference)], entree.lueLe > Date.now.addingTimeInterval(-Self.validite) { return }
        demandes.insert(reference)
        attente.append(reference)
        pomper(client)
    }

    private func pomper(_ client: TMDBClient) {
        while actifs < 4, !attente.isEmpty {
            let reference = attente.removeFirst()
            actifs += 1
            Task {
                // Une erreur réseau ne s'enregistre pas : le titre sera redemandé à sa prochaine apparition.
                if let reponse = try? await client.fournisseurs(reference.type, id: reference.tmdbID) {
                    let offres = reponse.offres()
                    let inclus = (offres?.abonnement ?? []) + (offres?.gratuit ?? []) + (offres?.avecPublicite ?? [])
                    tampon[Self.cle(reference)] = Entree(lueLe: .now, plateformes: inclus.map {
                        Plateforme(id: $0.id, nom: $0.nom, logo: $0.cheminLogo, priorite: $0.priorite)
                    })
                }
                actifs -= 1
                demandes.remove(reference)
                if attente.isEmpty, actifs == 0 {
                    publier()
                    enregistrer()
                } else {
                    prevoirPublication()
                    pomper(client)
                }
            }
        }
    }

    private func prevoirPublication() {
        guard !publicationPrevue else { return }
        publicationPrevue = true
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            publier()
        }
    }

    /// Un seul changement observé pour tout le lot.
    private func publier() {
        publicationPrevue = false
        guard !tampon.isEmpty else { return }
        entrees.merge(tampon) { _, nouvelle in nouvelle }
        tampon = [:]
    }

    private func enregistrer() {
        guard let donnees = try? JSONEncoder().encode(entrees) else { return }
        try? donnees.write(to: Self.fichier, options: .atomic)
    }

    private static func cle(_ reference: ReferenceTitre) -> String {
        "\(reference.type.rawValue)-\(reference.tmdbID)"
    }
}

/// Ce que Séance a appris en ouvrant les plateformes : TMDB ne donne pas de lien, Séance ouvre leur recherche, et toutes ne
/// s'y prêtent pas sur tous les appareils. Par plateforme : combien de fois le lien s'est ouvert, combien de fois non.
enum PlateformesApprises {
    private static let cle = "plateformes.ouvertures"

    static func noter(_ id: Int, ouverte: Bool) {
        var comptes = UserDefaults.standard.dictionary(forKey: cle) as? [String: [Int]] ?? [:]
        var compte = comptes[String(id)] ?? [0, 0]
        compte[ouverte ? 0 : 1] += 1
        comptes[String(id)] = compte
        UserDefaults.standard.set(comptes, forKey: cle)
    }

    /// Une plateforme dont le lien n'a jamais abouti et a déjà échoué deux fois : « Regarder maintenant » en choisit une autre.
    static func fiable(_ id: Int) -> Bool {
        let compte = (UserDefaults.standard.dictionary(forKey: cle) as? [String: [Int]])?[String(id)] ?? [0, 0]
        return compte[0] > 0 || compte[1] < 2
    }
}

/// blue TV (6.1) : une chaîne en direct s'ouvre dans l'app blue TV de Swisscom — activé d'office, la maison la reçoit.
enum BlueTV {
    static let cle = "tele.blueTV"

    static var actif: Bool {
        UserDefaults.standard.object(forKey: cle) as? Bool ?? true
    }
}
