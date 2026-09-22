import Foundation

/// Terminés, rangés par mois (6.1) : le mois où tu as fini chaque titre — son dernier visionnage —, du plus récent au
/// plus ancien, et dans chaque mois le plus récent d'abord. Un titre sans date connue (« déjà vu avant », rangé à la
/// main dans Terminés) va dans « Plus tôt », à la fin.
public enum TerminesParMois {
    public struct Groupe<Element> {
        /// « Septembre 2026 », ou « Plus tôt ».
        public let titre: String
        /// Le premier jour du mois ; `nil` pour « Plus tôt ».
        public let mois: Date?
        public let elements: [Element]
    }

    public static func grouper<Element>(
        _ elements: [Element], fini: (Element) -> Date?, calendrier: Calendar = .current
    ) -> [Groupe<Element>] {
        var parMois: [Date: [(Element, Date)]] = [:]
        var sansDate: [Element] = []
        for element in elements {
            guard let date = fini(element), let debut = calendrier.dateInterval(of: .month, for: date)?.start else {
                sansDate.append(element)
                continue
            }
            parMois[debut, default: []].append((element, date))
        }
        var groupes = parMois.keys.sorted(by: >).map { mois in
            Groupe(titre: libelle(mois, calendrier: calendrier), mois: mois,
                   elements: parMois[mois, default: []].sorted { $0.1 > $1.1 }.map(\.0))
        }
        if !sansDate.isEmpty { groupes.append(Groupe(titre: "Plus tôt", mois: nil, elements: sansDate)) }
        return groupes
    }

    /// « Septembre 2026 », avec la majuscule d'un titre.
    static func libelle(_ mois: Date, calendrier: Calendar) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "fr_CH")
        format.calendar = calendrier
        format.timeZone = calendrier.timeZone
        format.dateFormat = "LLLL yyyy"
        let texte = format.string(from: mois)
        return texte.prefix(1).uppercased() + texte.dropFirst()
    }
}
