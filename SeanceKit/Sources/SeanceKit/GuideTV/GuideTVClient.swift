import Foundation

public enum ErreurGuideTV: Error, Equatable {
    case http(code: Int)
}

/// Programmes TV des chaînes françaises, depuis les fichiers de XML TV Fr (projet bénévole, sans garantie).
/// Règles d'usage : un téléchargement par jour, après 3 h, toujours en version compressée.
public actor GuideTVClient {
    public enum Fichier: String, Sendable, CaseIterable {
        /// TNT française : environ 1,2 Mo compressé, 5 jours de programmes.
        case tnt = "xmltv_tnt.xml.gz"
        /// Environ 785 chaînes : 17 Mo compressé, à réserver aux chaînes hors TNT.
        case complet = "xmltv.xml.gz"
    }

    public static let urlBase = URL(string: "https://xmltvfr.fr/xmltv/")!

    private let transport: any TransportHTTP

    public init(transport: any TransportHTTP = URLSession.shared) {
        self.transport = transport
    }

    /// Le fichier TNT suffit pour les chaînes françaises ; la RTS impose le fichier complet.
    public static func fichier(pour chaines: Set<String>) -> Fichier {
        chaines.isSubset(of: Set(ChaineGuide.tntParDefaut.map(\.id))) ? .tnt : .complet
    }

    /// Films et séries des chaînes demandées ; les magazines, le sport et le reste sont écartés.
    public func programmes(
        fichier: Fichier? = nil,
        chaines: Set<String>,
        natures: Set<ProgrammeTV.Nature> = [.film, .serie]
    ) async throws -> XMLTV.Resultat {
        let fichier = fichier ?? Self.fichier(pour: chaines)
        var requete = URLRequest(url: Self.urlBase.appending(path: fichier.rawValue))
        requete.setValue("application/gzip", forHTTPHeaderField: "Accept")
        let (donnees, reponse) = try await transport.envoyer(requete)
        guard (200..<300).contains(reponse.statusCode) else {
            throw ErreurGuideTV.http(code: reponse.statusCode)
        }
        var resultat = try XMLTV.lire(try Gzip.decompresser(donnees), chaines: chaines)
        resultat.programmes.removeAll { !natures.contains($0.nature) }
        return resultat
    }
}
