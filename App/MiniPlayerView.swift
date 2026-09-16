import SwiftUI

/// Widget-sized floating player on real Liquid Glass (the window's NSGlassEffectView sits behind it).
struct MiniPlayerView: View {
    static let size = CGSize(width: 340, height: 156)

    @Environment(PlayerHub.self) private var hub
    @AppStorage("miniPinned") private var pinned = true
    @State private var hovering = false

    private var np: NowPlaying { hub.nowPlaying }
    private var tint: Color { (np.tint ?? GT.fallbackTint).color }

    var body: some View {
        HStack(spacing: 14) {
            artwork
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 2)
                if np.isEmpty {
                    Text("Not Playing")
                        .font(.system(size: 15, weight: .bold))
                    Text(hub.selection == .automatic ? "Play something in any app" : hub.selection.title)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Text(np.title)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)
                        .id("t" + np.trackID)
                        .transition(.opacity)
                    Text(np.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
                Scrubber(nowPlaying: np, compact: true) { hub.perform(.seek($0)) }
                    .opacity(np.isEmpty ? 0.3 : 1)
                controls
            }
        }
        .padding(14)
        .frame(width: Self.size.width, height: Self.size.height)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .gesture(WindowDragGesture())
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.45), value: np.isPlaying)
        .animation(.easeInOut(duration: hub.isMixing ? 1.4 : 0.35), value: np.trackID)
        .onChange(of: np.tint, initial: true) { _, _ in WindowManager.setMiniTint(tint) }
        .onChange(of: pinned, initial: true) { _, value in WindowManager.setMiniPinned(value) }
    }

    private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return ZStack {
            if let art = hub.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [tint, tint.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note").font(.system(size: 36, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            }
            if let square = hub.motion?.square {
                LoopingVideo(url: square, isPlaying: np.isPlaying, maxPixels: 400)
            }
        }
        .frame(width: 128, height: 128)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
        .shadow(color: .black.opacity(np.isPlaying ? 0.35 : 0.15), radius: np.isPlaying ? 10 : 4, y: np.isPlaying ? 5 : 2)
        .scaleEffect(np.isPlaying || np.isEmpty ? 1 : 0.9)
        .overlay(alignment: .bottomLeading) {
            if hub.isMixing {
                Label("Mixing", systemImage: "infinity")
                    .symbolEffect(.pulse, options: .repeating)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .glassEffect(.regular.tint(tint.opacity(0.5)), in: .capsule)
                    .padding(6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .id(np.trackID)
        .transition(.opacity)
    }

    private var header: some View {
        HStack(spacing: 5) {
            if let icon = hub.sourceIcon {
                Image(nsImage: icon).resizable().frame(width: 14, height: 14)
            } else {
                Image(systemName: hub.selection.symbol).font(.system(size: 10, weight: .semibold))
            }
            Text(np.transition.map { "\(shortSource) · \($0)" } ?? shortSource)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if (np.availableSources?.count ?? 0) > 1 {
                HeaderButton(symbol: "arrow.left.arrow.right", help: "Switch to the other player") {
                    hub.cycleSource()
                }
            }
            Spacer(minLength: 4)
            if hovering {
                HStack(spacing: 2) {
                    HeaderButton(symbol: pinned ? "pin.fill" : "pin", help: pinned ? "Stop keeping on top" : "Keep on top") {
                        pinned.toggle()
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(height: 18)
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var shortSource: String {
        np.sourceName.isEmpty ? hub.selection.title : np.sourceName
    }

    private var controls: some View {
        HStack(spacing: 0) {
            MiniToggle(symbol: "shuffle", isOn: np.shuffle == true, isEnabled: np.shuffle != nil) {
                hub.perform(.toggleShuffle)
            }
            Spacer(minLength: 0)
            PlayerGlyph(symbol: "backward.fill", size: 15) { hub.perform(.previous) }
            PlayerGlyph(symbol: np.isPlaying ? "pause.fill" : "play.fill", size: 22) { hub.perform(.playPause) }
            PlayerGlyph(symbol: "forward.fill", size: 15) { hub.perform(.next) }
            Spacer(minLength: 0)
            MiniToggle(symbol: (np.repeatMode ?? .off).symbol, isOn: (np.repeatMode ?? .off) != .off,
                       isEnabled: np.repeatMode != nil) {
                hub.perform(.cycleRepeat)
            }
        }
    }
}

private struct HeaderButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 18, height: 18)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .help(help)
    }
}

private struct MiniToggle: View {
    let symbol: String
    let isOn: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? AnyShapeStyle(Color.black.opacity(0.85)) : AnyShapeStyle(.secondary))
                .frame(width: 24, height: 24)
                .background {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .opacity(isOn ? 1 : 0)
                        .scaleEffect(isOn ? 1 : 0.6)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.3), value: isOn)
        .accessibilityValue(isOn ? "On" : "Off")
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.3)
    }
}
