import SeanceKit
import SwiftData
import SwiftUI

/// Journal des problèmes rencontrés, affiché dans À propos › Journal. Pas un journal de débogage :
/// une phrase simple, ce que Patrick peut faire, et un court détail technique à transmettre au besoin.
/// Il reste sur l'appareil, sans clé ni mot de passe.
@MainActor
@Observable
final class Journal {
    enum Domaine: String, Codable, CaseIterable {
        case tmdb
        case tele
        case nas
        case lecture
        case alertes
        case claude
        case general
        /// Les arrêts brusques de Séance (8.2), notés au lancement suivant.
        case plantage

        var libelle: String {
            switch self {
            case .tmdb: "Films et séries (TMDB)"
            case .tele: "Programmes TV"
            case .nas: "NAS"
            case .lecture: "Lecture"
            case .alertes: "Alertes"
            case .claude: "Suggestions (Claude)"
            case .general: "Séance"
            case .plantage: "Arrêts de Séance"
            }
        }

        var symbole: String {
            switch self {
            case .tmdb: "film.stack"
            case .tele: "tv"
            case .nas: "externaldrive"
            case .lecture: "play.rectangle"
            case .alertes: "bell"
            case .claude: "sparkles"
            case .general: "exclamationmark.circle"
            case .plantage: "bolt.trianglebadge.exclamationmark"
            }
        }

        var couleur: Color {
            switch self {
            case .tmdb: .teal
            case .tele: .blue
            case .nas: .green
            case .lecture: .purple
            case .alertes: .red
            case .claude: .orange
            case .general: .gray
            case .plantage: .red
            }
        }
    }

    struct Entree: Codable, Identifiable, Hashable {
        var id = UUID()
        var date: Date
        var domaine: Domaine
        var message: String
        var conseil: String?
        var detail: String?
        /// Le même problème répété dans l'heure n'ajoute pas de ligne : il se compte.
        var repetitions = 1
    }

    /// Le journal de l'app, pour ce qui n'a pas l'état sous la main (un enregistrement qui échoue, loin d'un écran).
    nonisolated(unsafe) static weak var courant: Journal?

    private(set) var entrees: [Entree] = []
    private static let maximum = 150

    private var fichier: URL {
        DossiersSeance.reglages.appending(path: "journal.json")
    }

    /// Deux semaines d'entrées au plus (8.2.17, demande de Patrick) : les plus anciennes s'effacent d'elles-mêmes.
    static let conservation: TimeInterval = 14 * 86_400

    init() {
        entrees = (try? JSONDecoder().decode([Entree].self, from: Data(contentsOf: fichier))) ?? []
        Self.courant = self
        oublierLesAnciennes()
    }

    private func oublierLesAnciennes() {
        let limite = Date.now.addingTimeInterval(-Self.conservation)
        let avant = entrees.count
        entrees.removeAll { $0.date < limite }
        if entrees.count != avant { enregistrer() }
    }

    /// Efface les entrées jusqu'à ce jour-là compris.
    func effacer(jusqua jour: Date) {
        let fin = Calendar.current.startOfDay(for: jour).addingTimeInterval(86_400)
        entrees.removeAll { $0.date < fin }
        enregistrer()
    }

    /// Note un problème. Le conseil et le détail sont déduits de l'erreur quand ils ne sont pas donnés.
    func noter(_ domaine: Domaine, _ message: String, erreur: (any Error)? = nil, conseil: String? = nil) {
        let conseilRetenu = conseil ?? erreur.flatMap(Self.conseil)
        let detail = erreur.map(Self.detail)
        if let index = entrees.firstIndex(where: { $0.domaine == domaine && $0.message == message && Date.now.timeIntervalSince($0.date) < 3600 }) {
            entrees[index].repetitions += 1
            entrees[index].date = .now
            entrees[index].detail = detail ?? entrees[index].detail
            let entree = entrees.remove(at: index)
            entrees.insert(entree, at: 0)
        } else {
            entrees.insert(Entree(date: .now, domaine: domaine, message: message, conseil: conseilRetenu, detail: detail), at: 0)
        }
        if entrees.count > Self.maximum { entrees.removeLast(entrees.count - Self.maximum) }
        entrees.removeAll { $0.date < Date.now.addingTimeInterval(-Self.conservation) }
        enregistrer()
    }

