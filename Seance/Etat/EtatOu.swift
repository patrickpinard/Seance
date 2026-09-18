import Foundation
import Observation
import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// Où regarder, en un coup d'œil sur les affiches : NAS, plateforme de tes abonnements, ou télé ce soir.
/// Le NAS, la télé et les abonnements viennent du magasin ; les plateformes d'un titre viennent de TMDB, quatre
/// appels à la fois, gardées douze heures sur disque pour ne pas relire tout l'accueil à chaque ouverture.
@MainActor
@Observable
final class EtatOu {
    enum Badge: Hashable {
        case nas
        case plateforme(nom: String, logo: String?)
        case tele(chaine: String)
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
        nas = Set(((try? contexte.fetch(FetchDescriptor<FichierNAS>(predicate: #Predicate { $0.tmdbID != nil }))) ?? []).compactMap(\.reference))
        abonnements = Set(((try? contexte.fetch(FetchDescriptor<Abonnement>(predicate: #Predicate { $0.actif }))) ?? []).map(\.providerID))
        let maintenant = Date.now
        // La soirée en cours se termine à 2 h du matin, comme « Regardable ce soir ».
        let finDeSoiree = Calendar.current.startOfDay(for: maintenant.addingTimeInterval(-2 * 3600)).addingTimeInterval(26 * 3600)
        let diffusions = (try? contexte.fetch(FetchDescriptor<Diffusion>(
            predicate: #Predicate { $0.fin > maintenant && $0.debut < finDeSoiree }, sortBy: [SortDescriptor(\.debut)]
        ))) ?? []
        let chaines = Dictionary(((try? contexte.fetch(FetchDescriptor<Chaine>())) ?? []).map { ($0.identifiantGuide, $0.nom) },
                                 uniquingKeysWith: { premier, _ in premier })
        var ceSoir: [ReferenceTitre: String] = [:]
        for diffusion in diffusions {
            guard let id = diffusion.tmdbID else { continue }
            let reference = ReferenceTitre(type: TypeTitre(rawValue: diffusion.typeBrut) ?? .film, tmdbID: id)
            if ceSoir[reference] == nil { ceSoir[reference] = chaines[diffusion.chaine] ?? diffusion.chaine }
        }
        tele = ceSoir
    }

    /// Le badge d'une affiche : le NAS d'abord, puis la première plateforme cochée, puis la télé de ce soir.
    func badge(_ reference: ReferenceTitre) -> Badge? {
        if nas.contains(reference) { return .nas }
        if let plateforme = entrees[Self.cle(reference)]?.plateformes.filter({ abonnements.contains($0.id) }).min(by: { $0.priorite < $1.priorite }) {
            return .plateforme(nom: plateforme.nom, logo: plateforme.logo)
        }
        if let chaine = tele[reference] { return .tele(chaine: chaine) }
        return nil
    }

    /// Demande les plateformes d'un titre affiché, s'il n'est pas déjà connu ; sans abonnement coché, rien à chercher.
    func demander(_ reference: ReferenceTitre, client: TMDBClient?) {
        guard let client, !abonnements.isEmpty, !nas.contains(reference), !demandes.contains(reference) else { return }
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
        switch etat.ou.badge(reference) {
        case .nas:
            pastille("externaldrive.fill").accessibilityLabel("Sur le NAS")
        case .plateforme(let nom, let logo):
            ImageDistante(url: ImageTMDB.url(logo, .logo), coins: 6)
                .frame(width: 24, height: 24)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 3)
                .accessibilityLabel("Sur \(nom)")
        case .tele(let chaine):
            pastille("tv.fill").accessibilityLabel("Ce soir sur \(chaine)")
        case nil:
            EmptyView()
        }
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
