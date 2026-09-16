import Foundation

/// Ce que Claude renvoie pour un titre : son identifiant, repris tel quel de la liste
/// des candidats, et une phrase qui dit pourquoi il le propose (EF-24).
public struct ChoixClaude: Sendable, Equatable {
    public var reference: ReferenceTitre
    public var phrase: String

    public init(reference: ReferenceTitre, phrase: String) {
        self.reference = reference
        self.phrase = phrase
    }
}

public enum ErreurClaude: Error, Equatable {
    /// Clé refusée (HTTP 401).
    case identifiantsRefuses
    /// HTTP 429 encore renvoyé après toutes les tentatives.
    case limiteDepassee
    /// Claude a refusé de répondre : `stop_reason` vaut « refusal ».
    case refus
    case http(code: Int, message: String?)
    case decodage(String)
    case reponseVide
}

/// Client de l'API Claude (EF-24), appelée en HTTP faute de SDK Swift. La réponse est contrainte
/// par un schéma JSON dont le champ d'identifiant est une énumération des candidats envoyés :
/// Claude ne peut pas inventer un titre. L'app revérifie quand même chaque identifiant (EF-25).
public actor ClientClaude {
    public static let urlBase = URL(string: "https://api.anthropic.com")!
    public static let versionAPI = "2023-06-01"
    public static let modeleParDefaut = "claude-opus-5"
    /// Au-delà, l'invite coûte plus qu'elle ne rapporte (EF-23).
    public static let candidatsMax = 60

    private let cle: String
    private let modele: String
    private let transport: any TransportHTTP
    private let tentativesMax: Int
    private let attendre: @Sendable (Duration) async throws -> Void

    public init(
        cle: String,
        modele: String = modeleParDefaut,
        transport: any TransportHTTP = URLSession.shared,
        tentativesMax: Int = 2,
        attendre: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.cle = cle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.modele = modele
        self.transport = transport
        self.tentativesMax = max(1, tentativesMax)
        self.attendre = attendre
    }

    /// Demande à Claude de classer les candidats et d'expliquer ses choix.
    public func choisir(
        _ demande: DemandeCeSoir,
        parmi candidats: [CandidatSuggestion],
        profil: ProfilGouts,
        nomsGenres: [Int: String] = [:],
        nombre: Int = 5
    ) async throws -> [ChoixClaude] {
        let retenus = Array(candidats.prefix(Self.candidatsMax))
        guard !retenus.isEmpty else { return [] }
        let requete = try requete(demande, retenus, profil, nomsGenres, nombre)

        for tentative in 1...tentativesMax {
            let (donnees, reponse) = try await transport.envoyer(requete)
            switch reponse.statusCode {
            case 200..<300:
                return try Self.lire(donnees)
            case 401, 403:
                throw ErreurClaude.identifiantsRefuses
            case 429, 529:
                guard tentative < tentativesMax else { throw ErreurClaude.limiteDepassee }
                let secondes = reponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init) ?? 2
                try await attendre(.seconds(max(1, secondes)))
            default:
                throw ErreurClaude.http(code: reponse.statusCode, message: Self.messageErreur(donnees))
            }
        }
        throw ErreurClaude.limiteDepassee
    }

    // MARK: - Requête

    func requete(
        _ demande: DemandeCeSoir, _ candidats: [CandidatSuggestion],
        _ profil: ProfilGouts, _ nomsGenres: [Int: String], _ nombre: Int
    ) throws -> URLRequest {
        let format: [String: Any] = [
            "type": "json_schema",
            "name": "suggestions",
            "schema": InviteCeSoir.schema(candidats, nombre: nombre),
        ]
        let corps: [String: Any] = [
            "model": modele,
            "max_tokens": 1500,
            "system": InviteCeSoir.systeme,
            "messages": [["role": "user", "content": InviteCeSoir.message(demande, candidats, profil, nomsGenres, nombre)]],
            "output_config": ["format": format],
        ]
        var requete = URLRequest(url: Self.urlBase.appending(path: "/v1/messages"))
        requete.httpMethod = "POST"
        requete.setValue(cle, forHTTPHeaderField: "x-api-key")
        requete.setValue(Self.versionAPI, forHTTPHeaderField: "anthropic-version")
        requete.setValue("application/json", forHTTPHeaderField: "content-type")
        requete.httpBody = try JSONSerialization.data(withJSONObject: corps, options: [.sortedKeys])
        return requete
    }

    // MARK: - Réponse

    private struct Enveloppe: Decodable {
        struct Bloc: Decodable {
            let type: String
            let text: String?
        }

        let content: [Bloc]
        let raisonArret: String?

        enum CodingKeys: String, CodingKey {
            case content
            case raisonArret = "stop_reason"
        }
    }

    private struct Charge: Decodable {
        struct Element: Decodable {
            let id: String
            let phrase: String
        }

        let suggestions: [Element]
    }

    /// `stop_reason` se lit avant le contenu : un refus n'est pas une réponse vide.
    static func lire(_ donnees: Data) throws -> [ChoixClaude] {
        let enveloppe: Enveloppe
        do {
            enveloppe = try JSONDecoder().decode(Enveloppe.self, from: donnees)
        } catch {
            throw ErreurClaude.decodage(String(describing: error))
        }
        if enveloppe.raisonArret == "refusal" { throw ErreurClaude.refus }
        guard let texte = enveloppe.content.first(where: { $0.type == "text" })?.text, !texte.isEmpty else {
            throw ErreurClaude.reponseVide
        }
        do {
            let charge = try JSONDecoder().decode(Charge.self, from: Data(texte.utf8))
            return charge.suggestions.compactMap { element in
                ReferenceTitre(texte: element.id).map { ChoixClaude(reference: $0, phrase: element.phrase) }
            }
        } catch {
            throw ErreurClaude.decodage(String(describing: error))
        }
    }

    /// L'API détaille ses erreurs dans `error.message`.
    static func messageErreur(_ donnees: Data) -> String? {
        struct Corps: Decodable {
            struct Erreur: Decodable { let message: String? }
            let error: Erreur?
        }
        return (try? JSONDecoder().decode(Corps.self, from: donnees))?.error?.message
    }
}

