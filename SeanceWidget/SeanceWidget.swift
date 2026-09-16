import SwiftUI
import WidgetKit

// Widget vide du jalon 1 : il valide la cible, la signature et l'App Group.
// Le contenu réel (prochain épisode, bouton « Vu ») arrive au jalon 5.

struct EntreeProchainEpisode: TimelineEntry {
    let date: Date
}

struct FournisseurProchainEpisode: TimelineProvider {
    func placeholder(in context: Context) -> EntreeProchainEpisode {
        EntreeProchainEpisode(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (EntreeProchainEpisode) -> Void) {
        completion(EntreeProchainEpisode(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EntreeProchainEpisode>) -> Void) {
        completion(Timeline(entries: [EntreeProchainEpisode(date: .now)], policy: .never))
    }
}

struct ProchainEpisodeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProchainEpisode", provider: FournisseurProchainEpisode()) { _ in
            VStack(alignment: .leading, spacing: 4) {
                Text("Séance")
                    .font(.headline)
                Text("Prochain épisode : bientôt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Prochain épisode")
        .description("Le prochain épisode à regarder.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct SeanceWidgets: WidgetBundle {
    var body: some Widget {
        ProchainEpisodeWidget()
    }
}
