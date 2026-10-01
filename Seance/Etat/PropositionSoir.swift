import Foundation
import SeanceKit

/// « Pas ce soir » sur l'accueil (8.1) : le titre ne revient dans la proposition que le lendemain matin (6 h). Commun
/// à l'app et à l'Apple TV (`project.yml`), comme `PasInteresse`.
enum PasCeSoir {
    static let cle = "accueil.pasCeSoir"

    private static func lire(_ brut: String) -> [String: Double] {
        (try? JSONDecoder().decode([String: Double].self, from: Data(brut.utf8))) ?? [:]
    }

    private static func cle(_ reference: ReferenceTitre) -> String { "\(reference.type.rawValue):\(reference.tmdbID)" }

    static func references(_ brut: String, maintenant: Date = .now) -> Set<ReferenceTitre> {
        Set(lire(brut).compactMap { cle, jusquA -> ReferenceTitre? in
            guard jusquA > maintenant.timeIntervalSince1970 else { return nil }
            let morceaux = cle.split(separator: ":")
            guard morceaux.count == 2, let type = TypeTitre(rawValue: String(morceaux[0])), let id = Int(morceaux[1]) else { return nil }
            return ReferenceTitre(type: type, tmdbID: id)
        })
    }

    static func ecarter(_ reference: ReferenceTitre, maintenant: Date = .now) {
        var liste = lire(UserDefaults.standard.string(forKey: cle) ?? "").filter { $0.value > maintenant.timeIntervalSince1970 }
        liste[Self.cle(reference)] = demainMatin(maintenant).timeIntervalSince1970
        UserDefaults.standard.set(String(data: (try? JSONEncoder().encode(liste)) ?? Data(), encoding: .utf8), forKey: cle)
    }

    /// 6 h le lendemain, ou ce matin à 6 h pour un « pas ce soir » dit après minuit.
    static func demainMatin(_ maintenant: Date) -> Date {
        let calendrier = Calendar.current
        let sixHeures = calendrier.date(bySettingHour: 6, minute: 0, second: 0, of: maintenant) ?? maintenant
        return sixHeures > maintenant ? sixHeures : calendrier.date(byAdding: .day, value: 1, to: sixHeures) ?? sixHeures
    }
}

/// Les faits d'une vidéo entamée, sous le titre de la proposition (8.1) : les mêmes mots sur l'iPhone, l'iPad, le Mac
/// et l'Apple TV.
enum LibellesProposition {
    /// « 2 h 46 », « 52 min ».
    static func duree(_ secondes: Double) -> String {
        let minutes = Int((secondes / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(max(minutes, 1)) min"
    }

    /// « commencé jeudi sur l'iPhone », « commencé hier sur le Mac ».
    static func commence(_ position: PositionLecture, maintenant: Date = .now) -> String {
        let calendrier = Calendar.current
        let quand: String
        if calendrier.isDateInToday(position.majLe) {
            quand = "aujourd'hui"
        } else if calendrier.isDateInYesterday(position.majLe) {
            quand = "hier"
        } else if let jours = calendrier.dateComponents([.day], from: position.majLe, to: maintenant).day, jours < 7 {
            quand = position.majLe.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "fr_CH")))
        } else {
            quand = "le " + position.majLe.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_CH")))
        }
        guard let appareil = position.appareil else { return "commencé \(quand)" }
        let article = appareil.first.map { "aeiouyAEIOUY".contains($0) } == true ? "l'" : "le "
        return "commencé \(quand) sur \(article)\(appareil)"
    }

    /// « Film · 2 h 46 · commencé jeudi sur l'iPhone », « S2 E5 · 52 min · commencé hier ».
    static func reprise(film: Bool, saison: Int?, episode: Int?, position: PositionLecture) -> String {
        let episodeLu = [saison.map { "S\($0)" }, episode.map { "E\($0)" }].compactMap { $0 }.joined(separator: " ")
        let quoi = film ? "Film" : (episodeLu.isEmpty ? "Série" : episodeLu)
        return [quoi, position.duree > 0 ? duree(position.duree) : nil, commence(position)].compactMap { $0 }.joined(separator: " · ")
    }
}


/// Combien de propositions du soir défilent en tête de l'accueil (8.6) : 1, 3, 5 ou 8. Réglé dans Préférences › Accueil
/// sur l'iPhone, l'iPad ou le Mac ; la valeur voyage dans les réglages synchronisés, jusqu'à l'Apple TV.
enum NombrePropositions {
    static let cle = "accueil.propositions"
    /// Sur l'Apple TV (8.7) : le nombre a été choisi sur la TV même, la synchronisation ne le remplace plus.
    static let cleChoisiIci = "accueil.propositions.choisiIci"
    static let parDefaut = 5
    static let choix = [1, 3, 5, 8]
}

/// Le message du lecteur pendant que le NAS ouvre la vidéo (8.8, Patrick : « sois un peu plus explicite ») — le même
/// sur l'iPhone, l'iPad et l'Apple TV.
enum ChargementNAS {
    /// Au-delà, le message dit que le NAS se réveille.
    static let attenteLongue: Duration = .seconds(8)

    /// « Chargement du film depuis le NAS », de l'épisode, ou de la vidéo pour un souvenir.
    static func titre(film: Bool?, episode: Bool) -> String {
        guard let film else { return "Chargement de la vidéo depuis le NAS" }
        return film ? "Chargement du film depuis le NAS" : episode ? "Chargement de l'épisode depuis le NAS" : "Chargement depuis le NAS"
    }

    static func detail(longue: Bool) -> String {
        longue ? "Le NAS se réveille, encore un instant…" : "Patiente quelques secondes…"
    }
}
