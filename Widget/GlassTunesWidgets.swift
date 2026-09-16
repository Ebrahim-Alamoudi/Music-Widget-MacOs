import AppIntents
import SwiftUI
import WidgetKit

@main
struct GlassTunesWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        PlayerWidget()
        DeckWidget()
    }
}

struct GlassStyleIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Glass Style"
    static let description = IntentDescription("Choose how the liquid glass looks.")

    @Parameter(title: "Glass", default: .artwork)
    var style: GlassStyle

    init() {}
}

struct PlayerEntry: TimelineEntry {
    let date: Date
    let snapshot: PlayerSnapshot
}

struct PlayerProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PlayerEntry {
        PlayerEntry(date: .now, snapshot: .preview(style: .artwork))
    }

    func snapshot(for configuration: GlassStyleIntent, in context: Context) async -> PlayerEntry {
        let live = PlayerSnapshot.load(style: configuration.style)
        // Show something lively in the widget gallery when nothing is playing.
        let snapshot = context.isPreview && live.nowPlaying.isEmpty ? .preview(style: configuration.style) : live
        return PlayerEntry(date: .now, snapshot: snapshot)
    }

    func timeline(for configuration: GlassStyleIntent, in context: Context) async -> Timeline<PlayerEntry> {
        let snapshot = PlayerSnapshot.load(style: configuration.style)
        let np = snapshot.nowPlaying
        // The helper app pushes reloads on every change; this is only a safety net.
        let next = np.isPlaying && np.duration > 0
            ? max(np.endDate, .now.addingTimeInterval(5))
            : .now.addingTimeInterval(30 * 60)
        return Timeline(entries: [PlayerEntry(date: .now, snapshot: snapshot)], policy: .after(next))
    }
}

struct WidgetRoot: View {
    let entry: PlayerEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        GlassTunesWidgetView(family: family, snapshot: entry.snapshot)
            .containerBackground(for: .widget) {
                GlassBackdrop(snapshot: entry.snapshot)
            }
            .widgetURL(GT.openPlayerURL)
    }
}

struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "GlassTunes.NowPlaying", intent: GlassStyleIntent.self, provider: PlayerProvider()) {
            WidgetRoot(entry: $0)
        }
        .configurationDisplayName("Now Playing")
        .description("Artwork and controls, like Control Center on iPhone. Click to open the full player.")
        .supportedFamilies([.systemSmall])
    }
}

struct PlayerWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "GlassTunes.Player", intent: GlassStyleIntent.self, provider: PlayerProvider()) {
            WidgetRoot(entry: $0)
        }
        .configurationDisplayName("Player")
        .description("The iPhone Lock Screen player. Click to open the full player.")
        .supportedFamilies([.systemMedium])
    }
}

struct DeckWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "GlassTunes.Deck", intent: GlassStyleIntent.self, provider: PlayerProvider()) {
            WidgetRoot(entry: $0)
        }
        .configurationDisplayName("Music Deck")
        .description("The iPhone Control Center player: artwork, scrubber, controls and volume.")
        .supportedFamilies([.systemLarge])
    }
}
