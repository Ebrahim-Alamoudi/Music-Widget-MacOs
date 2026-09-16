import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Snapshot

struct RecentItem: Identifiable {
    var track: RecentTrack
    var image: NSImage?
    var id: String { track.id }
}

struct PlayerSnapshot {
    var nowPlaying: NowPlaying
    var artwork: NSImage?
    var recent: [RecentItem]
    var style: GlassStyle
    var sourceIcon: NSImage?

    var tint: Color { (nowPlaying.tint ?? GT.fallbackTint).color }
    var playSymbol: String { nowPlaying.isPlaying ? "pause.fill" : "play.fill" }

    static func load(style: GlassStyle) -> PlayerSnapshot {
        let np = SharedStore.nowPlaying
        return PlayerSnapshot(
            nowPlaying: np,
            artwork: np.isEmpty ? nil : SharedStore.artwork(for: np.trackID),
            recent: SharedStore.recent.prefix(4).map { RecentItem(track: $0, image: SharedStore.artwork(for: $0.id)) },
            style: style,
            sourceIcon: SharedStore.icon(for: np.sourceAppID)
        )
    }

    static func preview(style: GlassStyle) -> PlayerSnapshot {
        var np = NowPlaying()
        np.state = .playing
        np.trackID = "preview"
        np.title = "Liquid Glass"
        np.artist = "GlassTunes"
        np.album = "macOS 27"
        np.duration = 214
        np.position = 71
        np.tint = RGBColor(r: 0.36, g: 0.42, b: 0.95)
        np.source = .appleMusic
        np.sourceName = "Apple Music"
        np.shuffle = false
        np.repeatMode = .off
        np.transition = "AutoMix"
        let recent = [
            RecentTrack(id: "p1", title: "Midnight Drive", artist: "Neon Coast"),
            RecentTrack(id: "p2", title: "Refraction", artist: "Prism"),
            RecentTrack(id: "p3", title: "Soft Focus", artist: "Aurora Lane"),
        ]
        return PlayerSnapshot(nowPlaying: np, artwork: nil, recent: recent.map { RecentItem(track: $0, image: nil) },
                              style: style, sourceIcon: nil)
    }
}

// MARK: - Liquid Glass primitives
// Hand-built glass (tinted fill + specular gradient + light rim) because widgets are rendered
// as static snapshots, where live materials and `glassEffect` aren't reliable.

