import Foundation
import Observation
import SeanceKit
import SeanceNAS

/// Les vidéos personnelles (EF-157 à EF-163) : un second accès au NAS, facultatif, à part de la bibliothèque de films.
/// Partagé par l'app de l'iPhone et celle de l'Apple TV. Rien ici ne parle à TMDB ni à aucun service : ces vidéos sont
/// privées, et leur liste ne vit que dans le cache de l'appareil.
@MainActor
@Observable
final class EtatVideosPerso {
    private let coffre: any CoffreCles
    private(set) var reglages: ReglagesVideosPerso
    private(set) var videos: [VideoPerso] = []
    private(set) var enCours = false
    private(set) var erreur: String?
    private(set) var derniereLecture: Date?

    static let cleReglages = "videos.reglages"
    private static let cleLecture = "videos.derniereLecture"
    private static var cache: URL { URL.cachesDirectory.appending(path: "videos-perso.json") }

    init(coffre: any CoffreCles) {
        self.coffre = coffre
        let defauts = UserDefaults.standard
        reglages = defauts.data(forKey: Self.cleReglages).flatMap { try? JSONDecoder().decode(ReglagesVideosPerso.self, from: $0) } ?? ReglagesVideosPerso()
        derniereLecture = defauts.object(forKey: Self.cleLecture) as? Date
        videos = (try? Data(contentsOf: Self.cache)).flatMap { try? JSONDecoder().decode([VideoPerso].self, from: $0) } ?? []
        #if DEBUG
        if Demonstration.active, !Demonstration.vide {
            reglages = ReglagesVideosPerso(actif: true, acces: ReglagesNAS(partage: "video", dossiers: []))
            videos = Self.exemples
        }
        #endif
    }

    var actif: Bool { reglages.actif }
    var arbre: ArbreVideosPerso { ArbreVideosPerso(videos) }

    /// `aConfigurer` : la case est cochée, mais l'accès n'est pas utilisable.
    func aConfigurer(films: ReglagesNAS) -> Bool {
        reglages.actif && (!reglages.estComplet || motDePasse(films: films) == nil)
    }

    /// Son propre mot de passe ; à défaut, celui des films quand c'est le même serveur et le même compte.
    func motDePasse(films: ReglagesNAS) -> String? {
        if let propre = (try? coffre.lire(.nasVideos)) ?? nil, !propre.isEmpty { return propre }
        return reglages.partageLeCompte(de: films) ? ((try? coffre.lire(.nas)) ?? nil) : nil
    }

    var aSonMotDePasse: Bool { ((try? coffre.lire(.nasVideos)) ?? nil)?.isEmpty == false }

    /// `motDePasse` vide : on garde celui qui est déjà là.
    func enregistrer(_ nouveaux: ReglagesVideosPerso, motDePasse: String = "") {
        let accesChange = nouveaux.acces != reglages.acces
        reglages = nouveaux
        UserDefaults.standard.set(try? JSONEncoder().encode(nouveaux), forKey: Self.cleReglages)
        if !motDePasse.isEmpty { try? coffre.enregistrer(motDePasse, pour: .nasVideos) }
        // Décoché, ou pointé ailleurs : ce qui a été lu avant n'a plus à traîner sur l'appareil.
        if !nouveaux.actif || accesChange { oublier() }
    }

    func supprimerMotDePasse() { try? coffre.supprimer(.nasVideos) }

    private func oublier() {
        videos = []
        derniereLecture = nil
        try? FileManager.default.removeItem(at: Self.cache)
        UserDefaults.standard.removeObject(forKey: Self.cleLecture)
    }

    /// Lit le partage. `force` : le bouton des réglages ; sinon, une fois par heure suffit.
    func lire(films: ReglagesNAS, force: Bool = false) async {
        #if DEBUG
        if Demonstration.active { return }
        #endif
        guard reglages.actif, reglages.estComplet, !enCours else { return }
        if !force, let derniereLecture, Date.now.timeIntervalSince(derniereLecture) < 3600 { return }
        guard let motDePasse = motDePasse(films: films) else { erreur = "Le mot de passe de cet accès manque."; return }
        enCours = true
        erreur = nil
        defer { enCours = false }
        do {
            videos = try await ExplorateurSMB(reglages: reglages.acces, motDePasse: motDePasse).listerVideosPerso(dossiers: reglages.acces.dossiers)
            derniereLecture = .now
            UserDefaults.standard.set(Date.now, forKey: Self.cleLecture)
            try? JSONEncoder().encode(videos).write(to: Self.cache, options: .atomic)
        } catch is CancellationError {
            return
        } catch {
            self.erreur = ErreurNAS.message(error)
        }
    }

    /// Une vidéo personnelle n'a pas de fiche TMDB : Infuse, qui n'ouvre par lien que les titres de sa bibliothèque, ne
    /// sait pas la lire ainsi. Elle passe donc par VLC, qui lit le fichier à son adresse — seule exception au lecteur
    /// unique. Sur le Mac, l'adresse SMB s'ouvre dans le lecteur du système.
    func lien(pour video: VideoPerso, films: ReglagesNAS) -> URL? {
        #if targetEnvironment(macCatalyst)
        let monte = URL(filePath: "/Volumes").appending(path: reglages.acces.partage).appending(path: video.chemin)
        if FileManager.default.fileExists(atPath: monte.path(percentEncoded: false)) { return monte }
        return reglages.acces.url(chemin: video.chemin)
        #else
        guard let motDePasse = motDePasse(films: films), let adresse = reglages.acces.url(chemin: video.chemin, motDePasse: motDePasse) else { return nil }
        return LecteurVideo.vlc.lien(pour: adresse)
        #endif
    }

    #if DEBUG
    private static var exemples: [VideoPerso] {
        func il(_ jours: Int) -> Date { Date.now.addingTimeInterval(TimeInterval(-jours * 86_400)) }
        return [
            VideoPerso(chemin: "2026/Vacances d'été/Plage, premier jour.mov", taille: 1_450_000_000, modifieLe: il(40)),
            VideoPerso(chemin: "2026/Vacances d'été/Coucher de soleil.mov", taille: 620_000_000, modifieLe: il(38)),
            VideoPerso(chemin: "2026/Anniversaire de Camille.mp4", taille: 2_100_000_000, modifieLe: il(12)),
            VideoPerso(chemin: "2025/Noël/Le sapin.mov", taille: 980_000_000, modifieLe: il(270)),
            VideoPerso(chemin: "2025/Noël/Ouverture des cadeaux.mov", taille: 3_300_000_000, modifieLe: il(269)),
            VideoPerso(chemin: "2025/Ski à Verbier.mp4", taille: 1_800_000_000, modifieLe: il(220)),
            VideoPerso(chemin: "Film de famille 2010-2020.mp4", taille: 5_400_000_000, modifieLe: il(900)),
        ]
    }
    #endif
}
