import Foundation
import SeanceKit
import SwiftData

/// Les favoris (EF-165 à EF-168) : une collection à part, que l'on garde et que l'on montre. Ajouter un favori ne
/// change ni les listes, ni les goûts, ni les statistiques — et retirer un titre de « À voir » ne l'en sort pas.
@MainActor
public struct ServiceFavoris {
    private let contexte: ModelContext

    public init(contexte: ModelContext) {
        self.contexte = contexte
    }

    public func tous() throws -> [Favori] {
        try contexte.fetch(FetchDescriptor<Favori>(sortBy: [SortDescriptor(\.ajouteLe, order: .reverse)]))
    }

    public func favori(_ reference: ReferenceTitre) throws -> Favori? {
        let id = reference.tmdbID
        let type = reference.type.rawValue
        return try contexte.fetch(FetchDescriptor<Favori>(predicate: #Predicate { $0.tmdbID == id && $0.typeBrut == type })).first
    }

    public func estFavori(_ reference: ReferenceTitre) throws -> Bool {
        try favori(reference) != nil
    }

    /// Ajoute, ou retire si le titre y était déjà. Renvoie l'état après le geste.
    @discardableResult
    public func basculer(_ reference: ReferenceTitre, titre: String, cheminAffiche: String? = nil, annee: Int? = nil) throws -> Bool {
        if let existant = try favori(reference) {
            contexte.delete(existant)
            try contexte.save()
            return false
        }
        contexte.insert(Favori(reference: reference, titre: titre, cheminAffiche: cheminAffiche, annee: annee))
        try contexte.save()
        return true
    }

    public func retirer(_ reference: ReferenceTitre) throws {
        guard let existant = try favori(reference) else { return }
        contexte.delete(existant)
        try contexte.save()
    }

    /// 8.11 : les favoris disparaissent de l'interface — « J'aime » et la note disent déjà ce qu'on aime. Chaque favori
    /// devient un « J'aime » (s'il ne l'était pas, et sauf titre écarté), puis quitte la base : la suppression voyage
    /// par la synchronisation, et un second passage ne trouve plus rien. Renvoie le nombre de favoris convertis.
    @discardableResult
    public func convertirEnJAime() throws -> Int {
        let favoris = try tous()
        guard !favoris.isEmpty else { return 0 }
        let gouts = ServiceGouts(contexte: contexte)
        let suivis = ServiceSuivi(contexte: contexte)
        for favori in favoris {
            let suivi = try suivis.suivi(favori.reference)
            if try !gouts.estAime(favori.reference), suivi?.statut != .exclu {
                try gouts.aimer(favori.reference, titre: favori.titre, cheminAffiche: favori.cheminAffiche, genres: suivi?.genres ?? [])
            }
            contexte.delete(favori)
        }
        try contexte.save()
        return favoris.count
    }

    /// La liste à envoyer à quelqu'un (EF-167) : lisible telle quelle dans Messages ou dans un courriel.
    public func texteAPartager(prenom: String?) throws -> String {
        let favoris = try tous()
        guard !favoris.isEmpty else { return "" }
        let entete = prenom.map { "Les favoris de \($0)" } ?? "Mes favoris"
        let lignes = favoris.map { favori -> String in
            let annee = favori.annee.map { " (\($0))" } ?? ""
            let genre = favori.type == .film ? "film" : "série"
            return "• \(favori.titre)\(annee) — \(genre)"
        }
        return ([entete, ""] + lignes + ["", "Envoyé depuis Séance"]).joined(separator: "\n")
    }
}
