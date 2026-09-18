import Foundation
import SeanceKit
import SwiftData

/// Les listes nommées (EF-63) : « Soirées Statham », « À montrer aux enfants »… Un titre peut être dans plusieurs
/// listes, sans rapport avec son statut « à voir », « en cours » ou « terminé ».
@MainActor
public struct ServiceListes {
    public let contexte: ModelContext

    public init(contexte: ModelContext) {
        self.contexte = contexte
    }

    public func listes() throws -> [ListePerso] {
        try contexte.fetch(FetchDescriptor<ListePerso>(sortBy: [SortDescriptor(\.creeeLe)]))
    }

    /// Crée la liste, ou renvoie celle qui porte déjà ce nom (sans tenir compte des majuscules) ; `nil` pour un nom vide.
    @discardableResult
    public func creer(_ nom: String) throws -> ListePerso? {
        let propre = nom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty else { return nil }
        if let existante = try listes().first(where: { $0.nom.compare(propre, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return existante
        }
        let liste = ListePerso(nom: propre)
        contexte.insert(liste)
        try contexte.save()
        return liste
    }

    public func renommer(_ liste: ListePerso, en nom: String) throws {
        let propre = nom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty else { return }
        liste.nom = propre
        try contexte.save()
    }

    public func supprimer(_ liste: ListePerso) throws {
        contexte.delete(liste)
        try contexte.save()
    }

    /// Ajoute le titre en fin de liste, sans doublon ; son nom et son affiche sont gardés pour l'afficher sans réseau.
    public func ajouter(_ reference: ReferenceTitre, titre: String, cheminAffiche: String?, a liste: ListePerso) throws {
        if !liste.titres.contains(reference) { liste.titres.append(reference) }
        liste.apercus.removeAll { $0.reference == reference }
        liste.apercus.append(ApercuTitre(reference: reference, titre: titre, cheminAffiche: cheminAffiche))
        try contexte.save()
    }

    public func retirer(_ reference: ReferenceTitre, de liste: ListePerso) throws {
        liste.titres.removeAll { $0 == reference }
        liste.apercus.removeAll { $0.reference == reference }
        try contexte.save()
    }

    /// Les titres de la liste dans leur ordre, chacun avec de quoi l'afficher : son aperçu, sinon le titre suivi du
    /// même nom (liste venue d'une ancienne sauvegarde), sinon rien d'autre que sa référence.
    public func titres(_ liste: ListePerso) throws -> [ApercuTitre] {
        let apercus = Dictionary(liste.apercus.map { ($0.reference, $0) }, uniquingKeysWith: { premier, _ in premier })
        let suivi = ServiceSuivi(contexte: contexte)
        return try liste.titres.map { reference in
            if let apercu = apercus[reference] { return apercu }
            if let connu = try suivi.suivi(reference) {
                return ApercuTitre(reference: reference, titre: connu.titre, cheminAffiche: connu.cheminAffiche)
            }
            return ApercuTitre(reference: reference, titre: "", cheminAffiche: nil)
        }
    }
}
