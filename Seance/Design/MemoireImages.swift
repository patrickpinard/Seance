import ImageIO
import UIKit

/// Les images décodées, en mémoire (8.1), communes à l'app et à l'Apple TV (`project.yml`) :
/// - une limite en octets (150 Mo) plutôt qu'en nombre — 400 fonds décodés pouvaient dépasser 500 Mo, et iOS fermait
///   Séance dès qu'elle passait en arrière-plan ;
/// - une seule requête par adresse : dix cartes qui montrent la même affiche attendent le même téléchargement ;
/// - un décodage plafonné en taille, directement à la bonne dimension, sans passer par l'image entière.
final class MemoireImages: @unchecked Sendable {
    private let cache = NSCache<NSURL, UIImage>()
    private var enVol: [URL: Task<UIImage?, Never>] = [:]
    private let verrou = NSLock()
    private let charger: @Sendable (URL) async -> Data?
    /// Le plus grand côté, en pixels, d'une image décodée.
    private let coteMax: CGFloat

    init(limiteOctets: Int = 150 * 1024 * 1024, coteMax: CGFloat, charger: @escaping @Sendable (URL) async -> Data?) {
        cache.totalCostLimit = limiteOctets
        self.coteMax = coteMax
        self.charger = charger
    }

    func enMemoire(_ url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func vider() {
        cache.removeAllObjects()
    }

    /// L'image, de la mémoire ou du réseau ; `nil` en cas d'échec.
    func image(_ url: URL) async -> UIImage? {
        if let connue = enMemoire(url) { return connue }
        let tache: Task<UIImage?, Never> = verrou.withLock {
            if let deja = enVol[url] { return deja }
            let nouvelle = Task<UIImage?, Never>(priority: .userInitiated) { [charger, coteMax] in
                guard let donnees = await charger(url) else { return nil }
                return Self.decoder(donnees, coteMax: coteMax)
            }
            enVol[url] = nouvelle
            return nouvelle
        }
        let image = await tache.value
        verrou.withLock { enVol[url] = nil }
        if let image { cache.setObject(image, forKey: url as NSURL, cost: Self.octets(image)) }
        return image
    }

    /// Décode à la taille voulue au plus, prête à l'affichage (sans décodage paresseux au premier dessin).
    static func decoder(_ donnees: Data, coteMax: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(donnees as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: coteMax,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    static func octets(_ image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 1 }
        return cg.bytesPerRow * cg.height
    }
}
