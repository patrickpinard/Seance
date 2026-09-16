import SeanceKit
import SwiftUI

/// Liens `seance://film/603692` et `seance://serie/108978` : ouverture d'une fiche depuis le widget
/// ou le simulateur.
enum LienProfond {
    static func reference(_ url: URL) -> ReferenceTitre? {
        guard url.scheme == "seance", let hote = url.host(), let type = TypeTitre(rawValue: hote),
              let id = Int(url.lastPathComponent)
        else { return nil }
        return ReferenceTitre(type: type, tmdbID: id)
    }
}
