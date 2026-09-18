import CryptoKit
import Foundation

/// Garde sur disque les réponses de TMDB : une fiche relue dans la journée ne repart pas sur le réseau, et sans
/// réseau l'app montre ce qu'elle a déjà vu, même ancien. La clé d'API ne fait jamais partie du nom du fichier.
/// Durées : une fiche ou une saison 24 h, les plateformes 12 h, une liste ou une recherche 1 h, les genres 7 jours.
public struct CacheTMDB: TransportHTTP {
    private let reseau: any TransportHTTP
    private let dossier: URL
    private let maintenant: @Sendable () -> Date

    /// Au-delà, une réponse n'est plus gardée, même pour le hors-ligne.
    public static let conservation: TimeInterval = 30 * 86_400

    public init(reseau: any TransportHTTP = URLSession.shared, dossier: URL, maintenant: @escaping @Sendable () -> Date = { .now }) {
        self.reseau = reseau
        self.dossier = dossier
        self.maintenant = maintenant
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    }

    /// Combien de temps une réponse reste fraîche, selon ce qu'elle contient.
    public static func fraicheur(_ chemin: String) -> TimeInterval {
        if chemin.contains("/genre/") { return 7 * 86_400 }
        if chemin.contains("/discover/") || chemin.contains("/search/") || chemin.contains("/trending/") { return 3600 }
        if chemin.contains("/watch/providers") { return 12 * 3600 }
        return 86_400
    }

    public func envoyer(_ requete: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard requete.httpMethod ?? "GET" == "GET", let url = requete.url else { return try await reseau.envoyer(requete) }
        let fichier = dossier.appendingPathComponent(Self.nom(url))
        let age = (try? fichier.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            .map { maintenant().timeIntervalSince($0) }
        if let age, age < Self.fraicheur(url.path), let donnees = try? Data(contentsOf: fichier) {
            return (donnees, Self.reponse(url))
        }
        do {
            let (donnees, reponse) = try await reseau.envoyer(requete)
            // Seules les bonnes réponses se gardent : une erreur 401 ou 429 ne doit pas être rejouée.
            if reponse.statusCode == 200 {
                try? donnees.write(to: fichier, options: .atomic)
                // L'âge se compte sur l'horloge donnée, pas sur celle du disque.
                try? FileManager.default.setAttributes([.modificationDate: maintenant()], ofItemAtPath: fichier.path)
            }
            return (donnees, reponse)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Pas de réseau : mieux vaut une fiche ancienne que pas de fiche.
            if let age, age < Self.conservation, let donnees = try? Data(contentsOf: fichier) {
                return (donnees, Self.reponse(url))
            }
            throw error
        }
    }

    /// Retire ce qui est trop vieux pour servir, même hors ligne. Renvoie le nombre de fichiers retirés.
    @discardableResult
    public func purger() -> Int {
        let fichiers = (try? FileManager.default.contentsOfDirectory(at: dossier, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var retires = 0
        for fichier in fichiers {
            let date = (try? fichier.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if maintenant().timeIntervalSince(date) > Self.conservation, (try? FileManager.default.removeItem(at: fichier)) != nil { retires += 1 }
        }
        return retires
    }

    public func vider() {
        try? FileManager.default.removeItem(at: dossier)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    }

    /// Le nom du fichier : l'empreinte de l'adresse **sans** la clé d'API, paramètres triés.
    static func nom(_ url: URL) -> String {
        var composants = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let parametres = (composants?.queryItems ?? []).filter { $0.name != "api_key" }.sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
        composants?.queryItems = parametres.isEmpty ? nil : parametres
        let texte = composants?.string ?? url.absoluteString
        return SHA256.hash(data: Data(texte.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
    }

    private static func reponse(_ url: URL) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json", "X-Seance-Cache": "1"])!
    }
}
