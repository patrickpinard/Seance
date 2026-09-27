import Foundation
#if os(iOS)
import MetricKit
#endif

/// Les arrêts brusques de Séance (8.2, demande de Patrick) : on les voyait seulement dans les rapports de l'appareil,
/// lus depuis le Mac. Au lancement, Séance regarde comment la séance précédente s'est terminée : si elle était à
/// l'écran, qu'aucune installation n'est passée entre-temps, c'est un arrêt — noté avec la page ouverte à ce moment-là.
/// Sur l'iPhone, l'iPad et le Mac, iOS transmet en plus, un peu plus tard, le rapport lui-même (MetricKit) : le type
/// d'arrêt et les premières fonctions de la pile. Commun à l'app et à l'Apple TV (sans MetricKit).
@MainActor
enum Plantages {
    struct Plantage: Codable, Hashable, Identifiable, Sendable {
        var id = UUID()
        var date: Date
        var version: String
        /// La page ouverte, d'après la séance ; `nil` pour un rapport d'iOS.
        var page: String?
        /// Le détail technique d'un rapport d'iOS : type d'arrêt, premières fonctions.
        var detail: String?
        /// Déjà recopié dans le journal de l'app.
        var note = false
    }

    private struct Session: Codable {
        var derniere: Date
        var version: String
        var compilation: String?
        var page: String?
        var enFond: Bool
    }

    private static let cleSession = "plantages.session"
    private static let cleListe = "plantages.liste"
    private static let maximum = 20

    private static var version: String {
        let bundle = Bundle.main
        let numero = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(numero) (\(build))"
    }

    private static var compilation: String? {
        Bundle.main.object(forInfoDictionaryKey: "SeanceCompileeLe") as? String
    }

    /// Les arrêts connus, le plus récent d'abord.
    static var liste: [Plantage] {
        (UserDefaults.standard.data(forKey: cleListe).flatMap { try? JSONDecoder().decode([Plantage].self, from: $0) } ?? [])
            .sorted { $0.date > $1.date }
    }

    /// Au lancement, avant tout le reste.
    static func demarrer() {
        let defauts = UserDefaults.standard
        if let brut = defauts.data(forKey: cleSession), let precedente = try? JSONDecoder().decode(Session.self, from: brut),
           !precedente.enFond, precedente.compilation == compilation {
            ajouter(Plantage(date: precedente.derniere, version: precedente.version, page: precedente.page))
        }
        ecrire(Session(derniere: .now, version: version, compilation: compilation, page: nil, enFond: false))
        #if os(iOS)
        MXMetricManager.shared.add(RecepteurRapports.partage)
        #endif
        #if !os(tvOS)
        // L'état de l'app, et son journal, peuvent exister déjà : on y recopie tout de suite l'arrêt trouvé.
        Journal.courant?.noterPlantages()
        #endif
    }

    /// La page à l'écran : ce qu'on dira si Séance s'arrête là.
    static func page(_ nom: String) {
        modifierSession { $0.page = nom }
    }

    /// Séance passe en arrière-plan (un arrêt y est normal : iOS libère la place) ou revient à l'écran.
    static func enFond(_ oui: Bool) {
        modifierSession { $0.enFond = oui }
    }

    static func ajouter(_ plantage: Plantage) {
        var tous = liste
        tous.insert(plantage, at: 0)
        enregistrer(Array(tous.prefix(maximum)))
    }

    /// Ceux que le journal n'a pas encore reçus ; ils y sont marqués notés.
    static func aNoter() -> [Plantage] {
        var tous = liste
        let nouveaux = tous.filter { !$0.note }
        for index in tous.indices { tous[index].note = true }
        if !nouveaux.isEmpty { enregistrer(tous) }
        return nouveaux
    }

    static func effacer() {
        UserDefaults.standard.removeObject(forKey: cleListe)
    }

    /// « Séance s'est arrêtée brusquement (page : Regarder) ».
    static func message(_ plantage: Plantage) -> String {
        if let page = plantage.page { return "Séance s'est arrêtée brusquement, sur la page « \(page) »." }
        return plantage.detail == nil ? "Séance s'est arrêtée brusquement." : "Rapport d'arrêt transmis par le système."
    }

    private static func modifierSession(_ changement: (inout Session) -> Void) {
        var session = UserDefaults.standard.data(forKey: cleSession).flatMap { try? JSONDecoder().decode(Session.self, from: $0) }
            ?? Session(derniere: .now, version: version, compilation: compilation, page: nil, enFond: false)
        changement(&session)
        session.derniere = .now
        ecrire(session)
    }

    private static func ecrire(_ session: Session) {
        UserDefaults.standard.set(try? JSONEncoder().encode(session), forKey: cleSession)
    }

    private static func enregistrer(_ liste: [Plantage]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(liste), forKey: cleListe)
    }
}

#if os(iOS)
/// Les rapports d'arrêt d'iOS, remis au lancement suivant (souvent un peu plus tard) : le type d'arrêt et les premières
/// fonctions de Séance dans la pile, pour me les transmettre depuis le journal.
final class RecepteurRapports: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let partage = RecepteurRapports()

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        var plantages: [Plantages.Plantage] = []
        for payload in payloads {
            for rapport in payload.crashDiagnostics ?? [] {
                var morceaux: [String] = []
                if let type = rapport.exceptionType { morceaux.append("exception \(type)") }
                if let signal = rapport.signal { morceaux.append("signal \(signal)") }
                if let raison = rapport.terminationReason, !raison.isEmpty { morceaux.append(raison) }
                morceaux.append(contentsOf: Self.fonctions(rapport.callStackTree.jsonRepresentation()))
                plantages.append(Plantages.Plantage(date: payload.timeStampEnd, version: rapport.metaData.applicationBuildVersion,
                                                    detail: morceaux.joined(separator: " · ")))
            }
        }
        guard !plantages.isEmpty else { return }
        let recus = plantages
        Task { @MainActor in
            for plantage in recus { Plantages.ajouter(plantage) }
            Journal.courant?.noterPlantages()
        }
    }

    /// Les huit premières images de la pile du fil arrêté : « Seance +0x65e2a4 », « SwiftData +0x1be04 »…
    nonisolated private static func fonctions(_ json: Data) -> [String] {
        guard let arbre = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let piles = arbre["callStacks"] as? [[String: Any]] else { return [] }
        let pile = piles.first { ($0["threadAttributed"] as? Bool) == true } ?? piles.first
        var resultat: [String] = []
        var cadres = pile?["callStackRootFrames"] as? [[String: Any]] ?? []
        while let cadre = cadres.first, resultat.count < 8 {
            let binaire = cadre["binaryName"] as? String ?? "?"
            let decalage = cadre["offsetIntoBinaryTextSegment"] as? Int ?? 0
            resultat.append("\(binaire) +0x\(String(decalage, radix: 16))")
            cadres = cadre["subFrames"] as? [[String: Any]] ?? []
        }
        return resultat
    }
}
#endif
