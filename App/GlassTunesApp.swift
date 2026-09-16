import SwiftUI

@main
struct GlassTunesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var hub = PlayerHub.shared
    @State private var navigation = AppNavigation.shared

    var body: some Scene {
        Window("GlassTunes", id: "main") {
            MainView()
                .environment(hub)
                .environment(navigation)
        }
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { WindowManager.showSettings() }
                    .keyboardShortcut(",")
            }
            CommandMenu("Playback") {
                Button("Play/Pause") { hub.perform(.playPause) }
                    .keyboardShortcut(.space, modifiers: [.option])
                Button("Next Track") { hub.perform(.next) }
                    .keyboardShortcut(.rightArrow)
                Button("Previous Track") { hub.perform(.previous) }
                    .keyboardShortcut(.leftArrow)
                Divider()
                Button("Shuffle") { hub.perform(.toggleShuffle) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Repeat") { hub.perform(.cycleRepeat) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Button("Mini Player") { WindowManager.showMiniPlayer() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Full Player") { WindowManager.showPlayer() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(hub)
        } label: {
            MenuBarLabel(isPlaying: hub.nowPlaying.isPlaying)
        }
    }
}

/// Always alive, so it's where we grab SwiftUI's `openWindow` for AppKit callers.
private struct MenuBarLabel: View {
    let isPlaying: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: isPlaying ? "music.note" : "music.note.list")
            .onAppear { WindowManager.openMainWindow = { openWindow(id: "main") } }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        if UserDefaults.standard.bool(forKey: "hideDockIcon") {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        PlayerHub.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // Keep running in the menu bar so widgets stay live.
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowManager.showMain() }
        return true
    }

    /// Clicking a widget opens `glasstunes://player`.
    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.scheme == "glasstunes" }) {
            WindowManager.showMiniPlayer()
        }
    }
}

struct MenuBarContent: View {
    @Environment(PlayerHub.self) private var hub

    var body: some View {
        @Bindable var hub = hub
        let np = hub.nowPlaying
        if np.isEmpty {
            Text("Not Playing")
        } else {
            Text(np.title)
            Text("\(np.artist) · \(np.sourceName)")
        }
        Divider()
        Button(np.isPlaying ? "Pause" : "Play") { hub.perform(.playPause) }
        Button("Next Track") { hub.perform(.next) }
        Button("Previous Track") { hub.perform(.previous) }
        Divider()
        Picker("Source", selection: $hub.selection) {
            ForEach(SourceKind.allCases) { Text($0.title).tag($0) }
        }
        Divider()
        Button("Mini Player") { WindowManager.showMiniPlayer() }
        Button("Full Player") { WindowManager.showPlayer() }
        Button("Open GlassTunes") { WindowManager.showMain() }
        Button("Settings…") { WindowManager.showSettings() }
        Divider()
        Button("Quit GlassTunes") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
