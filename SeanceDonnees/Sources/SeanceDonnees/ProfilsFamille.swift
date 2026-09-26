import Foundation
import SeanceKit
import SwiftData

/// La famille (Séance 6.0) : plusieurs personnes sur le même appareil, chacune avec ses listes, ses notes, ses pouces et
/// ses idées du soir. Le profil principal garde le magasin de toujours ; les autres ont le leur à côté
/// (`EntrepotSeance.Emplacement.profil`). Le registre vit dans les réglages du groupe d'apps : le widget le lit aussi.
public struct ProfilFamille: Codable, Sendable, Hashable, Identifiable {
    /// Vide pour le profil principal.
    public var id: String
    public var prenom: String
    /// Un symbole de l'app, pour le reconnaître d'un coup d'œil.
    public var symbole: String

    public init(id: String, prenom: String, symbole: String = "person.fill") {
        self.id = id
        self.prenom = prenom
        self.symbole = symbole
    }

    public var estPrincipal: Bool { id.isEmpty }

    public var emplacement: EntrepotSeance.Emplacement { estPrincipal ? .groupeApp : .profil(id) }

    /// Le sous-dossier de synchronisation du profil : le principal reste à la racine, comme avant la 6.0. Deux appareils se
    /// reconnaissent par le prénom — « Famille/Anne » sur l'iPhone comme sur l'iPad.
    public var dossierSynchro: String? {
        estPrincipal ? nil : "Famille/" + Self.nomDeDossier(prenom)
    }

    static func nomDeDossier(_ prenom: String) -> String {
        let propre = prenom.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|")).joined(separator: "-")
        // « anne » sur l'iPad et « Anne » sur l'iPhone sont la même personne : un seul dossier, quelle que soit la casse du NAS.
        return propre.isEmpty ? "Profil" : propre.capitalized(with: Locale(identifier: "fr_CH"))
    }
}

public struct ProfilsFamille {
    /// Les images qu'une personne peut choisir (8.2.3 : davantage de choix). Des symboles d'Apple et non des émojis : la
    /// charte de Séance n'en veut pas dans l'interface.
    public static let symboles = ["person.fill", "star.fill", "heart.fill", "bolt.fill", "moon.stars.fill", "flame.fill", "leaf.fill",
                                  "gamecontroller.fill", "crown.fill", "sparkles", "sun.max.fill", "cloud.fill", "popcorn.fill",
                                  "film.fill", "music.note", "soccerball", "bicycle", "pawprint.fill", "cat.fill", "dog.fill",
                                  "hare.fill", "bird.fill", "fish.fill", "tree.fill"]

    private let defauts: UserDefaults
    private static let cleProfils = "famille.profils"
    private static let cleActif = "famille.actif"
    private static let cleDemander = "famille.demanderAuLancement"

    public init(defauts: UserDefaults? = nil) {
        self.defauts = defauts ?? UserDefaults(suiteName: EntrepotSeance.groupeApp) ?? .standard
    }

    /// Le profil principal d'abord (toujours présent), puis les autres dans l'ordre de leur création.
    public var profils: [ProfilFamille] {
        let autres = defauts.data(forKey: Self.cleProfils).flatMap { try? JSONDecoder().decode([ProfilFamille].self, from: $0) } ?? []
        let principal = autres.first(where: \.estPrincipal) ?? ProfilFamille(id: "", prenom: "", symbole: "person.fill")
        return [principal] + autres.filter { !$0.estPrincipal }
    }

    public var aPlusieursProfils: Bool { profils.count > 1 }

    public var actif: ProfilFamille {
        let id = defauts.string(forKey: Self.cleActif) ?? ""
        return profils.first { $0.id == id } ?? profils[0]
    }

    public func activer(_ profil: ProfilFamille) {
        defauts.set(profil.id, forKey: Self.cleActif)
    }

