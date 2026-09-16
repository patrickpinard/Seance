import SeanceKit
import SwiftUI

/// Liens `seance://film/603692` et `seance://serie/108978` : ouverture d'une fiche depuis le widget
/// ou le simulateur.
enum LienProfond {
    enum Onglet {
        case ceSoir
        case aVenir
    }

    /// `seance://cesoir` et `seance://avenir`, touchés dans un widget.
    static func onglet(_ url: URL) -> Onglet? {
        guard url.scheme == "seance" else { return nil }
        switch url.host() {
        case "cesoir": return .ceSoir
        case "avenir": return .aVenir
        default: return nil
        }
    }

    static func reference(_ url: URL) -> ReferenceTitre? {
        guard url.scheme == "seance", let hote = url.host(), let type = TypeTitre(rawValue: hote),
              let id = Int(url.lastPathComponent)
        else { return nil }
        return ReferenceTitre(type: type, tmdbID: id)
    }
}
