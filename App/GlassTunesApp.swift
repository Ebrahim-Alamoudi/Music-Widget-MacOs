import SwiftUI

@main
struct GlassTunesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var hub = PlayerHub.shared
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some Scene {
        Window("GlassTunes", id: "main") {
            MainView()
                .environment(hub)
        }
        .defaultSize(width: 1120, height: 740)
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

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarContent()
                .environment(hub)
        } label: {
            MenuBarLabel(nowPlaying: hub.nowPlaying)
        }
    }
}

/// Always alive, so it's where we grab SwiftUI's `openWindow` for AppKit callers.
private struct MenuBarLabel: View {
    let nowPlaying: NowPlaying
    @AppStorage("menuBarStyle") private var style: MenuBarStyle = .iconOnly
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let icon = Image(systemName: nowPlaying.isPlaying ? "music.note" : "music.note.list")
        Group {
            switch style {
            case .iconOnly: icon
            case .textOnly: Text(text)
            case .iconAndText: HStack(spacing: 4) { icon; Text(text) }
            }
        }
        .onAppear { WindowManager.openMainWindow = { openWindow(id: "main") } }
    }

    /// "Title — Artist", kept short so it doesn't crowd the menu bar.
    private var text: String {
        guard !nowPlaying.isEmpty else { return "Not Playing" }
        let full = nowPlaying.artist.isEmpty ? nowPlaying.title : "\(nowPlaying.title) — \(nowPlaying.artist)"
        return full.count > 32 ? String(full.prefix(31)) + "…" : full
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