    /// « Qui regarde ? » à l'ouverture de l'app, quand il y a plusieurs profils. Tant que personne n'a réglé la
    /// question, l'appelant décide (6.4) : un appareil partagé — l'Apple TV, l'iPad de la maison — le demande, un
    /// iPhone non, car la réponse y est toujours la même et l'écran s'interposait à chaque ouverture.
    public func demanderAuLancement(parDefaut: Bool) -> Bool {
        defauts.object(forKey: Self.cleDemander) == nil ? parDefaut : defauts.bool(forKey: Self.cleDemander)
    }

    public var demanderAuLancement: Bool {
        get { demanderAuLancement(parDefaut: true) }
        nonmutating set { defauts.set(newValue, forKey: Self.cleDemander) }
    }

    @discardableResult
    public func ajouter(prenom: String, symbole: String) -> ProfilFamille {
        let profil = ProfilFamille(id: String(UUID().uuidString.prefix(8)), prenom: prenom.trimmingCharacters(in: .whitespacesAndNewlines), symbole: symbole)
        enregistrer(profils + [profil])
        return profil
    }

    /// Renommer, ou changer de symbole ; vaut aussi pour le profil principal.
    public func modifier(_ profil: ProfilFamille) {
        var tous = profils
        guard let rang = tous.firstIndex(where: { $0.id == profil.id }) else { return }
        tous[rang] = profil
        enregistrer(tous)
    }

