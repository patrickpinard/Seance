import Foundation

/// Apps de lecture qui ouvrent une vidéo du NAS (EF-74). Séance ne lit pas elle-même les MKV et
/// les AVI : elle passe l'adresse SMB à l'app choisie, qui lit le fichier sans le copier.
public enum LecteurVideo: String, Sendable, Codable, CaseIterable, Identifiable {
    case infuse
    case vlc

    public var id: String { rawValue }

    public var nom: String {
        switch self {
        case .infuse: "Infuse"
        case .vlc: "VLC"
        }
    }

    /// À déclarer dans `LSApplicationQueriesSchemes`.
    public var schema: String {
        switch self {
        case .infuse: "infuse"
        case .vlc: "vlc-x-callback"
        }
    }

    public var appStore: URL {
        switch self {
        case .infuse: URL(string: "https://apps.apple.com/app/id1136220934")!
        case .vlc: URL(string: "https://apps.apple.com/app/id650377962")!
        }
    }

    /// Lien x-callback-url : l'adresse de la vidéo, identifiants compris, voyage encodée dans `url=`.
    public func lien(pour video: URL) -> URL? {
        var nonReserves = CharacterSet.alphanumerics
        nonReserves.insert(charactersIn: "-._~")
        guard let encodee = video.absoluteString.addingPercentEncoding(withAllowedCharacters: nonReserves) else { return nil }
        switch self {
        case .infuse: return URL(string: "infuse://x-callback-url/play?url=\(encodee)")
        case .vlc: return URL(string: "vlc-x-callback://x-callback-url/stream?url=\(encodee)")
        }
    }
}
