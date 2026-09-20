import Foundation

/// Le second accès au NAS, pour les vidéos personnelles (EF-157) : facultatif — une case à cocher —, et à part de la
/// bibliothèque de films. Le même NAS et un autre partage le plus souvent ; un autre serveur si on veut.
public struct ReglagesVideosPerso: Codable, Sendable, Hashable {
    /// La case à cocher : décochée, rien n'apparaît dans l'app.
    public var actif: Bool
    public var acces: ReglagesNAS

    public init(actif: Bool = false, acces: ReglagesNAS = ReglagesNAS(partage: "video", dossiers: [])) {
        self.actif = actif
        self.acces = acces
    }

    /// Prérempli avec le NAS des films : même adresse, même compte, partage « video », tous ses dossiers.
    public static func depuis(_ films: ReglagesNAS) -> ReglagesVideosPerso {
        ReglagesVideosPerso(acces: ReglagesNAS(hote: films.hote, partage: "video", dossiers: [], utilisateur: films.utilisateur))
    }

    /// Des dossiers vides veulent dire « tout le partage » : ici, contrairement aux films, ce n'est pas un manque.
    public var estComplet: Bool { !acces.hote.isEmpty && !acces.partage.isEmpty && !acces.utilisateur.isEmpty }

    /// Même serveur et même compte que les films : le mot de passe des films sert aussi, sans le redemander.
    public func partageLeCompte(de films: ReglagesNAS) -> Bool {
        acces.hote.caseInsensitiveCompare(films.hote) == .orderedSame && acces.utilisateur == films.utilisateur
    }
}

/// Une vidéo personnelle : son chemin dans le partage, sa taille, sa date. Privée (EF-158) : son nom ne part vers aucun
/// service, et elle n'entre ni dans les statistiques ni dans les goûts.
public struct VideoPerso: Codable, Sendable, Hashable, Identifiable {
    public var chemin: String
    public var taille: Int64
    public var modifieLe: Date?

    public init(chemin: String, taille: Int64, modifieLe: Date? = nil) {
        self.chemin = chemin
        self.taille = taille
        self.modifieLe = modifieLe
    }

    public var id: String { chemin }
    /// « Noël 2023.mov » → « Noël 2023 ».
    public var nom: String { ((chemin as NSString).lastPathComponent as NSString).deletingPathExtension }
    public var dossier: String { (chemin as NSString).deletingLastPathComponent }
}

/// Les vidéos personnelles se parcourent comme sur le NAS : par dossiers (année, événement), le plus récent d'abord.
public struct ArbreVideosPerso: Sendable {
    public struct Dossier: Sendable, Hashable, Identifiable {
        public let chemin: String
        public let nombre: Int
        public let plusRecente: Date?
        public var id: String { chemin }
        public var nom: String { (chemin as NSString).lastPathComponent }
    }

    public let videos: [VideoPerso]

    public init(_ videos: [VideoPerso]) {
        self.videos = videos
    }

    /// Les sous-dossiers directs de `chemin` (« » pour la racine), du plus récemment alimenté au plus ancien.
    public func dossiers(dans chemin: String) -> [Dossier] {
        let prefixe = chemin.isEmpty ? "" : chemin + "/"
        var parNom: [String: (nombre: Int, date: Date?)] = [:]
        for video in videos where video.chemin.hasPrefix(prefixe) {
            let reste = video.chemin.dropFirst(prefixe.count).split(separator: "/", omittingEmptySubsequences: true)
            guard reste.count > 1 else { continue }
            let nom = String(reste[0])
            let connu = parNom[nom]
            let date = [connu?.date, video.modifieLe].compactMap { $0 }.max()
            parNom[nom] = ((connu?.nombre ?? 0) + 1, date)
        }
        return parNom.map { Dossier(chemin: prefixe + $0.key, nombre: $0.value.nombre, plusRecente: $0.value.date) }
            .sorted { ($0.plusRecente ?? .distantPast, $1.nom) > ($1.plusRecente ?? .distantPast, $0.nom) }
    }

    /// Les vidéos rangées directement dans `chemin`, de la plus récente à la plus ancienne.
    public func videos(dans chemin: String) -> [VideoPerso] {
        videos.filter { $0.dossier == chemin }
            .sorted { ($0.modifieLe ?? .distantPast, $1.nom) > ($1.modifieLe ?? .distantPast, $0.nom) }
    }

    /// Les dernières arrivées, tous dossiers confondus.
    public func recentes(_ nombre: Int) -> [VideoPerso] {
        videos.sorted { ($0.modifieLe ?? .distantPast) > ($1.modifieLe ?? .distantPast) }.prefix(nombre).map { $0 }
    }
}