struct LiquidGlass<S: InsettableShape>: ViewModifier {
    var shape: S
    var intensity: Double = 1
    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        let fullColor = renderingMode == .fullColor
        content
            .background {
                if fullColor {
                    ZStack {
                        shape.fill(.white.opacity(0.10 * intensity))
                        shape.fill(LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.32 * intensity), location: 0),
                                .init(color: .white.opacity(0.05), location: 0.45),
                                .init(color: .clear, location: 0.7),
                                .init(color: .white.opacity(0.12 * intensity), location: 1),
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                    }
                } else {
                    shape.fill(.white.opacity(0.12))
                }
            }
            .overlay {
                shape.strokeBorder(LinearGradient(
                    colors: [.white.opacity(0.8), .white.opacity(0.12), .white.opacity(0.04), .white.opacity(0.45)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(fullColor ? 0.2 * intensity : 0), radius: 8, y: 4)
    }
}

extension View {
    func liquidGlass<S: InsettableShape>(_ shape: S, intensity: Double = 1) -> some View {
        modifier(LiquidGlass(shape: shape, intensity: intensity))
    }
}

struct GlassBackdrop: View {
    let snapshot: PlayerSnapshot

    var body: some View {
        ZStack {
            switch snapshot.style {
            case .artwork:
                LinearGradient(colors: [snapshot.tint, snapshot.tint.opacity(0.55), .black.opacity(0.85)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if let art = snapshot.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 38)
                        .saturation(1.5)
                        .opacity(0.9)
                }
                LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
            case .frosted:
                Color(white: 0.14)
                RadialGradient(colors: [snapshot.tint.opacity(0.55), .clear], center: .topLeading, startRadius: 0, endRadius: 320)
                RadialGradient(colors: [snapshot.tint.opacity(0.25), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 260)
                Color.white.opacity(0.06)
            case .clear:
                LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom)
            }
            // Specular sheen across the top-left edge.
            LinearGradient(stops: [.init(color: .white.opacity(0.24), location: 0), .init(color: .clear, location: 0.4)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// MARK: - Building blocks

struct ArtworkView: View {
    let image: NSImage?
    let tint: Color
    var corner: CGFloat = 14

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .widgetAccentedRenderingMode(.desaturated)
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [tint, tint.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note")
                    .font(.system(size: max(12, corner * 1.5), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05), .white.opacity(0.2)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }
}

/// The small app icon in the top-right corner, like on the iPhone.
struct SourceBadge: View {
    let snapshot: PlayerSnapshot
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let icon = snapshot.sourceIcon {
                Image(nsImage: icon)
                    .resizable()
                    .widgetAccentedRenderingMode(.desaturated)
            } else {
                Image(systemName: snapshot.nowPlaying.source.symbol)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .frame(width: size, height: size)
                    .liquidGlass(Circle(), intensity: 0.6)
            }
        }
        .frame(width: size, height: size)
    }
}

/// The source badge; when several players are active it becomes a button that switches between them.
struct SourceSwitcher: View {
    let snapshot: PlayerSnapshot
    var size: CGFloat = 20

    var body: some View {
        let count = snapshot.nowPlaying.availableSources?.count ?? 0
        if count > 1 {
            Button(intent: NextSourceIntent()) {
                HStack(spacing: 3) {
                    SourceBadge(snapshot: snapshot, size: size)
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 2)
                .padding(.trailing, 5)
                .padding(.vertical, 2)
                .liquidGlass(Capsule(), intensity: 0.6)
            }
            .buttonStyle(.plain)
        } else {
            SourceBadge(snapshot: snapshot, size: size)
        }
    }
}

/// Plain white transport glyph, as on the iPhone Lock Screen.
struct GlyphButton<I: AppIntent>: View {
    let intent: I
    let symbol: String
    var size: CGFloat = 20
    var active = true

    var body: some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(active ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(width: size * 1.7, height: size * 1.5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .widgetAccentable()
    }
}

struct TransportRow: View {
    let snapshot: PlayerSnapshot
    var size: CGFloat = 20

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            GlyphButton(intent: PreviousTrackIntent(), symbol: "backward.fill", size: size)
            Spacer(minLength: 0)
            GlyphButton(intent: TogglePlaybackIntent(), symbol: snapshot.playSymbol, size: size * 1.3)
            Spacer(minLength: 0)
            GlyphButton(intent: NextTrackIntent(), symbol: "forward.fill", size: size)
            Spacer(minLength: 0)
        }
    }
}

extension EnvironmentValues {
    /// True when widget views are drawn inside the app as previews. Previews skip the
    /// timer-driven views, which redraw every frame outside of WidgetKit.
    @Entry var isStaticWidgetPreview = false
}

struct TrackProgress: View {
    let nowPlaying: NowPlaying
    var showTimes = true
    @Environment(\.isStaticWidgetPreview) private var isStaticPreview

    private var isLive: Bool { nowPlaying.isPlaying && nowPlaying.duration > 0 && !isStaticPreview }

    var body: some View {
        let position = nowPlaying.position(at: .now)
        let total = max(nowPlaying.duration, 0.01)
        VStack(spacing: 3) {
            if isLive {
                ProgressView(timerInterval: nowPlaying.startDate...nowPlaying.endDate, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(Color.primary)
                .labelsHidden()
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.2))
                        Capsule().fill(.primary)
                            .frame(width: geo.size.width * min(1, position / total))
                    }
                }
                .frame(height: 4)
            }

            if showTimes {
                HStack {
                    if isLive {
                        Text(timerInterval: nowPlaying.startDate...nowPlaying.endDate, countsDown: false)
                            .frame(maxWidth: 44, alignment: .leading)
                        Spacer()
                        Text(timerInterval: nowPlaying.startDate...nowPlaying.endDate, countsDown: true)
                            .frame(maxWidth: 44, alignment: .trailing)
                    } else {
                        Text(Self.format(position))
                        Spacer()
                        Text("-" + Self.format(nowPlaying.duration - position))
                    }
                }
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    static func format(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct TrackTitles: View {
    let nowPlaying: NowPlaying
    var titleSize: CGFloat = 14
    var titleLines = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(nowPlaying.title)
                .font(.system(size: titleSize, weight: .semibold))
                .lineLimit(titleLines)
                .widgetAccentable()
            Text(nowPlaying.artist)
                .font(.system(size: titleSize * 0.92))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// "AutoMix" / "Crossfade" pill, like the badge under the scrubber in Apple Music.
struct TransitionBadge: View {
    let nowPlaying: NowPlaying

    var body: some View {
        if let transition = nowPlaying.transition {
            Label(transition, systemImage: transition == "AutoMix" ? "infinity" : "arrow.triangle.merge")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .liquidGlass(Capsule(), intensity: 0.5)
        }
    }
}

struct NotPlayingView: View {
    let snapshot: PlayerSnapshot
    var horizontal = false

    var body: some View {
        let layout = horizontal ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        layout {
            ArtworkView(image: nil, tint: snapshot.tint, corner: 10)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("Not Playing")
                    .font(.system(size: 14, weight: .semibold))
                Text(snapshot.nowPlaying.sourceName.isEmpty ? "Press play to start" : snapshot.nowPlaying.sourceName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            GlyphButton(intent: TogglePlaybackIntent(), symbol: "play.fill", size: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - The three widgets

/// Control Center–style Now Playing tile.
struct SmallPlayerView: View {
    let snapshot: PlayerSnapshot

    var body: some View {
        if snapshot.nowPlaying.isEmpty {
            NotPlayingView(snapshot: snapshot)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    ArtworkView(image: snapshot.artwork, tint: snapshot.tint, corner: 9)
                        .frame(width: 50, height: 50)
                    Spacer(minLength: 4)
                    SourceSwitcher(snapshot: snapshot, size: 18)
                }
                Spacer(minLength: 6)
                TrackTitles(nowPlaying: snapshot.nowPlaying, titleSize: 13)
                Spacer(minLength: 4)
                TransportRow(snapshot: snapshot, size: 17)
            }
        }
    }
}

/// iPhone Lock Screen Now Playing, one to one.
struct MediumPlayerView: View {
    let snapshot: PlayerSnapshot

    var body: some View {
        if snapshot.nowPlaying.isEmpty {
            NotPlayingView(snapshot: snapshot, horizontal: true)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    ArtworkView(image: snapshot.artwork, tint: snapshot.tint, corner: 9)
                        .frame(width: 50, height: 50)
                    TrackTitles(nowPlaying: snapshot.nowPlaying, titleSize: 14)
                    Spacer(minLength: 4)
                    SourceSwitcher(snapshot: snapshot, size: 22)
                }
                Spacer(minLength: 8)
                TrackProgress(nowPlaying: snapshot.nowPlaying)
                Spacer(minLength: 4)
                TransportRow(snapshot: snapshot, size: 22)
            }
        }
    }
}

/// Apple Music's full player, condensed.
struct LargePlayerView: View {
    let snapshot: PlayerSnapshot

    var body: some View {
        let np = snapshot.nowPlaying
        VStack(alignment: .leading, spacing: 0) {
            if np.isEmpty {
                NotPlayingView(snapshot: snapshot, horizontal: true)
                    .frame(height: 170)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    ArtworkView(image: snapshot.artwork, tint: snapshot.tint, corner: 16)
                        .frame(width: 150, height: 150)
                        .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            SourceSwitcher(snapshot: snapshot, size: 18)
                            Text(np.sourceName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        TrackTitles(nowPlaying: np, titleSize: 18, titleLines: 2)
                        if !np.album.isEmpty {
                            Text(np.album)
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .frame(height: 150)
                }
                Spacer(minLength: 12)
                TrackProgress(nowPlaying: np)
                    .overlay(alignment: .bottom) { TransitionBadge(nowPlaying: np).offset(y: 2) }
                Spacer(minLength: 6)
                HStack(spacing: 0) {
                    if np.shuffle != nil {
                        GlyphButton(intent: ToggleShuffleIntent(), symbol: "shuffle", size: 13, active: np.shuffle == true)
                    }
                    TransportRow(snapshot: snapshot, size: 26)
                    if let mode = np.repeatMode {
                        GlyphButton(intent: CycleRepeatIntent(), symbol: mode.symbol, size: 13, active: mode != .off)
                    }
                }
            }
            Spacer(minLength: 10)
            RecentStrip(snapshot: snapshot)
        }
    }
}

struct RecentStrip: View {
    let snapshot: PlayerSnapshot

    var body: some View {
        HStack(spacing: 10) {
            Text("Recently\nPlayed")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
            if snapshot.recent.isEmpty {
                Text("Songs you play show up here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            } else {
                ForEach(snapshot.recent) { item in
                    ArtworkView(image: item.image, tint: snapshot.tint, corner: 7)
                        .frame(width: 44, height: 44)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .liquidGlass(RoundedRectangle(cornerRadius: 14, style: .continuous), intensity: 0.6)
    }
}

/// Picks the layout for a widget size. Colored glass styles always use light-on-dark text.
struct GlassTunesWidgetView: View {
    let family: WidgetFamily
    let snapshot: PlayerSnapshot
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch family {
            case .systemSmall: SmallPlayerView(snapshot: snapshot)
            case .systemMedium: MediumPlayerView(snapshot: snapshot)
            default: LargePlayerView(snapshot: snapshot)
            }
        }
        .environment(\.colorScheme, snapshot.style == .clear ? colorScheme : .dark)
    }
}