    func effacer() {
        entrees = []
        enregistrer()
    }

    /// Recopie les arrêts brusques pas encore notés (`Plantages`), à leur date, avec la version et la page ou le détail
    /// du rapport d'iOS — à me transmettre depuis le partage du journal.
    func noterPlantages() {
        let nouveaux = Plantages.aNoter()
        guard !nouveaux.isEmpty else { return }
        for plantage in nouveaux {
            entrees.insert(Entree(date: plantage.date, domaine: .plantage, message: Plantages.message(plantage),
                                  conseil: "Si cela se répète, partage ce journal : le détail aide à trouver la cause.",
                                  detail: ["Version \(plantage.version)", plantage.detail].compactMap { $0 }.joined(separator: " · ")), at: 0)
        }
        entrees.sort { $0.date > $1.date }
        if entrees.count > Self.maximum { entrees.removeLast(entrees.count - Self.maximum) }
        enregistrer()
    }

    /// Texte à partager, par exemple pour me décrire un problème.
    var texte: String {
        let format = Date.FormatStyle(date: .numeric, time: .shortened, locale: Locale(identifier: "fr_CH"))
        return entrees.map { entree in
            var lignes = ["\(entree.date.formatted(format)) · \(entree.domaine.libelle)\(entree.repetitions > 1 ? " (×\(entree.repetitions))" : "")",
                          entree.message]
            if let conseil = entree.conseil { lignes.append("→ \(conseil)") }
            if let detail = entree.detail { lignes.append("Détail : \(detail)") }
            return lignes.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private func enregistrer() {
        try? FileManager.default.createDirectory(at: DossiersSeance.reglages, withIntermediateDirectories: true)
        try? JSONEncoder().encode(entrees).write(to: fichier, options: .atomic)
    }

    /// Ce que Patrick peut faire, pour les causes les plus courantes.
    static func conseil(_ erreur: any Error) -> String? {
        if let tmdb = erreur as? ErreurTMDB {
            switch tmdb {
            case .identifiantsRefuses: return "Vérifie la clé TMDB dans Réglages › TMDB."
            case .limiteDepassee: return "TMDB limite le nombre de demandes : patiente une minute."
            case .http, .decodage: return "TMDB a répondu de façon inattendue : réessaie plus tard."
            }
        }
        if let url = erreur as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "Vérifie la connexion Internet de l'appareil, puis réessaie."
            case .timedOut, .cannotConnectToHost, .cannotFindHost:
                return "Le service ne répond pas pour l'instant : réessaie un peu plus tard."
            default:
                return nil
            }
        }
        return nil
    }

    /// Une ligne, sans données personnelles : le message de l'erreur, clés et mots de passe masqués.
    static func detail(_ erreur: any Error) -> String {
        masquer(String((erreur as NSError).localizedDescription.prefix(200)))
    }

    static func masquer(_ texte: String) -> String {
        texte
            .replacing(#/api_key=[^&\s]+/#, with: "api_key=•••")
            .replacing(#/sk-ant-[A-Za-z0-9_\-]+/#, with: "sk-ant-•••")
            .replacing(#/smb://[^@\s]+@/#, with: "smb://•••@")
    }
}

extension ModelContext {
    /// Enregistre ; un échec n'est plus avalé en silence : il va au journal d'À propos, avec son détail.
    @MainActor
    func sauver(_ quoi: String = "Un changement") {
        do {
            try save()
        } catch {
            Journal.courant?.noter(.general, "\(quoi) n'a pas pu être enregistré.", erreur: error,
                                   conseil: "Réessaie. Si cela se répète, exporte une sauvegarde depuis Réglages › Sauvegarde.")
        }
    }
}
