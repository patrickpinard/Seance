import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

// « À venir » dans l'esprit du programme TV : une rangée de jours, et chaque rendez-vous en grande carte.

/// Un rendez-vous : ce qui arrive, et quand.
struct CarteEcheance: View {
    let echeance: Echeance
    let decor: EtatDecors.Decor?

    private static let locale = Locale(identifier: "fr_CH")

    private var jours: Int {
        let calendrier = Calendar.current
        return calendrier.dateComponents([.day], from: calendrier.startOfDay(for: .now), to: calendrier.startOfDay(for: echeance.date)).day ?? 0
    }

    private var compteARebours: String {
        switch jours {
        case ..<1: "Aujourd'hui"
        case 1: "Demain"
        default: "Dans \(jours) j"
        }
    }

    private var date: String {
        let texte = echeance.date.formatted(.dateTime.weekday(.abbreviated).day().month(.wide).locale(Self.locale))
        return texte.prefix(1).uppercased() + texte.dropFirst()
    }

    /// 8.7 : la carte commune de la charte (ligne d'origine, titre, ▶︎), comme sur l'Apple TV — plus de badge orange
    /// « AUJOURD'HUI », de contour orange ni de pastilles ; la date et le compte à rebours sont dans la ligne d'origine.
    var body: some View {
        NavigationLink(value: echeance.reference) {
            CarteLargeTitre(echeance: echeance, quand: "\(date) · \(compteARebours.lowercased())")
        }
        .buttonStyle(.plain)
    }
}

/// L'onglet « À venir » de Mes listes, dans un défilement libre (pas dans une `List`, qui ouvrait plusieurs liens à la fois) : la rangée des jours où il se passe quelque chose, puis les rendez-vous en grandes cartes, le plus proche en tête.
struct SectionAVenir: View {
    /// Les rendez-vous à partir d'aujourd'hui, déjà filtrés par la recherche, triés par date.
    let echeances: [Echeance]

    @Environment(EtatApp.self) private var etat
    /// Le jour choisi, à minuit ; `nil` : le plus proche.
    @State private var jourChoisi: Date?

    private static let locale = Locale(identifier: "fr_CH")

    private var parJour: [Date: [Echeance]] {
        Dictionary(grouping: echeances) { Calendar.current.startOfDay(for: $0.date) }
    }

    var body: some View {
        let parJour = parJour
        let jours = parJour.keys.sorted()
        // Toujours un jour à la fois, le plus proche d'office : « Tout » répétait la même série autant de fois qu'elle passe
        // dans la semaine (NCIS chaque soir sur W9), et noyait le reste.
        let jour = jourChoisi.flatMap { parJour[$0] == nil ? nil : $0 } ?? jours.first
        let affichees = jour.flatMap { parJour[$0] } ?? []

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(jours, id: \.self) { date in
                    let nombre = parJour[date]?.count ?? 0
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { jourChoisi = date }
                    } label: {
                        TuileJour(nom: nomCourt(date), numero: Calendar.current.component(.day, from: date),
                                  detail: detail(date, nombre: nombre), actif: date == jour)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Self.locale))), \(Format.pluriel(nombre, "rendez-vous", "rendez-vous"))")
                    .accessibilityAddTraits(date == jour ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }

        LazyVGrid(columns: CarteLargeTitre.colonnes, spacing: 14) {
            ForEach(affichees) { echeance in
                CarteEcheance(echeance: echeance, decor: etat.decors.decor(echeance.reference))
            }
        }
        .padding(.horizontal, 16)
        .task(id: echeances.map(\.reference)) { await etat.decors.charger(echeances.map(\.reference), client: etat.tmdb) }
    }

    private func nomCourt(_ date: Date) -> String {
        let calendrier = Calendar.current
        if calendrier.isDateInToday(date) { return "Auj." }
        if calendrier.isDateInTomorrow(date) { return "Demain" }
        return date.formatted(.dateTime.weekday(.abbreviated).locale(Self.locale)).capitalized
    }

    /// Dans la semaine, le nombre de rendez-vous ; plus loin, le mois, sans lequel « 14 » ne dit rien.
    private func detail(_ date: Date, nombre: Int) -> String {
        let calendrier = Calendar.current
        let jours = calendrier.dateComponents([.day], from: calendrier.startOfDay(for: .now), to: date).day ?? 0
        guard jours > 6 else { return Format.pluriel(nombre, "titre") }
        let mois = date.formatted(.dateTime.month(.abbreviated).locale(Self.locale))
        return nombre > 1 ? "\(mois) · \(nombre)" : mois
    }
}
