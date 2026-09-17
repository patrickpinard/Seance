import Foundation

/// Avec un compte Apple gratuit, l'app cesse de s'ouvrir quand son profil d'installation expire (7 jours).
/// Le profil est un plist signé ; sa date d'expiration se lit sans vérifier la signature.
public enum ProfilInstallation {
    public static func dateExpiration(_ donnees: Data) -> Date? {
        guard let debut = donnees.range(of: Data("<?xml".utf8)),
              let fin = donnees.range(of: Data("</plist>".utf8), in: debut.lowerBound..<donnees.endIndex)
        else { return nil }
        let plist = donnees.subdata(in: debut.lowerBound..<fin.upperBound)
        let dictionnaire = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        return dictionnaire?["ExpirationDate"] as? Date
    }

    /// Profil de l'app en cours : `embedded.mobileprovision` sur l'iPhone, `embedded.provisionprofile` sur le Mac.
    public static func dateExpirationDeLApp(bundle: Bundle = .main) -> Date? {
        let candidats = [
            bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
            bundle.bundleURL.appending(path: "Contents/embedded.provisionprofile"),
        ]
        for url in candidats.compactMap({ $0 }) {
            if let donnees = try? Data(contentsOf: url), let date = dateExpiration(donnees) { return date }
        }
        return nil
    }

    /// « encore 5 jours », « expire demain », « expire aujourd'hui », « expirée ».
    public static func libelle(expiration: Date, maintenant: Date = .now, fuseau: TimeZone = .suisse) -> String {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = fuseau
        let jours = calendrier.dateComponents([.day], from: calendrier.startOfDay(for: maintenant),
                                              to: calendrier.startOfDay(for: expiration)).day ?? 0
        if expiration <= maintenant { return "expirée" }
        switch jours {
        case 0: return "expire aujourd'hui"
        case 1: return "expire demain"
        default: return "encore \(jours) jours"
        }
    }
}
