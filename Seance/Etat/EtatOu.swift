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

    private struct Plateforme: Codable {
        let id: Int
        let nom: String
        let logo: String?
        let priorite: Int
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
    /// ouvrir la chaîne plus tôt montrerait autre chose. Sur le Mac, faute d'app blue TV, le lecteur web.
    func lienBlueTV(_ reference: ReferenceTitre, maintenant: Date = .now) -> URL? {
        guard BlueTV.actif, let passage = passages[reference],
              passage.debut <= maintenant.addingTimeInterval(15 * 60), passage.fin > maintenant else { return nil }
        #if targetEnvironment(macCatalyst)
        return LiensChaines.blueTV(chaine: passage.idGuide, app: false)
        #else
        return LiensChaines.blueTV(chaine: passage.idGuide, app: true)
        #endif
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
                    entrees[Self.cle(reference)] = Entree(lueLe: .now, plateformes: inclus.map {
                        Plateforme(id: $0.id, nom: $0.nom, logo: $0.cheminLogo, priorite: $0.priorite)
                    })
                }
                actifs -= 1
                demandes.remove(reference)
                if attente.isEmpty, actifs == 0 { enregistrer() } else { pomper(client) }
            }
        }
    }

    private func enregistrer() {
        guard let donnees = try? JSONEncoder().encode(entrees) else { return }
        try? donnees.write(to: Self.fichier, options: .atomic)
    }

    private static func cle(_ reference: ReferenceTitre) -> String {
        "\(reference.type.rawValue)-\(reference.tmdbID)"
    }
}

/// Le badge lui-même, en coin d'affiche.
struct BadgeOu: View {
    let reference: ReferenceTitre

    @Environment(EtatApp.self) private var etat

    var body: some View {
        let badges = etat.ou.badges(reference)
        HStack(spacing: 4) {
            ForEach(badges, id: \.self) { badge in
                switch badge {
                case .nas: pastille("externaldrive.fill")
                case .plateforme(_, _, let logo): BadgeOu.logo(logo)
                case .tele: pastille("tv.fill")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badges.map(BadgeOu.libelle).joined(separator: ", "))
        .accessibilityHidden(badges.isEmpty)
        // Dans une cellule qui assemble son libellé (une grille d'affiches), le titre s'annonce avant l'endroit où
        // regarder : « John Wick, sur ton NAS » et non l'inverse.
        .accessibilitySortPriority(-1)
    }

    static func libelle(_ badge: EtatOu.Badge) -> String {
        switch badge {
        case .nas: "Sur ton NAS"
        case .plateforme(_, let nom, _): nom
        case .tele(let chaine, let quand): "\(chaine), \(quand)"
        }
    }

    static func logo(_ chemin: String?) -> some View {
        ImageDistante(url: ImageTMDB.url(chemin, .logo), coins: 6)
            .frame(width: 24, height: 24)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 3)
    }

    private func pastille(_ symbole: String) -> some View {
        Image(systemName: symbole)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Theme.accentClair)
            .frame(width: 24, height: 24)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1))
    }
}

/// En tête de fiche : où regarder ce titre, d'un coup d'œil — les mêmes pastilles que sur les affiches, avec leur nom.
/// Le détail (location, achat, prochaines diffusions) reste dans le bloc « Où regarder », plus bas.
struct RangeeOu: View {
    let reference: ReferenceTitre

    @Environment(EtatApp.self) private var etat

    var body: some View {
        let badges = etat.ou.badges(reference)
        if !badges.isEmpty {
            Flux(espacement: 8) {
                ForEach(badges, id: \.self) { badge in
                    HStack(spacing: 6) {
                        switch badge {
                        case .nas: Image(systemName: "externaldrive.fill").foregroundStyle(Theme.accentClair)
                        case .plateforme(_, _, let logo): BadgeOu.logo(logo).frame(width: 20, height: 20)
                        case .tele: Image(systemName: "tv.fill").foregroundStyle(Theme.accentClair)
                        }
                        Text(BadgeOu.libelle(badge)).font(.caption.weight(.semibold)).lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 30)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.trait))
                }
            }
            .padding(.horizontal, 20)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Où regarder : " + badges.map(BadgeOu.libelle).joined(separator: ", "))
            .task(id: reference) { etat.ou.demander(reference, client: etat.tmdb) }
        }
    }
}
