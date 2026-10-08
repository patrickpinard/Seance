import AVFoundation
import CryptoKit
import SeanceKit
import SeanceNAS
import SwiftUI

/// La première image de chaque vidéo personnelle (6.4). Quarante souvenirs qui portent tous la même icône ne se
/// distinguent pas : une image tirée de la vidéo elle-même, oui.
///
/// 8.11 : le Mac, centrale de la maison, les fabrique et les dépose sur le NAS, dans le dossier caché
/// `.seance-vignettes` du partage des souvenirs ; l'iPhone, l'iPad et l'Apple TV les y lisent (une petite image) au lieu
/// de relire le début de chaque vidéo. Celle qui manque encore est fabriquée sur place, puis déposée pour les autres.
/// Chacun la garde aussi sur l'appareil. Rien ne quitte la maison.
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
    /// Les noms des vignettes déjà sur le NAS, lus une fois : une vignette absente n'est pas cherchée en vain.
    @ObservationIgnored private var surLeNAS: Set<String>?
    static let dossierNAS = ".seance-vignettes"

    /// Où les images sont gardées entre deux lancements.
    private static var dossier: URL? {
        guard let base = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        else { return nil }
        let dossier = base.appendingPathComponent("VignettesSouvenirs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        return dossier
    }

    /// Le nom d'une vignette : une empreinte du chemin, la même d'un lancement et d'un appareil à l'autre. 8.11 :
    /// `hashValue` changeait à chaque lancement — la vignette gardée sur l'appareil ne se retrouvait jamais.
    static func nom(_ chemin: String, instant: Double? = nil) -> String {
        let empreinte = SHA256.hash(data: Data(chemin.precomposedStringWithCanonicalMapping.utf8)).prefix(12)
            .map { String(format: "%02x", $0) }.joined()
        return empreinte + (instant.map { "-\(Int($0))" } ?? "") + ".jpg"
    }

    private static func fichier(_ chemin: String, instant: Double? = nil) -> URL? {
        dossier?.appendingPathComponent(nom(chemin, instant: instant))
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
        Task {
            if await lireSurLeNAS(video, acces: acces, motDePasse: motDePasse, instant: instant) { return }
            await produire(video, acces: acces, motDePasse: motDePasse, instant: instant, deposer: true)
        }
    }

    /// La vignette déposée sur le NAS par le Mac ou un autre appareil.
    private func lireSurLeNAS(_ video: VideoPerso, acces: ReglagesNAS, motDePasse: String, instant: Double?) async -> Bool {
        let nom = Self.nom(video.chemin, instant: instant)
        let presents = await nomsSurLeNAS(acces: acces, motDePasse: motDePasse)
        guard presents.contains(nom),
              let donnees = try? await DossierSynchroSMB(reglages: acces, motDePasse: motDePasse, dossier: Self.dossierNAS).lire(nom),
              let image = UIImage(data: donnees) else { return false }
        vignettes[video.chemin] = Image(uiImage: image)
        if let fichier = Self.fichier(video.chemin, instant: instant) { try? donnees.write(to: fichier, options: .atomic) }
        return true
    }

    private func nomsSurLeNAS(acces: ReglagesNAS, motDePasse: String) async -> Set<String> {
        if let surLeNAS { return surLeNAS }
        let lus = Set(((try? await DossierSynchroSMB(reglages: acces, motDePasse: motDePasse, dossier: Self.dossierNAS).lister()) ?? []).map(\.nom))
        surLeNAS = lus
        return lus
    }

    /// Le Mac, à chaque passage de la centrale (8.11) : les vignettes qui manquent sur le NAS, quelques-unes à la fois
    /// pour ne pas occuper le NAS des heures. Renvoie le nombre de vignettes déposées.
    @discardableResult
    func preparerSurLeNAS(_ videos: [VideoPerso], acces: ReglagesNAS, motDePasse: String, maximum: Int = 20) async -> Int {
        surLeNAS = nil
        let presents = await nomsSurLeNAS(acces: acces, motDePasse: motDePasse)
        var deposees = 0
        for video in videos where Self.possible(video.chemin) {
            guard deposees < maximum, !Task.isCancelled else { break }
            let instant = instantDe?(video.chemin)
            guard !presents.contains(Self.nom(video.chemin, instant: instant)) else { continue }
            if await produire(video, acces: acces, motDePasse: motDePasse, instant: instant, deposer: true) { deposees += 1 }
        }
        return deposees
    }

    /// Deux vidéos à la fois au plus : chaque image demande d'ouvrir une connexion SMB et de lire le début du fichier.
    @discardableResult
    private func produire(_ video: VideoPerso, acces: ReglagesNAS, motDePasse: String, instant: Double?, deposer: Bool) async -> Bool {
        while enCours >= 2 { try? await Task.sleep(for: .milliseconds(250)) }
        enCours += 1
        defer { enCours -= 1 }
        let source = SourceVideoSMB(reglages: acces, motDePasse: motDePasse, chemin: video.chemin)
        await source.ouvrir()
        let extension_ = (video.chemin as NSString).pathExtension.lowercased()
        let relais = RelaisVideo(source: source, typeMIME: extension_ == "mp4" ? "video/mp4" : "video/quicktime")
        defer { Task { await relais.arreter(); await source.fermer() } }
        guard let adresse = try? await relais.demarrer() else { return false }
        let asset = AVURLAsset(url: adresse)
        let generateur = AVAssetImageGenerator(asset: asset)
        generateur.appliesPreferredTrackTransform = true
        generateur.maximumSize = CGSize(width: 640, height: 640)
        // Une seconde après le début : la toute première image est souvent noire. Ou l'image choisie (8.2).
        guard let image = try? await generateur.image(at: CMTime(seconds: instant ?? 1, preferredTimescale: 600)).image else { return false }
        let uiImage = UIImage(cgImage: image)
        vignettes[video.chemin] = Image(uiImage: uiImage)
        guard let donnees = uiImage.jpegData(compressionQuality: 0.7) else { return true }
        if let fichier = Self.fichier(video.chemin, instant: instant) { try? donnees.write(to: fichier, options: .atomic) }
        // Pour les autres appareils : déposée sur le NAS, à côté des souvenirs.
        if deposer {
            let nom = Self.nom(video.chemin, instant: instant)
            if (try? await DossierSynchroSMB(reglages: acces, motDePasse: motDePasse, dossier: Self.dossierNAS).ecrire(donnees, nom: nom)) != nil {
                surLeNAS?.insert(nom)
            }
        }
        return true
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
