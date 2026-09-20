import AMSMB2
import Foundation
import SeanceKit

/// Une connexion SMB gardée le temps d'un passage de synchronisation. Sans elle, chaque opération — lister, lire
/// le fichier de chaque appareil, écrire le sien — ouvrait la sienne : sonde du réseau local, connexion, partage,
/// déconnexion, cinq fois de suite sur un NAS qui répond lentement.
actor SessionSMB {
    private let explorateur: ExplorateurSMB
    private var client: SMB2Manager?
    /// Vrai entre `ouvrir()` et `fermer()` : hors de là, chaque opération reprend son ancienne façon de faire.
    private var passageEnCours = false
    /// Le dernier contenu lu du dossier, pour ne pas le redemander à chaque lecture ou écriture.
    private var nomsConnus: [String]?

    init(explorateur: ExplorateurSMB) {
        self.explorateur = explorateur
    }

    func ouvrir() {
        passageEnCours = true
        nomsConnus = nil
    }

    func fermer() async {
        passageEnCours = false
        nomsConnus = nil
        if let client { try? await client.disconnectShare() }
        client = nil
    }

    /// Exécute le travail sur le partage : sur la connexion gardée pendant un passage, sur une connexion
    /// jetable sinon. Une erreur ferme la connexion gardée : la suivante repartira d'une connexion saine.
    func avec<Resultat: Sendable>(_ travail: sending (SMB2Manager) async throws -> Resultat) async throws -> Resultat {
        guard passageEnCours else { return try await explorateur.avecPartage(travail) }
        let ouvert: SMB2Manager
        if let client {
            ouvert = client
        } else {
            ouvert = try await explorateur.connecter()
            client = ouvert
        }
        do {
            return try await travail(ouvert)
        } catch {
            await fermerConnexion()
            throw error
        }
    }

    /// Les noms de fichiers du dossier, relus une seule fois par passage.
    func noms(_ dossier: String) async throws -> [String] {
        if let nomsConnus { return nomsConnus }
        let noms = try await avec { client in
            ((try? await client.contentsOfDirectory(atPath: dossier)) ?? []).compactMap { $0[.nameKey] as? String }
        }
        if passageEnCours { nomsConnus = noms }
        return noms
    }

    /// Le dossier vient de changer : le prochain besoin de noms les relira.
    func oublierLesNoms() {
        nomsConnus = nil
    }

    private func fermerConnexion() async {
        if let client { try? await client.disconnectShare() }
        client = nil
        nomsConnus = nil
    }
}

/// Le dossier de synchronisation sur le NAS (EF-144) : « Séance », à la racine du partage des films. Chaque appareil y
/// dépose son fichier et y lit ceux des autres — c'est ainsi que les listes de l'iPhone arrivent sur l'Apple TV, qui
/// n'a ni Fichiers ni iCloud Drive. Le compte du NAS doit pouvoir **écrire** dans le partage.
public struct DossierSynchroSMB: TransportSynchro {
    public static let dossierParDefaut = "Séance"

    private let session: SessionSMB
    private let dossier: String

    public init(reglages: ReglagesNAS, motDePasse: String, dossier: String = DossierSynchroSMB.dossierParDefaut) {
        session = SessionSMB(explorateur: ExplorateurSMB(reglages: reglages, motDePasse: motDePasse))
        self.dossier = dossier
    }

    /// Le moteur annonce le début et la fin d'un passage : entre les deux, une seule connexion sert à tout.
    public func ouvrirPassage() async {
        await session.ouvrir()
    }

    public func fermerPassage() async {
        await session.fermer()
    }

    public func lister() async throws -> [SynchroDossier.Fichier] {
        let dossier = dossier
        return try await session.avec { client in
            // Pas encore de dossier : personne n'a rien déposé, ce n'est pas une erreur.
            guard let elements = try? await client.contentsOfDirectory(atPath: dossier) else { return [] }
            return elements.compactMap { element in
                guard (element[.isDirectoryKey] as? Bool) != true, let nom = element[.nameKey] as? String else { return nil }
                // Le NAS peut rendre les accents décomposés : les noms se comparent composés, comme ceux de l'app.
                return SynchroDossier.Fichier(nom: nom.precomposedStringWithCanonicalMapping,
                                              modifieLe: (element[.contentModificationDateKey] as? Date) ?? .distantPast)
            }
        }
    }

    public func lire(_ nom: String) async throws -> Data {
        let dossier = dossier
        // Le nom réel, tel que le NAS l'écrit (accents composés ou non), relu une fois par passage.
        let reel = try await nomReel(nom)
        return try await session.avec { client in
            try await client.contents(atPath: "\(dossier)/\(reel)", range: Range<UInt64>?.none, progress: nil)
        }
    }

    public func ecrire(_ donnees: Data, nom: String) async throws {
        let dossier = dossier
        let reel = try await nomReel(nom)
        try await session.avec { client in
            if (try? await client.attributesOfItem(atPath: dossier)) == nil {
                try await client.createDirectory(atPath: dossier)
            }
            let cible = "\(dossier)/\(reel)"
            // Écrire à côté puis remplacer : un autre appareil ne lit jamais un fichier à moitié écrit.
            let provisoire = "\(dossier)/.\(UUID().uuidString.prefix(8)).tmp"
            try await client.write(data: donnees, toPath: provisoire, progress: nil)
            try? await client.removeItem(atPath: cible)
            try await client.moveItem(atPath: provisoire, toPath: cible)
        }
        await session.oublierLesNoms()
    }

    private func nomReel(_ nom: String) async throws -> String {
        let presents = try await session.noms(dossier)
        return presents.first { $0.precomposedStringWithCanonicalMapping == nom } ?? nom
    }
}
