import Foundation
import SeanceKit
import SwiftData

/// « Suivre un acteur » : Séance prévient quand un nouveau film où il joue est annoncé.
@MainActor
public struct ServiceActeurs {
    public let contexte: ModelContext

    public init(contexte: ModelContext) {
        self.contexte = contexte
    }

    public func suivi(_ personneID: Int) throws -> ActeurSuivi? {
        var requete = FetchDescriptor<ActeurSuivi>(predicate: #Predicate { $0.personneID == personneID })
        requete.fetchLimit = 1
        return try contexte.fetch(requete).first
    }

    /// Suivre deux fois le même acteur ne crée pas de doublon ; le portrait est mis à jour.
    public func suivre(personneID: Int, nom: String, cheminPortrait: String?) throws {
        if let existant = try suivi(personneID) {
            existant.nom = nom
            existant.cheminPortrait = cheminPortrait ?? existant.cheminPortrait
        } else {
            contexte.insert(ActeurSuivi(personneID: personneID, nom: nom, cheminPortrait: cheminPortrait))
        }
        try contexte.save()
    }

    public func nePlusSuivre(_ personneID: Int) throws {
        try contexte.delete(model: ActeurSuivi.self, where: #Predicate { $0.personneID == personneID })
        try contexte.save()
    }
}
