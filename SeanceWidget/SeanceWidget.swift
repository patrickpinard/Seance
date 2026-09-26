import AppIntents
import SwiftUI
import WidgetKit

// Trois widgets pour l'écran d'accueil et l'écran verrouillé : Ma soirée, les prochains épisodes
// (cochables d'un ✓) et ce qui arrive bientôt.

/// Les widgets de Séance n'ont pas de réglage : cette configuration vide donne accès aux fournisseurs asynchrones.
struct ConfigurationSeance: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Séance"
    static let description = IntentDescription("Widget Séance.")
}

private let famillesEcran: [WidgetFamily] = {
    #if targetEnvironment(macCatalyst)
    [.systemSmall, .systemMedium, .systemLarge]
    #else
    [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline, .accessoryCircular]
    #endif
}()

/// Prochain changement de soirée : 6 h du matin.
private func prochainMatin(apres date: Date) -> Date {
    let calendrier = Calendar.current
    let sixHeures = calendrier.date(bySettingHour: 6, minute: 0, second: 0, of: date) ?? date
    return sixHeures > date ? sixHeures : calendrier.date(byAdding: .day, value: 1, to: sixHeures) ?? date.addingTimeInterval(86_400)
}

// MARK: - Ma soirée

struct FournisseurSoiree: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> EntreeSoiree { .exemple }

    func snapshot(for configuration: ConfigurationSeance, in context: Context) async -> EntreeSoiree {
        let titres = await LecteurWidgets.soiree()
        return context.isPreview && titres.isEmpty ? .exemple : EntreeSoiree(date: .now, titres: titres)
    }

    func timeline(for configuration: ConfigurationSeance, in context: Context) async -> Timeline<EntreeSoiree> {
        let maintenant = Date.now
        let matin = prochainMatin(apres: maintenant)
        return Timeline(entries: [
            EntreeSoiree(date: maintenant, titres: await LecteurWidgets.soiree(maintenant: maintenant)),
            EntreeSoiree(date: matin, titres: []),
        ], policy: .after(matin))
    }
}

struct MaSoireeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "MaSoiree", intent: ConfigurationSeance.self, provider: FournisseurSoiree()) { entree in
            VueEntreeSoiree(entree: entree)
        }
        .configurationDisplayName("Ma soirée")
        .description("Les films et séries gardés pour ce soir.")
        .supportedFamilies(famillesEcran)
    }
}

private struct VueEntreeSoiree: View {
    let entree: EntreeSoiree
    @Environment(\.widgetFamily) private var famille

    var body: some View {
        VueSoiree(entree: entree, famille: famille)
            .widgetURL(LiensWidget.ceSoir)
            .containerBackground(for: .widget) { FondWidget() }
    }
}

// MARK: - Prochains épisodes

struct FournisseurEpisodes: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> EntreeEpisodes { .exemple }

    func snapshot(for configuration: ConfigurationSeance, in context: Context) async -> EntreeEpisodes {
        let episodes = await LecteurWidgets.prochainsEpisodes()
        return context.isPreview && episodes.isEmpty ? .exemple : EntreeEpisodes(date: .now, episodes: episodes)
    }

    func timeline(for configuration: ConfigurationSeance, in context: Context) async -> Timeline<EntreeEpisodes> {
        let entree = EntreeEpisodes(date: .now, episodes: await LecteurWidgets.prochainsEpisodes())
        return Timeline(entries: [entree], policy: .after(.now.addingTimeInterval(2 * 3600)))
    }
}

struct ProchainEpisodeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ProchainEpisode", intent: ConfigurationSeance.self, provider: FournisseurEpisodes()) { entree in
            VueEntreeEpisodes(entree: entree)
        }
        .configurationDisplayName("Prochains épisodes")
        .description("L'épisode suivant de tes séries, à cocher d'un ✓.")
        .supportedFamilies(famillesEcran)
    }
}

private struct VueEntreeEpisodes: View {
    let entree: EntreeEpisodes
    @Environment(\.widgetFamily) private var famille

    var body: some View {
        VueEpisodes(entree: entree, famille: famille)
            .containerBackground(for: .widget) { FondWidget() }
    }
}

// MARK: - À venir

struct FournisseurAVenir: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> EntreeAVenir { .exemple }

    func snapshot(for configuration: ConfigurationSeance, in context: Context) async -> EntreeAVenir {
        let echeances = await LecteurWidgets.aVenir()
        return context.isPreview && echeances.isEmpty ? .exemple : EntreeAVenir(date: .now, echeances: echeances)
    }

    /// Une entrée maintenant et une à minuit : « Demain » devient « Aujourd'hui » sans attendre l'app.
    func timeline(for configuration: ConfigurationSeance, in context: Context) async -> Timeline<EntreeAVenir> {
        let maintenant = Date.now
        let minuit = Calendar.current.startOfDay(for: maintenant.addingTimeInterval(86_400))
        let tout = await LecteurWidgets.aVenir(maintenant: maintenant, limite: 12)
        let demain = tout.filter { $0.nature == .tele ? $0.date > minuit.addingTimeInterval(-2 * 3600) : $0.date >= minuit }
        return Timeline(entries: [
            EntreeAVenir(date: maintenant, echeances: Array(tout.prefix(6))),
            EntreeAVenir(date: minuit, echeances: Array(demain.prefix(6))),
        ], policy: .after(minuit.addingTimeInterval(60)))
    }
}

struct AVenirWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "AVenir", intent: ConfigurationSeance.self, provider: FournisseurAVenir()) { entree in
            VueEntreeAVenir(entree: entree)
        }
        .configurationDisplayName("À venir")
        .description("Prochains épisodes, sorties et passages à la TV de tes titres suivis.")
        .supportedFamilies(famillesEcran)
    }
}

private struct VueEntreeAVenir: View {
    let entree: EntreeAVenir
    @Environment(\.widgetFamily) private var famille

    var body: some View {
        VueAVenir(entree: entree, famille: famille)
            .containerBackground(for: .widget) { FondWidget() }
    }
}

// MARK: - Reprendre (8.1)

struct FournisseurReprendre: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> EntreeReprendre { .exemple }

    func snapshot(for configuration: ConfigurationSeance, in context: Context) async -> EntreeReprendre {
        let reprises = await LecteurWidgets.reprises()
        return context.isPreview && reprises.isEmpty ? .exemple : EntreeReprendre(date: .now, reprises: reprises)
    }

    func timeline(for configuration: ConfigurationSeance, in context: Context) async -> Timeline<EntreeReprendre> {
        Timeline(entries: [EntreeReprendre(date: .now, reprises: await LecteurWidgets.reprises())],
                 policy: .after(.now.addingTimeInterval(3 * 3600)))
    }
}

struct ReprendreWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Reprendre", intent: ConfigurationSeance.self, provider: FournisseurReprendre()) { entree in
            VueReprendre(entree: entree)
                .containerBackground(for: .widget) { FondWidget() }
        }
        .configurationDisplayName("Reprendre")
        .description("Les films et épisodes du NAS entamés : un toucher reprend là où tu t'étais arrêté.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct SeanceWidgets: WidgetBundle {
    var body: some Widget {
        MaSoireeWidget()
        ProchainEpisodeWidget()
        AVenirWidget()
        ReprendreWidget()
    }
}
