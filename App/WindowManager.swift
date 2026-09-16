import AppKit
import SwiftUI

/// AppKit-hosted windows, so a menu bar app can open them from anywhere (widget clicks, menu, reopen).
@MainActor
enum WindowManager {
    private static var playerWindow: NSWindow?
    private static var miniPanel: NSPanel?
    private static var miniGlass: NSGlassEffectView?

    // MARK: Mini player

    static func showMiniPlayer() {
        let panel = miniPanel ?? makeMiniPanel()
        miniPanel = panel
        playerWindow?.orderOut(nil)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    static func closeMiniPlayer() {
        miniPanel?.orderOut(nil)
    }

    static func setMiniTint(_ color: Color) {
        miniGlass?.tintColor = NSColor(color).withAlphaComponent(0.25)
    }

    static func setMiniPinned(_ pinned: Bool) {
        miniPanel?.level = pinned ? .floating : .normal
    }

    private static func makeMiniPanel() -> NSPanel {
        let size = MiniPlayerView.size
        let panel = KeyablePanel(contentRect: NSRect(origin: .zero, size: size),
                                 styleMask: [.borderless, .fullSizeContentView],
                                 backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.level = UserDefaults.standard.object(forKey: "miniPinned") as? Bool == false ? .normal : .floating

        let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
        glass.cornerRadius = 28
        glass.style = .regular
        glass.autoresizingMask = [.width, .height]
        let hosting = NSHostingView(rootView: MiniPlayerView().environment(PlayerHub.shared))
        hosting.frame = glass.bounds
        glass.contentView = hosting
        panel.contentView = glass
        miniGlass = glass

        // First time: tuck it under the menu bar on the right, where widgets usually live.
        if !panel.setFrameUsingName("MiniPlayer"), let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 20, y: screen.maxY - size.height - 16))
        }
        panel.setFrameAutosaveName("MiniPlayer")
        return panel
    }

    // MARK: Full player

    static func showPlayer() {
        let window = playerWindow ?? makeWindow(
            ExpandedPlayerView(),
            size: NSSize(width: 360, height: 660),
            title: "Now Playing",
            panel: true
        )
        playerWindow = window
        miniPanel?.orderOut(nil)
        present(window)
    }

    // MARK: Main window

    /// Set by the menu bar label, which SwiftUI keeps alive for the app's whole lifetime.
    static var openMainWindow: (() -> Void)?

    static func showMain(page: AppPage? = nil) {
        if let page { AppNavigation.shared.page = page }
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
    }

    static func showSettings() {
        showMain(page: .general)
    }

    private static func present(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private static func makeWindow<V: View>(_ view: V, size: NSSize, title: String, panel: Bool) -> NSWindow {
        let hosting = NSHostingView(rootView: view.environment(PlayerHub.shared))
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        let window = panel
            ? KeyablePanel(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
            : NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setContentSize(size)
        window.center()
        window.setFrameAutosaveName(title)
        if let panel = window as? NSPanel {
            panel.hidesOnDeactivate = false
        }
        return window
    }
}

/// Borderless panels can't become key by default; Escape closes them.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}