    /// Retire un profil du registre et efface son magasin. Le profil principal ne se supprime pas.
    public func supprimer(_ profil: ProfilFamille) {
        guard !profil.estPrincipal else { return }
        enregistrer(profils.filter { $0.id != profil.id })
        if actif.id == profil.id || defauts.string(forKey: Self.cleActif) == profil.id { defauts.removeObject(forKey: Self.cleActif) }
        if let dossier = EntrepotSeance.dossierPartage?.appending(path: "Library/Application Support") {
            for suffixe in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: dossier.appending(path: "Utilisateur-\(profil.id).store\(suffixe)"))
            }
        }
    }

    // MARK: La famille voyage entre les appareils (6.0.1)

    /// La clé sous laquelle la famille voyage dans les réglages de la sauvegarde et de la synchronisation.
    public static let cleSynchro = "famille.profils"

    /// Les profils de la maison, tels qu'ils partent vers les autres appareils ; `nil` quand il n'y a que le principal.
    public func exporter() -> Data? {
        let autres = profils.filter { !$0.estPrincipal }
        return autres.isEmpty ? nil : try? JSONEncoder().encode(autres)
    }

    /// Ajoute ici les personnes créées ailleurs, avec le même identifiant — leurs listes se retrouvent ainsi d'un appareil
    /// à l'autre, dans le sous-dossier à leur prénom. Rien n'est jamais retiré : supprimer un profil reste un geste local.
    /// Renvoie le nombre de personnes ajoutées.
    @discardableResult
    public func fusionner(_ donnees: Data) -> Int {
        guard let recus = try? JSONDecoder().decode([ProfilFamille].self, from: donnees) else { return 0 }
        var tous = profils
        var ajoutes = 0
        for recu in recus where !recu.estPrincipal && !recu.prenom.isEmpty {
            let connu = tous.contains { $0.id == recu.id || $0.prenom.compare(recu.prenom, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            if !connu { tous.append(recu); ajoutes += 1 }
        }
        if ajoutes > 0 { enregistrer(tous) }
        return ajoutes
    }

    private func enregistrer(_ profils: [ProfilFamille]) {
        defauts.set(try? JSONEncoder().encode(profils), forKey: Self.cleProfils)
    }
}

/// Ce que le foyer partage, et ce que plusieurs personnes regardent ensemble.
@MainActor
public enum ServiceFamille {
    /// Les plateformes, les chaînes et les sources du NAS sont celles de la maison : un nouveau profil les reçoit, et elles
    /// se recopient à chaque changement de profil, dans le sens du profil qu'on quitte vers celui où l'on entre.
    public static func partagerLeFoyer(de source: ModelContext, vers cible: ModelContext) throws {
        var foyer = Sauvegarde(creeeLe: .now)
        let complete = try ServiceSauvegarde(contexte: source).exporter()
        foyer.abonnements = complete.abonnements
        foyer.chaines = complete.chaines
        _ = try ServiceSauvegarde(contexte: cible).importer(foyer)
        // Ce qui existait déjà des deux côtés suit l'état de la maison : cochée ici, cochée là.
        let actifs = Dictionary(complete.abonnements.map { ($0.providerID, $0.actif) }, uniquingKeysWith: { premier, _ in premier })
        for abonnement in try cible.fetch(FetchDescriptor<Abonnement>()) {
            if let actif = actifs[abonnement.providerID], actif != abonnement.actif { abonnement.actif = actif }
        }
        let actives = Dictionary(complete.chaines.map { ($0.identifiantGuide, $0.active) }, uniquingKeysWith: { premier, _ in premier })
        for chaine in try cible.fetch(FetchDescriptor<Chaine>()) {
            if let active = actives[chaine.identifiantGuide], active != chaine.active { chaine.active = active }
        }
        try cible.save()
    }

    /// « Qui regarde ce soir ? » : les goûts de plusieurs personnes fondus en un seul profil. Un genre qu'une seule
    /// déteste est pénalisé plus qu'il n'est moyenné : on cherche ce qui plaît à tous, pas la moyenne.
    public static func fondre(_ profils: [ProfilGouts]) -> ProfilGouts {
        guard let premier = profils.first else { return ProfilGouts() }
        guard profils.count > 1 else { return premier }
        var fondu = ProfilGouts()
        let nombre = Double(profils.count)
        func melanger(_ valeurs: [[Int: Double]]) -> [Int: Double] {
            var resultat: [Int: Double] = [:]
            for cle in Set(valeurs.flatMap(\.keys)) {
                let notes = valeurs.map { $0[cle] ?? 0 }
                let moyenne = notes.reduce(0, +) / nombre
                let pire = notes.min() ?? 0
                resultat[cle] = pire < -0.25 ? min(moyenne, pire / 2) : moyenne
            }
            return resultat
        }
        fondu.genres = melanger(profils.map(\.genres))
        fondu.acteurs = melanger(profils.map(\.acteurs))
        fondu.nomsActeurs = profils.reduce(into: [:]) { $0.merge($1.nomsActeurs) { premier, _ in premier } }
        let durees = profils.compactMap(\.dureeHabituelleMinutes)
        fondu.dureeHabituelleMinutes = durees.isEmpty ? nil : durees.reduce(0, +) / durees.count
        fondu.ecartDureeMinutes = profils.map(\.ecartDureeMinutes).max() ?? 30
        fondu.partSeries = profils.map(\.partSeries).reduce(0, +) / nombre
        let notes = profils.compactMap(\.noteMoyenne)
        fondu.noteMoyenne = notes.isEmpty ? nil : notes.reduce(0, +) / Double(notes.count)
        fondu.observations = profils.map(\.observations).reduce(0, +)
        return fondu
    }

    /// Ce que personne ne doit se voir proposer : vu par l'un, écarté par l'autre, reporté par un troisième.
    public static func fondre(_ contextes: [CollecteurCandidats.Contexte]) -> CollecteurCandidats.Contexte {
        guard var fondu = contextes.first else { return CollecteurCandidats.Contexte() }
        for autre in contextes.dropFirst() {
            fondu.dejaVus.formUnion(autre.dejaVus)
            fondu.exclus.formUnion(autre.exclus)
            fondu.reportes.formUnion(autre.reportes)
            fondu.abonnements = Array(Set(fondu.abonnements + autre.abonnements))
        }
        return fondu
    }
}