/// L'invite envoyée à Claude, construite sans réseau pour rester vérifiable par les tests.
enum InviteCeSoir {
    static let systeme = """
    Tu aides Patrick, en Suisse romande, à choisir quoi regarder ce soir. Il aime surtout \
    l'action. Tu réponds en français, au tutoiement, sans flatterie.
    Tu choisis uniquement parmi les candidats listés, en reprenant leur identifiant tel quel. \
    Tu ne proposes jamais un titre absent de la liste, même excellent.
    Chaque phrase dit pourquoi ce titre-là ce soir : elle relie la demande et les goûts de \
    Patrick à ce film ou à cette série, en une phrase de vingt-cinq mots au plus, sans révéler \
    la fin ni recopier le synopsis.
    Si rien ne correspond vraiment à la demande, tu renvoies moins de titres, quitte à n'en \
    renvoyer aucun. Une liste courte et juste vaut mieux qu'une liste remplie.
    """

    static func message(
        _ demande: DemandeCeSoir, _ candidats: [CandidatSuggestion],
        _ profil: ProfilGouts, _ nomsGenres: [Int: String], _ nombre: Int
    ) -> String {
        var morceaux: [String] = []
        let envie = demande.envieNettoyee
        morceaux.append("Demande de ce soir : \(envie.isEmpty ? "rien de précis, surprends-moi." : envie)")

        var precisions: [String] = []
        if let type = demande.typeEffectif { precisions.append(type == .film ? "un film" : "une série") }
        if let duree = demande.dureeMaxEffective { precisions.append("\(duree) min au maximum") }
        if !precisions.isEmpty { morceaux.append("Précisions : \(precisions.joined(separator: ", ")).") }

        morceaux.append(profilEnTexte(profil, nomsGenres))
        morceaux.append("""
        Candidats (identifiant — titre (année) · genres · durée · note TMDB · acteurs · où le regarder · synopsis) :
        \(candidats.map { ligne($0, nomsGenres) }.joined(separator: "\n"))
        """)
        morceaux.append("Renvoie au plus \(nombre) identifiants, du plus au moins convaincant, chacun avec sa phrase.")
        return morceaux.joined(separator: "\n\n")
    }

