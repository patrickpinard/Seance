import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

// « À venir » dans l'esprit du programme TV : une rangée de jours, et chaque rendez-vous en grande carte.

/// « ÉPISODE », « SAISON », « SORTIE », « TÉLÉ » : ce qui arrive, lisible sur une image.
private struct PastilleNature: View {
    let nature: EcheancePrevue.Nature

    private var texte: String {
        switch nature {
        case .episode: "ÉPISODE"
        case .saison: "SAISON"
        case .sortie: "SORTIE"
        case .tele: "TV"
        }
    }

    private var symbole: String {
        switch nature {
        case .episode: "play.tv"
        case .saison: "sparkles.tv"
        case .sortie: "film"
        case .tele: "tv"
        }
    }

    var body: some View {
        Label(texte, systemImage: symbole)
            .font(.caption2.weight(.black))
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(.black.opacity(0.65), in: Capsule())
            .foregroundStyle(.white)
    }
}

/// Un rendez-vous : l'image du titre, ce qui arrive, et sa date en grand comme l'heure d'un passage TV.
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

    var body: some View {
        NavigationLink(value: echeance.reference) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay { ImageDistante(url: ImageTMDB.url(decor?.fond, .fond) ?? ImageTMDB.url(echeance.cheminAffiche, .fond), coins: 0) }
                .overlay {
                    LinearGradient(stops: [.init(color: .black.opacity(0.45), location: 0), .init(color: .clear, location: 0.35),
                                           .init(color: .black.opacity(0.92), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 6) {
                        PastilleNature(nature: echeance.nature)
                        Spacer(minLength: 4)
                        Text(compteARebours.uppercased())
                            .font(.caption2.weight(.black))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .foregroundStyle(jours < 1 ? Color.black : Color.white)
                            .background(jours < 1 ? AnyShapeStyle(Theme.degradeAccent) : AnyShapeStyle(.black.opacity(0.65)), in: Capsule())
                    }
                    .padding(12)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(date)
                            .font(.system(.title2, design: .rounded).weight(.heavy))
                            .foregroundStyle(Theme.accentClair)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(echeance.titre)
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 7) {
                            PastilleType(film: echeance.reference.type == .film)
                            Text(echeance.libelle)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.78))
                                .lineLimit(1)
                        }
                    }
                    .padding(12)
                }
                .foregroundStyle(.white)
                .surImage()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(jours < 1 ? AnyShapeStyle(Theme.degradeAccent) : AnyShapeStyle(.white.opacity(0.1)), lineWidth: jours < 1 ? 2 : 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(echeance.titre), \(echeance.libelle), \(date), \(compteARebours.lowercased())")
        .accessibilityAddTraits(.isButton)
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
