import AVFoundation
import SwiftUI

/// Apple Music–style full player with animated album art.
struct ExpandedPlayerView: View {
    @Environment(PlayerHub.self) private var hub

    private var np: NowPlaying { hub.nowPlaying }
    private var tint: Color { (np.tint ?? GT.fallbackTint).color }
    private var tallVideo: URL? { hub.motion?.tall }

    var body: some View {
        ZStack {
            PlayerBackground(artwork: hub.artwork, tint: tint, tallVideo: tallVideo,
                             isPlaying: np.isPlaying, trackID: np.trackID)

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 16)
                if tallVideo == nil {
                    hero
                    Spacer(minLength: 24)
                } else {
                    Spacer()
                }
                if np.isEmpty {
                    emptyState
                } else {
                    titleRow
                    Scrubber(nowPlaying: np) { hub.perform(.seek($0)) }
                        .padding(.top, 16)
                    mixBadge
                        .frame(height: 26)
                    transport
                        .padding(.top, 8)
                    if let volume = np.volume {
                        VolumeRow(volume: volume) { hub.perform(.setVolume($0)) }
                            .padding(.top, 16)
                    }
                }
                Spacer(minLength: 20)
                bottomBar
            }
            .padding(.horizontal, 26)
            .padding(.top, 34)
            .padding(.bottom, 18)
        }
        .frame(width: 360, height: 660)
        .environment(\.colorScheme, .dark)
        .animation(.spring(duration: 0.5), value: np.isPlaying)
        .animation(.easeInOut(duration: hub.isMixing ? 1.6 : 0.4), value: np.trackID)
    }

    // MARK: Sections

    private var topBar: some View {
        HStack(spacing: 8) {
            if let icon = SharedStore.icon(for: np.sourceAppID) {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            }
            Text(np.sourceName.isEmpty ? "Not Playing" : np.sourceName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(.clear, in: .capsule)
    }

    private var hero: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return ZStack {
            if let art = hub.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [tint, tint.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note").font(.system(size: 80, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
            }
            if let square = hub.motion?.square {
                LoopingVideo(url: square, isPlaying: np.isPlaying)
            }
        }
        .frame(width: 290, height: 290)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5) }
        .shadow(color: .black.opacity(np.isPlaying ? 0.45 : 0.2), radius: np.isPlaying ? 30 : 12, y: np.isPlaying ? 18 : 6)
        // Apple Music shrinks the artwork when paused.
        .scaleEffect(np.isPlaying || np.isEmpty ? 1 : 0.82)
        .id(np.trackID)
        .transition(hub.isMixing
                    ? .asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.08)), removal: .opacity.combined(with: .scale(scale: 0.92)))
                    : .opacity)
    }

    private var titleRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(np.title)
                    .font(.system(size: 19, weight: .bold))
                    .lineLimit(1)
                Text(np.artist)
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .id(np.trackID)
            .transition(.opacity)
            Spacer(minLength: 8)
            Button {
                WindowManager.showMiniPlayer()
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
        }
    }

    @ViewBuilder
    private var mixBadge: some View {
        if hub.isMixing {
            Label("Mixing into next song", systemImage: "infinity")
                .symbolEffect(.pulse, options: .repeating)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassEffect(.regular.tint(tint.opacity(0.5)), in: .capsule)
                .transition(.scale.combined(with: .opacity))
        } else if let transition = np.transition {
            Label(transition, systemImage: transition == "AutoMix" ? "infinity" : "arrow.triangle.merge")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .glassEffect(.clear, in: .capsule)
        }
    }

    private var transport: some View {
        HStack {
            Spacer()
            PlayerGlyph(symbol: "backward.fill", size: 26) { hub.perform(.previous) }
            Spacer()
            PlayerGlyph(symbol: np.isPlaying ? "pause.fill" : "play.fill", size: 38) { hub.perform(.playPause) }
            Spacer()
            PlayerGlyph(symbol: "forward.fill", size: 26) { hub.perform(.next) }
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("Not Playing")
                .font(.system(size: 22, weight: .bold))
            Text("Start music in \(hub.selection == .automatic ? "any supported app" : hub.selection.title), or press play.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            PlayerGlyph(symbol: "play.fill", size: 44) { hub.perform(.playPause) }
        }
    }

    private var bottomBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                ToggleGlyph(symbol: "shuffle", isOn: np.shuffle == true, isEnabled: np.shuffle != nil) {
                    hub.perform(.toggleShuffle)
                }
                ToggleGlyph(symbol: (np.repeatMode ?? .off).symbol, isOn: (np.repeatMode ?? .off) != .off,
                            isEnabled: np.repeatMode != nil) {
                    hub.perform(.cycleRepeat)
                }
                Spacer()
                SourceMenu()
            }
        }
    }
}

// MARK: - Controls

struct PlayerGlyph: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size * 1.8, height: size * 1.5)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .background {
                Circle()
                    .fill(.white.opacity(configuration.isPressed ? 0.15 : 0))
                    .scaleEffect(configuration.isPressed ? 1 : 0.6)
            }
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

struct ToggleGlyph: View {
    let symbol: String
    let isOn: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn ? AnyShapeStyle(.black) : AnyShapeStyle(.primary))
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .glassEffect(isOn ? .regular.tint(.white).interactive() : .regular.interactive(), in: .circle)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
    }
}

struct SourceMenu: View {
    @Environment(PlayerHub.self) private var hub

