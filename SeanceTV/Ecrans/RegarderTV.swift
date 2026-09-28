import SeanceDonnees
import SeanceKit
import SwiftData
import SwiftUI

/// D'où viennent les titres de Regarder, sur la TV : les mêmes que sur l'iPhone.
enum SourceTV: String, CaseIterable, Hashable {
    case tout, streaming, tele, nas

    var nom: String {
        switch self {
        case .tout: "Tout"
        case .streaming: "Streaming"
        case .tele: "TV"
        case .nas: "NAS"
        }
    }

    /// La rangée de jours n'a de sens que pour ce qui passe à une date : ta soirée et la TV.
    var suitLeJour: Bool { self == .tout || self == .tele }

    var pourLesFiltres: ExplorerTV.Source {
        switch self {
        case .tout: .toutes
        case .streaming: .streaming
        case .tele: .tele
        case .nas: .nas
        }
    }
}

/// Regarder sur la TV (8.0, charte commune) : la rangée de jours — « Auj. » d'abord —, les sources Tout · Streaming ·
/// TV · NAS, puis ce que la source montre. Une seule page qui défile : on descend de la rangée aux pastilles, puis aux
/// étagères, et la barre d'onglets revient quand on remonte.
struct RegarderTV: View {
    @Environment(EtatTV.self) private var etat
    @Environment(\.modelContext) private var contexte
    @Query(sort: \SelectionSoir.ajouteLe) private var selections: [SelectionSoir]

    @State private var source = DepartTV.source
    @State private var jour = RegarderTV.aujourdhui

    /// Le jour de la soirée en cours, à minuit : une soirée va de 6 h à 6 h.
    static var aujourdhui: Date {
        Calendar.current.startOfDay(for: ServiceSoiree.jour(ServiceSoiree.soiree()) ?? .now)
    }

    private var jours: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Self.aujourdhui) }
    }

    private var soiree: String { ServiceSoiree.soiree(jour: jour.addingTimeInterval(12 * 3600)) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 44) {
                // Maquette 8.0 : les jours à gauche et les sources à droite, sur une ligne ; sans jour (Streaming, NAS),
                // les sources à gauche.
                // 8.6 (demande de Patrick) : comme sur l'iPhone — les jours pour toutes les sources, puis une ligne avec les
                // sources, le filtre, Films et Séries.
                VStack(alignment: .leading, spacing: 18) {
                    rangeeDeJours.focusSection()
                    HStack { pastilles.fixedSize(); Spacer(minLength: 0) }.focusSection()
                }
                .padding(.horizontal, MargesTV.bord)
                switch source {
                case .tout:
                    SectionsSoireeTV(soiree: soiree)
                    SectionsTeleTV(jour: DateTMDB(jour.addingTimeInterval(12 * 3600)), moments: [.enCours, .soiree], prefixe: "à la TV")
                case .tele:
                    SectionsTeleTV(jour: DateTMDB(jour.addingTimeInterval(12 * 3600)), types: etat.typesRegarder)
                case .streaming:
                    SectionsStreamingTV()
                case .nas:
                    SectionsNASTV()
                }
            }
            .padding(.vertical, 40)
        }
        // « Tout voir » depuis l'accueil : la source demandée, aujourd'hui.
        .onChange(of: etat.demandeRegarder, initial: true) { _, demande in
            guard let demande else { return }
            source = demande
            jour = Self.aujourdhui
            etat.demandeRegarder = nil
        }
    }

    private var rangeeDeJours: some View {
            HStack(spacing: 16) {
                ForEach(jours, id: \.self) { date in
                    let nombre = selections.filter { $0.soiree == ServiceSoiree.soiree(jour: date.addingTimeInterval(12 * 3600)) }.count
                    Button { jour = date } label: {
                        TuileJourTV(nom: nomCourt(date), numero: Calendar.current.component(.day, from: date),
                                    detail: nombre > 1 ? "\(nombre) titres" : nombre == 1 ? "1 titre"
                                        : date.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: "fr_CH"))))
                    }
                    .buttonStyle(BoutonTV(principal: date == jour, hauteur: nil))
                    .accessibilityLabel(date == Self.aujourdhui ? "Aujourd'hui" : date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_CH"))))
                }
            }
            .padding(.vertical, 20)
    }

    private var pastilles: some View {
        HStack(spacing: 14) {
            ForEach(SourceTV.allCases, id: \.self) { choix in
                Button(choix.nom) { source = choix }
                    .buttonStyle(BoutonTV(principal: choix == source, hauteur: 56))
            }
            // Les filtres d'Explorer, en deux parties, sur la source choisie (8.0).
            NavigationLink(value: FiltresTVDemande(source: source.pourLesFiltres)) {
                Image(systemName: "line.3.horizontal.decrease")
            }
            .buttonStyle(BoutonTV(hauteur: 56))
            .accessibilityLabel("Filtres")
            .padding(.leading, 10)
            // 8.6, comme sur l'iPhone : Films et Séries à côté du filtre, l'un, l'autre ou les deux.
            if source == .streaming || source == .tele {
                ForEach([TypeTitre.film, .serie], id: \.self) { type in
                    let coche = etat.typesRegarder.contains(type)
                    Button(type == .film ? "Films" : "Séries") {
                        if coche { if etat.typesRegarder.count > 1 { etat.typesRegarder.remove(type) } } else { etat.typesRegarder.insert(type) }
                    }
                    .buttonStyle(BoutonTV(principal: coche, hauteur: 56))
                    .accessibilityAddTraits(coche ? .isSelected : [])
                }
            }
        }
    }

    private func nomCourt(_ date: Date) -> String {
        if date == Self.aujourdhui { return "Auj." }
        return date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "fr_CH"))).capitalized
    }
}
