import Foundation

public struct ResultatSuggestions: Sendable, Equatable {
    public enum Origine: String, Sendable {
        /// Classé par Claude, à partir des candidats de l'app (EF-24).
        case claude
        /// Classé sur l'iPhone, sans réseau ni clé (EF-27).
        case local
    }

    public var suggestions: [SuggestionClassee]
    public var origine: Origine
    /// Affiché en petit sous les suggestions quand quelque chose n'a pas marché comme prévu.
    public var avertissement: String?
    /// Ce que le classement local aurait proposé : l'écran le montre si Claude n'a rien retenu.
    public var repliLocal: [SuggestionClassee]

    public init(
        suggestions: [SuggestionClassee], origine: Origine,
        avertissement: String? = nil, repliLocal: [SuggestionClassee] = []
    ) {
        self.suggestions = suggestions
        self.origine = origine
        self.avertissement = avertissement
        self.repliLocal = repliLocal
    }
}

/// Orchestre « Qu'est-ce que je regarde ce soir ? » (EF-22 à EF-27) : classement local,
/// appel à Claude, puis revérification de chaque identifiant renvoyé.
public struct ServiceRecommandation: Sendable {
    /// `nil` tant qu'aucune clé n'est enregistrée : tout se fait alors en local.
    public let claude: ClientClaude?
    public var nombre: Int

    public init(claude: ClientClaude?, nombre: Int = 5) {
        self.claude = claude
        self.nombre = max(1, nombre)
    }

    public func suggerer(
        _ demande: DemandeCeSoir,
        candidats: [CandidatSuggestion],
        profil: ProfilGouts,
        nomsGenres: [Int: String] = [:],
        forcerLocal: Bool = false
    ) async -> ResultatSuggestions {
        // Le classement local sert d'abord à trier les candidats envoyés à Claude :
        // il ne lui en reste que soixante, les plus proches des goûts de Patrick (EF-23).
        let classes = ClassementLocal.classer(candidats, profil: profil, demande: demande, nomsGenres: nomsGenres)
        let local = Array(classes.prefix(nombre))

        guard let claude, !forcerLocal, !classes.isEmpty else {
            return ResultatSuggestions(suggestions: local, origine: .local)
        }

        do {
            let choix = try await claude.choisir(
                demande,
                parmi: classes.map(\.candidat),
                profil: profil,
                nomsGenres: nomsGenres,
                nombre: nombre
            )
            let verifiees = Self.verifier(choix, parmi: classes, nombre: nombre)
            return ResultatSuggestions(
                suggestions: verifiees,
                origine: .claude,
                avertissement: avertissementVerification(choix.count, verifiees.count),
                repliLocal: local
            )
        } catch {
            return ResultatSuggestions(
                suggestions: local,
                origine: .local,
                avertissement: Self.avertissement(error)
            )
        }
    }

    /// EF-25 : un identifiant absent des candidats est retiré, jamais remplacé.
    /// L'ordre de Claude est gardé, le score local sert seulement à l'affichage.
    static func verifier(_ choix: [ChoixClaude], parmi classes: [SuggestionClassee], nombre: Int) -> [SuggestionClassee] {
        let parReference = Dictionary(classes.map { ($0.reference, $0) }, uniquingKeysWith: { premier, _ in premier })
        var vues = Set<ReferenceTitre>()
        return choix.compactMap { choix -> SuggestionClassee? in
            guard vues.insert(choix.reference).inserted, var suggestion = parReference[choix.reference] else { return nil }
            let phrase = choix.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            if !phrase.isEmpty { suggestion.phrase = phrase }
            return suggestion
        }
        .prefix(nombre)
        .map { $0 }
    }

    private func avertissementVerification(_ renvoyes: Int, _ gardes: Int) -> String? {
        if renvoyes == 0 { return "Claude n'a rien retenu parmi les candidats du soir." }
        if gardes < renvoyes {
            let retires = renvoyes - gardes
            return retires == 1
                ? "Une suggestion a été retirée : le titre n'était plus dans la liste vérifiée."
                : "\(retires) suggestions ont été retirées : ces titres n'étaient plus dans la liste vérifiée."
        }
        return nil
    }

    static func avertissement(_ erreur: any Error) -> String {
        switch erreur as? ErreurClaude {
        case .identifiantsRefuses: "Clé Claude refusée : classement local en attendant."
        case .limiteDepassee: "Claude est saturé pour l'instant : classement local en attendant."
        case .refus: "Claude a préféré ne pas répondre : voici le classement local."
        case .reponseVide, .decodage: "Réponse de Claude illisible : voici le classement local."
        case .http(let code, _): "Claude a répondu \(code) : voici le classement local."
        case nil: "Claude est injoignable : voici le classement local."
        }
    }
}