    static func profilEnTexte(_ profil: ProfilGouts, _ nomsGenres: [Int: String]) -> String {
        guard !profil.estVide else {
            return "Goûts : encore inconnus, Patrick commence tout juste à utiliser l'app."
        }
        var lignes: [String] = []
        let aimes = profil.genresPreferes.prefix(6).map { "\(nomsGenres[$0] ?? "genre \($0)") (\(pourcent(profil.affinite(genre: $0))))" }
        if !aimes.isEmpty { lignes.append("Genres qu'il aime : \(aimes.joined(separator: ", ")).") }
        let evites = profil.genresEvites.prefix(4).compactMap { nomsGenres[$0] }
        if !evites.isEmpty { lignes.append("Genres qu'il évite : \(evites.joined(separator: ", ")).") }
        let acteurs = profil.acteursPreferes.prefix(6).map { profil.nom(acteur: $0) }
        if !acteurs.isEmpty { lignes.append("Acteurs qu'il suit : \(acteurs.joined(separator: ", ")).") }
        if let duree = profil.dureeHabituelleMinutes {
            lignes.append("Ses films font en général \(duree) min.")
        }
        lignes.append("Il regarde \(Int((profil.partSeries * 100).rounded())) % de séries.")
        if let note = profil.noteMoyenne {
            lignes.append(String(format: "Sa note moyenne est de %.1f sur 10.", note))
        }
        lignes.append("Profil établi sur \(profil.observations) signaux\(profil.maturite < 1 ? " : il est encore jeune, reste prudent" : "").")
        return lignes.joined(separator: " ")
    }

    static func ligne(_ candidat: CandidatSuggestion, _ nomsGenres: [Int: String]) -> String {
        let titre = candidat.titre
        var champs: [String] = []
        champs.append(titre.date.map { "\(titre.titre) (\($0.annee))" } ?? titre.titre)
        let genres = titre.genres.compactMap { nomsGenres[$0] }
        if !genres.isEmpty { champs.append(genres.joined(separator: ", ")) }
        if let duree = candidat.dureeMinutes { champs.append("\(duree) min") }
        if titre.nombreVotes >= 50 { champs.append("\(Int((titre.noteMoyenne * 10).rounded())) %") }
        let acteurs = candidat.acteurs.compactMap { candidat.nomsActeurs[$0] }
        if !acteurs.isEmpty { champs.append(acteurs.prefix(4).joined(separator: ", ")) }
        if let ou = ouRegarder(candidat.disponibilite) { champs.append(ou) }
        if !titre.synopsis.isEmpty { champs.append(String(titre.synopsis.prefix(220))) }
        return "\(titre.reference.description) — \(champs.joined(separator: " · "))"
    }

    static func ouRegarder(_ etat: EtatDisponibilite?) -> String? {
        guard let etat else { return nil }
        switch etat {
        case .surNAS: return "sur ton NAS"
        case .dansAbonnements(let fournisseurs):
            return fournisseurs.isEmpty ? "dans tes abonnements" : "sur \(fournisseurs.map(\.nom).joined(separator: ", "))"
        case .aLaTeleBientot(let diffusion): return "à la télé sur \(diffusion.chaine)"
        case .aLouerOuAcheter: return "à louer ou à acheter"
        case .introuvable: return nil
        }
    }

    /// Le champ `id` est une énumération : la réponse ne peut pas sortir de la liste.
    static func schema(_ candidats: [CandidatSuggestion], nombre: Int) -> [String: Any] {
        let identifiant: [String: Any] = ["type": "string", "enum": candidats.map(\.reference.description)]
        let phrase: [String: Any] = ["type": "string", "maxLength": 200]
        let element: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["id", "phrase"],
            "properties": ["id": identifiant, "phrase": phrase],
        ]
        let liste: [String: Any] = [
            "type": "array",
            "minItems": 0,
            "maxItems": nombre,
            "items": element,
        ]
        return [
            "type": "object",
            "additionalProperties": false,
            "required": ["suggestions"],
            "properties": ["suggestions": liste],
        ]
    }

    static func pourcent(_ valeur: Double) -> String {
        "\(Int((valeur * 100).rounded())) %"
    }
}
