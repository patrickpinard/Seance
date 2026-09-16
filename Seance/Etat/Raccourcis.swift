import AppIntents
import SeanceDonnees
import SeanceKit
import SwiftData

// Siri et l'app Raccourcis : « Dis Siri, qu'est-ce que je regarde ce soir avec Séance ? » et
// « Dis Siri, ajoute Reacher à ma soirée dans Séance ». Apple exige le nom de l'app dans la phrase.

/// Ta soirée prévue, sinon le prochain épisode d'une série, sinon ta liste à voir.
struct QuoiRegarderIntent: AppIntent {
    static let title: LocalizedStringResource = "Qu'est-ce que je regarde ce soir ?"
    static let description = IntentDescription("Dit ce que tu as prévu ce soir, ou te propose le prochain épisode d'une série et ta liste à voir.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let conteneur = ConteneurApp.conteneur else {
            return .result(dialog: "Séance n'arrive pas à lire tes listes. Ouvre l'app pour vérifier.")
        }
        let instantane = EntrepotSeance.dossierPartage.flatMap { InstantaneWidgets.lire(dossier: $0) }
        let phrase = try ServiceSoiree(contexte: conteneur.mainContext).phrase(instantane)
        return .result(dialog: IntentDialog(stringLiteral: phrase))
    }
}

/// Ajoute un film ou une série à « Ma soirée ».
struct AjouterASoireeIntent: AppIntent {
    static let title: LocalizedStringResource = "Ajouter à ma soirée"
    static let description = IntentDescription("Garde un film ou une série pour ce soir, en haut de l'onglet Ce soir.")

    @Parameter(title: "Film ou série", requestValueDialog: "Quel film ou quelle série ?")
    var titre: TitreEntite

    static var parameterSummary: some ParameterSummary {
        Summary("Ajouter \(\.$titre) à ma soirée")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let conteneur = ConteneurApp.conteneur else {
            return .result(dialog: "Séance n'arrive pas à lire tes listes. Ouvre l'app pour vérifier.")
        }
        let service = ServiceSoiree(contexte: conteneur.mainContext)
        if try service.estRetenu(titre.reference) {
            return .result(dialog: "« \(titre.nom) » est déjà dans ta soirée.")
        }
        try service.retenir(titre.reference, titre: titre.nom, cheminAffiche: titre.cheminAffiche)
        PublicationWidgets.recharger()
        return .result(dialog: "C'est noté : « \(titre.nom) » est dans ta soirée.")
    }
}

/// Un film ou une série, trouvé dans tes listes ou sur TMDB.
struct TitreEntite: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Film ou série"
    static let defaultQuery = RequeteTitres()

    let id: String
    let nom: String
    let annee: Int?
    let cheminAffiche: String?

    var reference: ReferenceTitre {
        ReferenceTitre(texte: id) ?? ReferenceTitre(type: .film, tmdbID: 0)
    }

    var displayRepresentation: DisplayRepresentation {
        let type = reference.type == .film ? "Film" : "Série"
        return DisplayRepresentation(title: "\(nom)", subtitle: "\(annee.map { "\(type) · \($0)" } ?? type)")
    }

    init(reference: ReferenceTitre, nom: String, annee: Int?, cheminAffiche: String?) {
        id = reference.description
        self.nom = nom
        self.annee = annee
        self.cheminAffiche = cheminAffiche
    }
}

struct RequeteTitres: EntityStringQuery {
    /// Tes titres d'abord : Siri les reconnaît dans la phrase sans chercher sur TMDB.
    @MainActor
    func suggestedEntities() async throws -> [TitreEntite] {
        suivis().filter { $0.statut == .aVoir || $0.statut == .enCours }.prefix(40).map(entite)
    }

    @MainActor
    func entities(for identifiers: [String]) async throws -> [TitreEntite] {
        let connus = Dictionary(suivis().map { ($0.reference.description, $0) }, uniquingKeysWith: { premier, _ in premier })
        var resultat: [TitreEntite] = []
        for identifiant in identifiers {
            if let suivi = connus[identifiant] {
                resultat.append(entite(suivi))
            } else if let reference = ReferenceTitre(texte: identifiant), let titre = await chercherSurTMDB(reference) {
                resultat.append(titre)
            }
        }
        return resultat
    }

    @MainActor
    func entities(matching texte: String) async throws -> [TitreEntite] {
        let recherche = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recherche.isEmpty else { return try await suggestedEntities() }
        let locaux = suivis().filter { $0.titre.localizedStandardContains(recherche) }.map(entite)
        guard let tmdb = try? DepotCles().client(),
              let trouves = try? await tmdb.rechercherTout(recherche)
        else { return locaux }
        let dejaLa = Set(locaux.map(\.id))
        let distants = trouves.compactMap(\.titre).prefix(8).map { titre in
            TitreEntite(reference: titre.reference, nom: titre.titre, annee: titre.date?.annee, cheminAffiche: titre.cheminAffiche)
        }
        return locaux + distants.filter { !dejaLa.contains($0.id) }
    }

    @MainActor
    private func suivis() -> [Suivi] {
        guard let contexte = ConteneurApp.conteneur?.mainContext else { return [] }
        return (try? contexte.fetch(FetchDescriptor<Suivi>(sortBy: [SortDescriptor(\.ajouteLe, order: .reverse)]))) ?? []
    }

    private func entite(_ suivi: Suivi) -> TitreEntite {
        TitreEntite(reference: suivi.reference, nom: suivi.titre, annee: nil, cheminAffiche: suivi.cheminAffiche)
    }

    private func chercherSurTMDB(_ reference: ReferenceTitre) async -> TitreEntite? {
        guard let tmdb = try? DepotCles().client() else { return nil }
        switch reference.type {
        case .film:
            guard let film = try? await tmdb.film(reference.tmdbID, complements: []) else { return nil }
            return TitreEntite(reference: reference, nom: film.titre, annee: film.dateSortie?.annee, cheminAffiche: film.cheminAffiche)
        case .serie:
            guard let serie = try? await tmdb.serie(reference.tmdbID) else { return nil }
            return TitreEntite(reference: reference, nom: serie.nom, annee: serie.premiereDiffusion?.annee, cheminAffiche: serie.cheminAffiche)
        }
    }
}

struct RaccourcisSeance: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuoiRegarderIntent(),
            phrases: [
                "Qu'est-ce que je regarde ce soir avec \(.applicationName)",
                "Qu'est-ce que je regarde ce soir dans \(.applicationName)",
                "Qu'est-ce qu'on regarde ce soir avec \(.applicationName)",
                "Ma soirée \(.applicationName)",
            ],
            shortTitle: "Ce soir",
            systemImageName: "moon.stars"
        )
        AppShortcut(
            intent: AjouterASoireeIntent(),
            phrases: [
                "Ajoute \(\.$titre) à ma soirée dans \(.applicationName)",
                "Ajoute \(\.$titre) à ma soirée avec \(.applicationName)",
                "Ajouter à ma soirée dans \(.applicationName)",
            ],
            shortTitle: "Ajouter à ma soirée",
            systemImageName: "moon.badge.plus"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .orange
}
