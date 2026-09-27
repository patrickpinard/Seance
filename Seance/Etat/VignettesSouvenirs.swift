import AVFoundation
import SeanceKit
import SeanceNAS
import SwiftUI

/// La première image de chaque vidéo personnelle (6.4). Quarante souvenirs qui portent tous la même icône ne se
/// distinguent pas : une image tirée de la vidéo elle-même, oui. Elle est lue une fois, à travers le relais local
/// qui sert déjà la lecture, puis gardée sur l'appareil — jamais sur le NAS, jamais envoyée ailleurs.
///
/// Seuls les formats qu'AVFoundation ouvre donnent une image (MP4, M4V, MOV) ; un AVI ou un WMV garde son icône.
@MainActor
@Observable
final class VignettesSouvenirs {
    /// Chemin de la vidéo → image prête à afficher.
    private(set) var vignettes: [String: Image] = [:]
    /// Les chemins déjà demandés, réussis ou non : une vidéo sans image n'est pas redemandée à chaque défilement.
    private var demandes: Set<String> = []
    private var enCours = 0
    /// L'image choisie dans chaque vidéo (8.2), en secondes ; `nil` : une seconde après le début.
    @ObservationIgnored var instantDe: ((String) -> Double?)?

    /// Où les images sont gardées entre deux lancements.
    private static var dossier: URL? {
        guard let base = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        else { return nil }
        let dossier = base.appendingPathComponent("VignettesSouvenirs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        return dossier
    }

    private static func fichier(_ chemin: String, instant: Double? = nil) -> URL? {
        // Le chemin d'une vidéo contient des « / » et des accents : on le réduit à une empreinte stable.
        let nom = String(format: "%016llx", UInt64(bitPattern: Int64(chemin.hashValue)))
        return dossier?.appendingPathComponent(nom + (instant.map { "-\(Int($0))" } ?? "") + ".jpg")
    }

    /// Les formats dont AVFoundation sait tirer une image : les mêmes qu'il sait lire.
    static let formats: Set<String> = ["mp4", "m4v", "mov", "qt"]

    /// Vrai quand Séance peut tirer une image de ce fichier.
    static func possible(_ chemin: String) -> Bool {
        formats.contains((chemin as NSString).pathExtension.lowercased())
    }

    /// Demande la vignette d'une vidéo. Sans effet si elle est déjà là, déjà demandée, ou si le format s'y refuse.
    func demander(_ video: VideoPerso, acces: ReglagesNAS, motDePasse: String?) {
        guard vignettes[video.chemin] == nil, !demandes.contains(video.chemin),
              Self.possible(video.chemin), let motDePasse, !motDePasse.isEmpty
        else { return }
        demandes.insert(video.chemin)
        // Sur le disque depuis un autre lancement : rien à relire sur le NAS.
        let instant = instantDe?(video.chemin)
        if let fichier = Self.fichier(video.chemin, instant: instant), let donnees = try? Data(contentsOf: fichier),
           let image = UIImage(data: donnees) {
            vignettes[video.chemin] = Image(uiImage: image)
            return
        }
        Task { await produire(video, acces: acces, motDePasse: motDePasse, instant: instant) }
    }

    /// Deux vidéos à la fois au plus : chaque image demande d'ouvrir une connexion SMB et de lire le début du fichier.
    private func produire(_ video: VideoPerso, acces: ReglagesNAS, motDePasse: String, instant: Double?) async {
        while enCours >= 2 { try? await Task.sleep(for: .milliseconds(250)) }
        enCours += 1
        defer { enCours -= 1 }
        let source = SourceVideoSMB(reglages: acces, motDePasse: motDePasse, chemin: video.chemin)
        await source.ouvrir()
        let extension_ = (video.chemin as NSString).pathExtension.lowercased()
        let relais = RelaisVideo(source: source, typeMIME: extension_ == "mp4" ? "video/mp4" : "video/quicktime")
        defer { Task { await relais.arreter(); await source.fermer() } }
        guard let adresse = try? await relais.demarrer() else { return }
        let asset = AVURLAsset(url: adresse)
        let generateur = AVAssetImageGenerator(asset: asset)
        generateur.appliesPreferredTrackTransform = true
        generateur.maximumSize = CGSize(width: 640, height: 640)
        // Une seconde après le début : la toute première image est souvent noire. Ou l'image choisie (8.2).
        guard let image = try? await generateur.image(at: CMTime(seconds: instant ?? 1, preferredTimescale: 600)).image else { return }
        let uiImage = UIImage(cgImage: image)
        vignettes[video.chemin] = Image(uiImage: uiImage)
        if let fichier = Self.fichier(video.chemin, instant: instant), let donnees = uiImage.jpegData(compressionQuality: 0.7) {
            try? donnees.write(to: fichier, options: .atomic)
        }
    }

    /// Une autre image a été choisie pour cette vidéo : la vignette se refait à la prochaine demande.
    func oublier(_ chemin: String) {
        vignettes[chemin] = nil
        demandes.remove(chemin)
    }

    /// Six images prises à travers la vidéo, pour choisir celle qui la représente (8.2, feuille « Couverture »).
    func apercus(_ video: VideoPerso, acces: ReglagesNAS, motDePasse: String, nombre: Int = 6) async -> [(secondes: Double, image: Image)] {
        let source = SourceVideoSMB(reglages: acces, motDePasse: motDePasse, chemin: video.chemin)
        await source.ouvrir()
        let extension_ = (video.chemin as NSString).pathExtension.lowercased()
        let relais = RelaisVideo(source: source, typeMIME: extension_ == "mp4" ? "video/mp4" : "video/quicktime")
        defer { Task { await relais.arreter(); await source.fermer() } }
        guard let adresse = try? await relais.demarrer() else { return [] }
        let asset = AVURLAsset(url: adresse)
        guard let duree = try? await asset.load(.duration).seconds, duree.isFinite, duree > 2 else { return [] }
        let generateur = AVAssetImageGenerator(asset: asset)
        generateur.appliesPreferredTrackTransform = true
        generateur.maximumSize = CGSize(width: 480, height: 480)
        var resultat: [(secondes: Double, image: Image)] = []
        for rang in 0..<nombre {
            // De 5 % à 90 % de la vidéo, à intervalles réguliers.
            let secondes = (duree * (0.05 + 0.85 * Double(rang) / Double(max(nombre - 1, 1)))).rounded()
            guard !Task.isCancelled else { break }
            if let image = try? await generateur.image(at: CMTime(seconds: secondes, preferredTimescale: 600)).image {
                resultat.append((secondes, Image(uiImage: UIImage(cgImage: image))))
            }
        }
        return resultat
    }

    /// Vide les images gardées : l'utilisateur le demande depuis Réglages › Vidéos personnelles.
    func oublier() {
        vignettes = [:]
        demandes = []
        if let dossier = Self.dossier { try? FileManager.default.removeItem(at: dossier) }
    }
}
