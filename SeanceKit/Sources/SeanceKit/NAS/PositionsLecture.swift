import Foundation

/// Où l'on s'est arrêté dans une vidéo du NAS (8.0, « Reprendre où tu en étais »).
public struct PositionLecture: Codable, Sendable, Hashable {
    /// Secondes depuis le début.
    public var secondes: Double
    /// Durée de la vidéo, en secondes ; 0 quand le lecteur ne l'a pas encore dite.
    public var duree: Double
    public var majLe: Date
    /// L'appareil où l'on s'est arrêté (« iPad », « Apple TV ») : « Tu t'es arrêté à 1:03:12, sur l'iPad ».
    public var appareil: String?

    public init(secondes: Double, duree: Double, majLe: Date, appareil: String? = nil) {
        self.secondes = secondes
        self.duree = duree
        self.majLe = majLe
        self.appareil = appareil
    }

    /// La part déjà vue, de 0 à 1 ; `nil` sans durée connue.
    public var fraction: Double? {
        duree > 0 ? min(max(secondes / duree, 0), 1) : nil
    }

    /// Ce qui reste, en secondes.
    public var reste: Double? {
        duree > 0 ? max(duree - secondes, 0) : nil
    }
}

/// Les positions de lecture, par chemin de fichier sur le NAS. Elles voyagent dans les réglages synchronisés, sous la clé
/// `cle`, la plus récente l'emportant entrée par entrée — commencé sur l'iPad, repris sur l'Apple TV. Le format reste
/// additif.
public struct PositionsLecture: Codable, Sendable, Hashable {
    public static let cle = "lecture.positions"

    /// 8.9 (bilan de l'Apple TV) : « Reprendre » est propre à chaque personne de la famille, comme sur Netflix. Le
    /// profil principal garde la clé d'avant ; les autres ont la leur.
    public static func cle(profil: String) -> String { profil.isEmpty ? cle : "\(cle).\(profil)" }
    /// En deçà, rien à reprendre : on vient à peine de commencer.
    public static let minimum: Double = 60
    /// Au-delà de 95 % ou à moins de trois minutes de la fin (le générique), la vidéo est vue : on repartira du début.
    public static let finVue: Double = 0.95
    public static let generique: Double = 180
    /// Au plus ce nombre d'entrées : les plus anciennes s'effacent.
    public static let maximum = 200

    public var entrees: [String: PositionLecture]

    public init(entrees: [String: PositionLecture] = [:]) {
        self.entrees = entrees
    }

    public init(donnees: Data?) {
        entrees = donnees.flatMap { try? JSONDecoder().decode(PositionsLecture.self, from: $0) }?.entrees ?? [:]
    }

    public func encoder() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Où reprendre ce fichier, s'il y a lieu : ni au tout début, ni à la fin.
    public func aReprendre(_ chemin: String) -> PositionLecture? {
        guard let position = entrees[chemin], position.secondes >= Self.minimum else { return nil }
        return Self.estFinie(position) ? nil : position
    }

    /// Les vidéos entamées, la plus récente d'abord : la rangée « Reprendre ».
    public var enCours: [(chemin: String, position: PositionLecture)] {
        entrees.compactMap { chemin, position in aReprendre(chemin).map { (chemin, $0) } }
            .sorted { $0.position.majLe > $1.position.majLe }
    }

    /// Retient où l'on s'est arrêté. Une vidéo finie garde son entrée, remise à zéro et datée, pour que les autres
    /// appareils l'apprennent.
    public mutating func noter(_ chemin: String, secondes: Double, duree: Double, appareil: String?, le maintenant: Date = .now) {
        var position = PositionLecture(secondes: max(secondes, 0), duree: max(duree, 0), majLe: maintenant, appareil: appareil)
        if Self.estFinie(position) { position.secondes = 0 }
        entrees[chemin] = position
        if entrees.count > Self.maximum {
            for (chemin, _) in entrees.sorted(by: { $0.value.majLe < $1.value.majLe }).prefix(entrees.count - Self.maximum) {
                entrees[chemin] = nil
            }
        }
    }

    /// « Depuis le début » : la position s'efface, datée, pour tous les appareils.
    public mutating func oublier(_ chemin: String, le maintenant: Date = .now) {
        guard let ancienne = entrees[chemin] else { return }
        entrees[chemin] = PositionLecture(secondes: 0, duree: ancienne.duree, majLe: maintenant, appareil: ancienne.appareil)
    }

    /// Reprend les positions d'un autre appareil plus récentes que les nôtres ; vrai si quelque chose a changé.
    @discardableResult
    public mutating func fusionner(_ autres: PositionsLecture) -> Bool {
        var change = false
        for (chemin, sienne) in autres.entrees where sienne.majLe > (entrees[chemin]?.majLe ?? .distantPast) {
            entrees[chemin] = sienne
            change = true
        }
        return change
    }

    static func estFinie(_ position: PositionLecture) -> Bool {
        guard position.duree > 0 else { return false }
        return position.secondes >= position.duree * finVue || position.duree - position.secondes <= generique
    }

    /// « 1:03:12 », « 12:05 ».
    public static func horodatage(_ secondes: Double) -> String {
        let total = Int(secondes.rounded(.down))
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// « encore 1 h 45 », « encore 31 min ».
    public static func reste(_ secondes: Double) -> String {
        let minutes = Int((secondes / 60).rounded())
        return minutes >= 60 ? "encore \(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "encore \(max(minutes, 1)) min"
    }
}