    var body: some View {
        @Bindable var hub = hub
        Menu {
            Picker("Source", selection: $hub.selection) {
                ForEach(SourceKind.allCases) { kind in
                    Label(kind.title, systemImage: kind.symbol).tag(kind)
                }
            }
            .pickerStyle(.inline)
            if !hub.sonos.rooms.isEmpty {
                Section("Sonos Rooms") {
                    ForEach(hub.sonos.rooms) { room in
                        Button(room.name) {
                            hub.sonos.selectedRoom = room
                            hub.selection = .sonos
                        }
                    }
                }
            }
            Divider()
            Button("GlassTunes Settings…") { WindowManager.showSettings() }
        } label: {
            Label(hub.selection.title, systemImage: "airplay.audio")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(height: 38)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

/// Apple Music's capsule scrubber: thin at rest, thicker while dragging.
struct Scrubber: View {
    let nowPlaying: NowPlaying
    var compact = false
    let onSeek: (Double) -> Void
    @State private var dragFraction: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let duration = max(nowPlaying.duration, 0.01)
            let live = nowPlaying.position(at: context.date) / duration
            let fraction = min(1, max(0, dragFraction ?? live))
            VStack(spacing: compact ? 3 : 6) {
                CapsuleBar(fraction: fraction, isActive: dragFraction != nil, restHeight: compact ? 5 : 7) { dragFraction = $0 } onEnded: { value in
                    onSeek(value * duration)
                    dragFraction = nil
                }
                HStack {
                    Text(TrackProgress.format(fraction * duration))
                    Spacer()
                    Text("-" + TrackProgress.format(duration - fraction * duration))
                }
                .font(.system(size: compact ? 9 : 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .disabled(nowPlaying.duration <= 0)
    }
}

struct VolumeRow: View {
    let volume: Int
    let onChange: (Int) -> Void
    @State private var draft: Double?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
            CapsuleBar(fraction: draft ?? Double(volume) / 100, isActive: draft != nil) { value in
                draft = value
                onChange(Int(value * 100))
            } onEnded: { value in
                onChange(Int(value * 100))
                draft = nil
            }
            Image(systemName: "speaker.wave.3.fill")
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
}

struct CapsuleBar: View {
    let fraction: Double
    let isActive: Bool
    var restHeight: CGFloat = 7
    let onChanged: (Double) -> Void
    let onEnded: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let value = { (x: CGFloat) in min(1, max(0, Double(x / geo.size.width))) }
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule().fill(.white.opacity(isActive ? 1 : 0.8))
                    .frame(width: geo.size.width * fraction)
            }
            .frame(height: isActive ? restHeight + 5 : restHeight)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onChanged(value($0.location.x)) }
                    .onEnded { onEnded(value($0.location.x)) }
            )
            .animation(.spring(duration: 0.25), value: isActive)
        }
        .frame(height: restHeight + 11)
    }
}

// MARK: - Background

/// Apple Music's slowly swirling, blurred artwork backdrop — or the full-height motion cover when the album has one.
struct PlayerBackground: View {
    let artwork: NSImage?
    let tint: Color
    let tallVideo: URL?
    let isPlaying: Bool
    let trackID: String

    var body: some View {
        ZStack {
            Color.black
            tint.opacity(0.6)
            if let artwork {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    ZStack {
                        Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 900, height: 900)
                            .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 90) * 4))
                        Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 700, height: 700)
                            .rotationEffect(.degrees(-t.truncatingRemainder(dividingBy: 60) * 6))
                            .offset(x: 120 * sin(t / 7), y: 160 * cos(t / 9))
                            .blendMode(.plusLighter)
                            .opacity(0.5)
                    }
                    .blur(radius: 70)
                    .saturation(1.4)
                }
                .id(trackID)
                .transition(.opacity)
            }
            if let tallVideo {
                LoopingVideo(url: tallVideo, isPlaying: isPlaying)
                    .transition(.opacity)
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.35),
                    .init(color: .black.opacity(0.75), location: 0.75),
                    .init(color: .black.opacity(0.9), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            } else {
                Color.black.opacity(0.28)
            }
        }
        .ignoresSafeArea()
        .clipped()
    }
}

// MARK: - Video

/// Muted, looping HLS video that fades in once the first frame is ready.
struct LoopingVideo: NSViewRepresentable {
    let url: URL
    let isPlaying: Bool

    func makeNSView(context: Context) -> VideoView { VideoView() }

    func updateNSView(_ view: VideoView, context: Context) {
        view.load(url)
        if isPlaying { view.player.play() } else { view.player.pause() }
    }

    static func dismantleNSView(_ view: VideoView, coordinator: ()) {
        view.player.pause()
        view.player.replaceCurrentItem(with: nil)
    }

    final class VideoView: NSView {
        let player = AVPlayer()
        private let playerLayer = AVPlayerLayer()
        private var current: URL?
        private var readyObservation: NSKeyValueObservation?
        private var loopObserver: NSObjectProtocol?

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.opacity = 0
            layer?.addSublayer(playerLayer)
            readyObservation = playerLayer.observe(\.isReadyForDisplay) { layer, _ in
                DispatchQueue.main.async {
                    CATransaction.begin()
                    CATransaction.setAnimationDuration(0.6)
                    layer.opacity = layer.isReadyForDisplay ? 1 : 0
                    CATransaction.commit()
                }
            }
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }

        func load(_ url: URL) {
            guard url != current else { return }
            current = url
            playerLayer.opacity = 0
            let item = AVPlayerItem(url: url)
            item.preferredMaximumResolution = CGSize(width: 1080, height: 1920)
            player.replaceCurrentItem(with: item)
            if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
            loopObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                                  object: item, queue: .main) { [weak self] _ in
                self?.player.seek(to: .zero)
                self?.player.play()
            }
        }

        deinit {
            if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        }
    }
}
