import AppKit
import SwiftUI

/// AppKit-hosted windows, so a menu bar app can open them from anywhere (widget clicks, menu, reopen).
@MainActor
enum WindowManager {
    private static var playerWindow: NSWindow?
    private static var miniPanel: NSPanel?
    private static var miniGlass: NSGlassEffectView?
    private static var miniButtons: [NSButton] = []

    // MARK: Mini player

    static func showMiniPlayer() {
        let panel = miniPanel ?? makeMiniPanel()
        miniPanel = panel
        playerWindow?.close()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    static func closeMiniPlayer() {
        miniPanel?.close()
    }

    static func setMiniTint(_ color: Color) {
        miniGlass?.tintColor = NSColor(color).withAlphaComponent(0.25)
    }

    static func setMiniButtonsVisible(_ visible: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            for button in miniButtons { button.animator().alphaValue = visible ? 1 : 0 }
        }
    }

    static func setMiniPinned(_ pinned: Bool) {
        miniPanel?.level = pinned ? .floating : .normal
    }

    private static func makeMiniPanel() -> NSPanel {
        let size = MiniPlayerView.size
        // Transparent margin so our rounded shadow isn't clipped. The system window shadow is off:
        // it's computed from the window rectangle and showed up as a dark box around the glass.
        let margin: CGFloat = 24
        let frame = NSRect(x: 0, y: 0, width: size.width + margin * 2, height: size.height + margin * 2)
        let panel = KeyablePanel(contentRect: frame, styleMask: [.borderless, .closable, .miniaturizable, .fullSizeContentView],
                                 backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.level = UserDefaults.standard.object(forKey: "miniPinned") as? Bool == false ? .normal : .floating

        let glassFrame = NSRect(x: margin, y: margin, width: size.width, height: size.height)
        let container = HoverView(frame: frame, hoverRect: glassFrame) { inside in
            WindowManager.setMiniButtonsVisible(inside)
        }
        container.wantsLayer = true
        container.layer?.backgroundColor = .clear

        let cornerRadius: CGFloat = 28
        let shadow = NSView(frame: glassFrame)
        shadow.wantsLayer = true
        if let layer = shadow.layer {
            layer.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: size),
                                      cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.28
            layer.shadowRadius = 14
            layer.shadowOffset = CGSize(width: 0, height: -6)
        }
        container.addSubview(shadow)

        let glass = NSGlassEffectView(frame: glassFrame)
        glass.cornerRadius = cornerRadius
        glass.style = .regular
        let hosting = NSHostingView(rootView: MiniPlayerView().environment(PlayerHub.shared))
        hosting.frame = NSRect(origin: .zero, size: size)
        glass.contentView = hosting
        container.addSubview(glass)

        // The real macOS window buttons, floating over the artwork like Apple Music's mini player.
        miniButtons = []
        var x = glassFrame.minX + 22
        for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = NSWindow.standardWindowButton(type, for: [.titled, .closable, .miniaturizable, .resizable]) else { continue }
            button.setFrameOrigin(NSPoint(x: x, y: glassFrame.maxY - 22 - button.frame.height))
            x += button.frame.width + 6
            button.alphaValue = 0
            if type == .zoomButton {
                button.target = ZoomToFullPlayer.shared
                button.action = #selector(ZoomToFullPlayer.open)
                button.toolTip = "Full Player"
            }
            container.addSubview(button)
            miniButtons.append(button)
        }

        panel.contentView = container
        miniGlass = glass

        // First time: tuck it under the menu bar on the right, where widgets usually live.
        if !panel.setFrameUsingName("MiniPlayer2"), let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - frame.width - 4, y: screen.maxY - frame.height))
        }
        panel.setFrameAutosaveName("MiniPlayer2")
        releaseOnClose(panel) { miniPanel = nil; miniGlass = nil; miniButtons = [] }
        return panel
    }

    // MARK: Full player

    static func showPlayer() {
        let window = playerWindow ?? makeWindow(
            ExpandedPlayerView(),
            size: NSSize(width: 380, height: 700),
            title: "Full Player",
            panel: true
        )
        playerWindow = window
        miniPanel?.close()
        present(window)
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

    private static var closeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

    private static func releaseOnClose(_ window: NSWindow, _ onClose: @escaping @MainActor () -> Void) {
        let key = ObjectIdentifier(window)
        closeObservers[key] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                window.contentView = nil
                onClose()
                if let observer = closeObservers.removeValue(forKey: key) {
                    NotificationCenter.default.removeObserver(observer)
                }
            }
        }
    }

    private static func present(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private static func makeWindow<V: View>(_ view: V, size: NSSize, title: String, panel: Bool) -> NSWindow {
        let hosting = NSHostingView(rootView: view.environment(PlayerHub.shared))
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        let window = panel
            ? KeyablePanel(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
            : NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false // dragging the seek bar must not move the window
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setContentSize(size)
        window.contentMinSize = NSSize(width: 320, height: 600)
        window.center()
        window.setFrameAutosaveName(title)
        if let panel = window as? NSPanel {
            panel.hidesOnDeactivate = false
        }
        releaseOnClose(window) { playerWindow = nil }
        return window
    }
}

/// Reports when the pointer enters or leaves a region, even while it's over subviews like the window buttons.
private final class HoverView: NSView {
    private let hoverRect: NSRect
    private let onHover: (Bool) -> Void

    init(frame: NSRect, hoverRect: NSRect, onHover: @escaping (Bool) -> Void) {
        self.hoverRect = hoverRect
        self.onHover = onHover
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: hoverRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
}

private final class ZoomToFullPlayer: NSObject {
    static let shared = ZoomToFullPlayer()

    @MainActor @objc func open() {
        WindowManager.showPlayer()
    }
}

/// Borderless panels can't become key by default; Escape closes them.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
