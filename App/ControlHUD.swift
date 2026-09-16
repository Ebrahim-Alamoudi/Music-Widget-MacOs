import AppKit
import SwiftUI

/// A small glass slider (volume or song position) that pops up at the pointer when a widget's bar or
/// volume buttons are clicked, since widgets themselves can only be clicked, not dragged.
@MainActor
@Observable
final class ControlHUDState {
    enum Mode { case volume, seek }
    var mode: Mode = .volume
}

@MainActor
enum ControlHUD {
    private static let state = ControlHUDState()
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?
    private static let size = CGSize(width: 290, height: 50)

    static func show(_ mode: ControlHUDState.Mode) {
        state.mode = mode
        let panel = panel ?? makePanel()
        self.panel = panel

        // Center on the pointer, kept inside the screen it's on.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        var origin = NSPoint(x: mouse.x - panel.frame.width / 2, y: mouse.y - panel.frame.height / 2)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - panel.frame.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - panel.frame.height - 8)
        }
        panel.setFrameOrigin(origin)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        scheduleHide()
    }

    static func keepOpen() {
        scheduleHide()
    }

    private static func scheduleHide(after seconds: Double = 2.5) {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let panel else { return }
            // Still dragging? Check again shortly.
            if NSEvent.pressedMouseButtons != 0 {
                return scheduleHide(after: 0.5)
            }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    private static func makePanel() -> NSPanel {
        let margin: CGFloat = 16
        let frame = NSRect(x: 0, y: 0, width: size.width + margin * 2, height: size.height + margin * 2)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false

        let container = NSView(frame: frame)
        container.wantsLayer = true
        let glassFrame = NSRect(x: margin, y: margin, width: size.width, height: size.height)
        let shadow = NSView(frame: glassFrame)
        shadow.wantsLayer = true
        shadow.layer?.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: size),
                                          cornerWidth: size.height / 2, cornerHeight: size.height / 2, transform: nil)
        shadow.layer?.shadowColor = NSColor.black.cgColor
        shadow.layer?.shadowOpacity = 0.3
        shadow.layer?.shadowRadius = 10
        shadow.layer?.shadowOffset = CGSize(width: 0, height: -4)
        container.addSubview(shadow)

        let hosting = NSHostingView(rootView: ControlHUDView().environment(PlayerHub.shared).environment(state))
        hosting.frame = NSRect(origin: .zero, size: size)
        container.addSubview(GlassBackdropView.make(frame: glassFrame, cornerRadius: size.height / 2, content: hosting))
        panel.contentView = container

        // Close when the user clicks somewhere else.
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated {
                guard let panel = ControlHUD.panel, panel.isVisible,
                      !panel.frame.contains(NSEvent.mouseLocation) else { return }
                panel.orderOut(nil)
            }
        }
        return panel
    }
}

private struct ControlHUDView: View {
    @Environment(ControlHUDState.self) private var state
    @Environment(PlayerHub.self) private var hub

    var body: some View {
        Group {
            switch state.mode {
            case .volume: VolumeSlider()
            case .seek: SeekSlider()
            }
        }
        .padding(.horizontal, 18)
        .frame(width: 290, height: 50)
        .onHover { if $0 { ControlHUD.keepOpen() } }
    }
}

private struct SeekSlider: View {
    @Environment(PlayerHub.self) private var hub

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: hub.nowPlaying.isPlaying ? "waveform" : "pause.fill")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 22)
            Scrubber(nowPlaying: hub.nowPlaying, compact: true) { seconds in
                hub.perform(.seek(seconds))
                ControlHUD.keepOpen()
            }
        }
        .padding(.top, 6)
    }
}

private struct VolumeSlider: View {
    @Environment(PlayerHub.self) private var hub
    @State private var draft: Double?

    var body: some View {
        let level = draft ?? Double(hub.nowPlaying.volume ?? 0) / 100
        HStack(spacing: 12) {
            Image(systemName: symbol(for: level))
                .font(.system(size: 15, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 24)
            CapsuleBar(fraction: level, isActive: draft != nil, restHeight: 8) { value in
                draft = value
                hub.setVolume(Int((value * 100).rounded()))
                ControlHUD.keepOpen()
            } onEnded: { value in
                hub.setVolume(Int((value * 100).rounded()))
                draft = nil
                ControlHUD.keepOpen()
            }
            Text("\(Int((level * 100).rounded()))")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
    }

    private func symbol(for level: Double) -> String {
        switch level {
        case ..<0.01: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}
