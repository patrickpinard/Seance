import Foundation
import Observation
import SeanceKit

/// Les documentaires (EF-151 à EF-156), troisième catégorie à côté des films et des séries. TMDB ne les range pas
/// par sous-genre : chaque thème est un jeu de mots-clés, cherchés une fois puis gardés sur l'appareil.
///
/// Rien ici ne touche aux listes ni aux statistiques : un documentaire se regarde comme un film, mais il a ses
/// propres suggestions (EF-156) — il ne vient pas se mêler aux idées du soir.
@MainActor
@Observable
final class EtatDocumentaires {
    private static let cleThemes = "documentaires.themes"
    private static let cleMotsCles = "documentaires.motsCles"

    /// Les thèmes cochés. Aucun : tous les documentaires, sans resserrement.
    private(set) var themes: Set<ThemeDocumentaire>
    private(set) var films: [TitreResume] = []
    private(set) var series: [TitreResume] = []
    private(set) var enCours = false
    private(set) var erreur: String?

    /// Mots-clés résolus, par thème : `{"sport": [6075, 1234]}`.
    @ObservationIgnored private var motsCles: [String: [Int]]
    @ObservationIgnored private var chargeAvec: Set<ThemeDocumentaire>?

    init() {
        let defauts = UserDefaults.standard
        let bruts = (defauts.array(forKey: Self.cleThemes) as? [String]) ?? []
        themes = Set(bruts.compactMap(ThemeDocumentaire.init(rawValue:)))
        motsCles = (defauts.dictionary(forKey: Self.cleMotsCles) as? [String: [Int]]) ?? [:]
    }

    func basculer(_ theme: ThemeDocumentaire) {
        if themes.contains(theme) { themes.remove(theme) } else { themes.insert(theme) }
        UserDefaults.standard.set(themes.map(\.rawValue), forKey: Self.cleThemes)
        chargeAvec = nil
    }

    var resume: String {
        themes.isEmpty ? "Tous les thèmes" : themes.map(\.libelle).sorted().joined(separator: " · ")
    }

    /// Charge ce qu'il faut montrer. Ne recommence pas tant que les thèmes n'ont pas changé.
    func charger(client: TMDBClient?, plateformes: [Int]?) async {
        guard let client, !enCours, chargeAvec != themes else { return }
        enCours = true
        erreur = nil
        defer { enCours = false }
        let ids = await identifiants(des: themes, client: client)
        var criteresFilms = CriteresDecouverte.documentaires(.film, motsCles: ids)
        var criteresSeries = CriteresDecouverte.documentaires(.serie, motsCles: ids)
        if let plateformes, !plateformes.isEmpty {
            criteresFilms.fournisseurs = plateformes
            criteresFilms.monetisations = [.abonnement, .gratuit, .avecPublicite]
            criteresSeries.fournisseurs = plateformes
            criteresSeries.monetisations = [.abonnement, .gratuit, .avecPublicite]
        }
        async let demandeFilms = client.decouvrirFilms(criteresFilms)
        async let demandeSeries = client.decouvrirSeries(criteresSeries)
        do {
            films = try await demandeFilms.resultats.map(\.titreResume)
            series = try await demandeSeries.resultats.map(\.titreResume)
            chargeAvec = themes
        } catch is CancellationError {
            return
        } catch {
            erreur = Journal.conseil(error) ?? "Les documentaires n'ont pas pu être lus : réessaie dans un moment."
        }
    }

    /// Les mots-clés TMDB des thèmes choisis, cherchés une fois puis gardés. Un terme introuvable est simplement
    /// laissé de côté : mieux vaut un thème un peu large qu'un écran vide.
    private func identifiants(des themes: Set<ThemeDocumentaire>, client: TMDBClient) async -> [Int] {
        var resultat: [Int] = []
        var aEnregistrer = false
        for theme in themes.sorted(by: { $0.rawValue < $1.rawValue }) {
            if let connus = motsCles[theme.rawValue] {
                resultat += connus
                continue
            }
            var trouves: [Int] = []
            for terme in theme.termes {
                guard let page = try? await client.motsCles(terme) else { continue }
                // Le mot-clé qui porte exactement ce nom, sinon le premier proposé.
                if let exact = page.resultats.first(where: { $0.nom.caseInsensitiveCompare(terme) == .orderedSame }) {
                    trouves.append(exact.id)
                } else if let premier = page.resultats.first {
                    trouves.append(premier.id)
                }
            }
            motsCles[theme.rawValue] = trouves
            aEnregistrer = true
            resultat += trouves
        }
        if aEnregistrer { UserDefaults.standard.set(motsCles, forKey: Self.cleMotsCles) }
        return resultat
    }
}
