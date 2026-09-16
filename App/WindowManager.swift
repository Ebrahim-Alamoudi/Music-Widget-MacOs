import AppKit
import SwiftUI

/// AppKit-hosted windows, so a menu bar app can open them from anywhere (widget clicks, menu, reopen).
@MainActor
enum WindowManager {
    private static var miniPlayer: GlassPanel?
    private static var fullPlayer: GlassPanel?

    // MARK: Players

    static func showMiniPlayer() {
        fullPlayer?.panel.close()
        let player = miniPlayer ?? GlassPanel(
            content: MiniPlayerView(),
            size: MiniPlayerView.size,
            cornerRadius: 28,
            autosaveName: "MiniPlayer2",
            zoomHelp: "Full Player",
            zoom: { showPlayer() },
            onClose: { miniPlayer = nil }
        )
        player.panel.level = UserDefaults.standard.object(forKey: "miniPinned") as? Bool == false ? .normal : .floating
        miniPlayer = player
        player.show()
    }

    static func showPlayer() {
        miniPlayer?.panel.close()
        let player = fullPlayer ?? GlassPanel(
            content: ExpandedPlayerView(),
            size: ExpandedPlayerView.size,
            cornerRadius: 30,
            autosaveName: "FullPlayer2",
            zoomHelp: "Mini Player",
            zoom: { showMiniPlayer() },
            onClose: { fullPlayer = nil }
        )
        fullPlayer = player
        player.show()
    }

    static func closeMiniPlayer() {
        miniPlayer?.panel.close()
    }

    static func setMiniTint(_ color: Color) {
        if let glass = miniPlayer?.glass { GlassBackdropView.setTint(NSColor(color).withAlphaComponent(0.25), on: glass) }
    }

    static func setMiniPinned(_ pinned: Bool) {
        miniPlayer?.panel.level = pinned ? .floating : .normal
    }

    // MARK: Main window

    /// Set by the menu bar label, which SwiftUI keeps alive for the app's whole lifetime.
    static var openMainWindow: (() -> Void)?

    static func showMain() {
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
    }

    static func showSettings() {
        showMain()
    }
}

/// A title-bar-less Liquid Glass window with a rounded shadow and the real macOS window
/// buttons, which fade in over the top-left corner on hover (like Apple Music's mini player).
@MainActor
private final class GlassPanel {
    let panel: KeyablePanel
    let glass: NSView
    private var closeObserver: NSObjectProtocol?
    private let zoomAction: () -> Void

    init<Content: View>(content: Content, size: CGSize, cornerRadius: CGFloat, autosaveName: String,
                        zoomHelp: String, zoom: @escaping () -> Void, onClose: @escaping () -> Void) {
        zoomAction = zoom
        // Transparent margin so the rounded shadow isn't clipped. The system window shadow is off:
        // it follows the window rectangle and shows up as a dark box around the glass.
        let margin: CGFloat = 24
        let frame = NSRect(x: 0, y: 0, width: size.width + margin * 2, height: size.height + margin * 2)
        let glassFrame = NSRect(x: margin, y: margin, width: size.width, height: size.height)

        panel = KeyablePanel(contentRect: frame, styleMask: [.borderless, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if #unavailable(macOS 15.0) {
            panel.isMovableByWindowBackground = true // no WindowDragGesture before macOS 15
        }

        var buttons: [NSButton] = []
        let container = HoverView(frame: frame, hoverRect: glassFrame) { inside in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                for button in buttons { button.animator().alphaValue = inside ? 1 : 0 }
            }
        }
        container.wantsLayer = true

        let shadow = NSView(frame: glassFrame)
        shadow.wantsLayer = true
        if let layer = shadow.layer {
            layer.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: size),
                                      cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.3
            layer.shadowRadius = 14
            layer.shadowOffset = CGSize(width: 0, height: -6)
        }
        container.addSubview(shadow)

        let hosting = NSHostingView(rootView: content.environment(PlayerHub.shared))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = cornerRadius
        hosting.layer?.cornerCurve = .continuous
        hosting.layer?.masksToBounds = true
        glass = GlassBackdropView.make(frame: glassFrame, cornerRadius: cornerRadius, content: hosting)
        container.addSubview(glass)

        var x = glassFrame.minX + 18
        for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = NSWindow.standardWindowButton(type, for: [.titled, .closable, .miniaturizable, .resizable]) else { continue }
            button.setFrameOrigin(NSPoint(x: x, y: glassFrame.maxY - 18 - button.frame.height))
            x += button.frame.width + 6
            button.alphaValue = 0
            container.addSubview(button)
            buttons.append(button)
        }
        panel.contentView = container

        if let zoomButton = buttons.last {
            zoomButton.toolTip = zoomHelp
        }

        if !panel.setFrameUsingName(autosaveName), let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - frame.width - 4, y: screen.maxY - frame.height))
        }
        panel.setFrameAutosaveName(autosaveName)

        // The green button swaps between the mini and full player.
        if let zoomButton = buttons.last {
            zoomButton.target = self
            zoomButton.action = #selector(zoomPressed)
        }

        // Free the SwiftUI tree (and any artwork video) as soon as the window closes.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.panel.contentView = nil
                if let observer = self.closeObserver { NotificationCenter.default.removeObserver(observer) }
                onClose()
            }
        }
    }

    func show() {
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func zoomPressed() {
        zoomAction()
    }
}

/// Reports when the pointer enters or leaves a region, even while it's over subviews like the window buttons.
private final class HoverView: NSView {
    private let onHover: (Bool) -> Void

    init(frame: NSRect, hoverRect: NSRect, onHover: @escaping (Bool) -> Void) {
        self.onHover = onHover
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: hoverRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
}

/// Borderless panels can't become key by default; Escape closes them.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
