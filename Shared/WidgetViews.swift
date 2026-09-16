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

extension Image {
    /// Grey artwork in tinted widget mode (macOS 15+); older systems keep full color.
    @ViewBuilder
    func desaturatedWhenAccented() -> some View {
        if #available(macOS 15.0, *) {
            widgetAccentedRenderingMode(.desaturated)
        } else {
            self
        }
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
                    .desaturatedWhenAccented()
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
                    .desaturatedWhenAccented()
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

/// The source badge. When several players are active, a tiny switch button (window-button sized)
/// sits on its corner and moves to the next player.
struct SourceSwitcher: View {
    let snapshot: PlayerSnapshot
    var size: CGFloat = 20

    var body: some View {
        let count = snapshot.nowPlaying.availableSources?.count ?? 0
        SourceBadge(snapshot: snapshot, size: size)
            .overlay(alignment: .bottomTrailing) {
                if count > 1 {
                    Button(intent: NextSourceIntent()) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(Color.black.opacity(0.8))
                            .frame(width: 14, height: 14)
                            .background(Circle().fill(.white))
                            .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: 5, y: 5)
                    .widgetAccentable()
                }
            }
            // Room for the corner button so it isn't clipped.
            .padding([.trailing, .bottom], count > 1 ? 5 : 0)
    }
}

/// Plain white transport glyph, as on the iPhone Lock Screen.
struct GlyphButton<I: AppIntent>: View {
    let intent: I
    let symbol: String
    var size: CGFloat = 20
    var active = true
    /// Shuffle/repeat: when on, drawn as a dark glyph on a white disc.
    var isToggle = false

    var body: some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(foreground)
                .frame(width: size * 1.7, height: size * 1.5)
                .background {
                    if isToggle && active {
                        Circle().fill(.white).frame(width: size * 1.9, height: size * 1.9)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .widgetAccentable()
    }
}

extension GlyphButton {
    private var foreground: AnyShapeStyle {
        if isToggle { return active ? AnyShapeStyle(Color.black.opacity(0.85)) : AnyShapeStyle(.secondary) }
        return active ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)
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
    var barHeight: CGFloat = 4
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
                .scaleEffect(x: 1, y: max(1, barHeight / 4), anchor: .center)
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.2))
                        Capsule().fill(.primary)
                            .frame(width: geo.size.width * min(1, position / total))
                    }
                }
                .frame(height: barHeight)
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

/// iPhone Control Center's expanded Now Playing card.
struct LargePlayerView: View {
    let snapshot: PlayerSnapshot

    var body: some View {
        let np = snapshot.nowPlaying
        VStack(spacing: 0) {
            // Artwork, titles, and the route/source button in the corner.
            HStack(alignment: .center, spacing: 14) {
                ArtworkView(image: np.isEmpty ? nil : snapshot.artwork, tint: snapshot.tint, corner: 12)
                    .frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 2) {
                    Text(np.isEmpty ? "Not Playing" : np.title)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                        .widgetAccentable()
                    Text(np.isEmpty ? (np.sourceName.isEmpty ? "Music" : np.sourceName) : np.artist)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                SourceSwitcher(snapshot: snapshot, size: 26)
            }

            Spacer(minLength: 16)

            TrackProgress(nowPlaying: np, barHeight: 7)
                .opacity(np.isEmpty ? 0.4 : 1)

            // Sits on its own line under the times, clear of the scrubber.
            if np.transition != nil {
                TransitionBadge(nowPlaying: np)
                    .padding(.top, 10)
            }

            Spacer(minLength: 10)

            TransportRow(snapshot: snapshot, size: 30)

            Spacer(minLength: 12)

            VolumeStrip(volume: np.volume)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }
}

/// Control Center volume row. Widgets can't be dragged, so the speaker icons step the volume.
struct VolumeStrip: View {
    let volume: Int?

    var body: some View {
        HStack(spacing: 10) {
            GlyphButton(intent: VolumeDownIntent(), symbol: "speaker.fill", size: 12, active: volume != nil)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.2))
                    Capsule().fill(.primary)
                        .frame(width: geo.size.width * CGFloat(volume ?? 0) / 100)
                }
            }
            .frame(height: 7)
            .widgetAccentable()
            GlyphButton(intent: VolumeUpIntent(), symbol: "speaker.wave.3.fill", size: 12, active: volume != nil)
        }
        .opacity(volume == nil ? 0.4 : 1)
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
