import ServiceManagement
import SwiftUI
import WidgetKit

/// One-page main window: Now Playing on the left, native grouped settings on the right.
struct MainView: View {
    @Environment(PlayerHub.self) private var hub
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var hub = hub
        HStack(spacing: 0) {
            NowPlayingPanel()
                .frame(width: 330)
                .frame(maxHeight: .infinity)
                .background(.background.secondary.opacity(0.55))
            Divider()
            HStack(alignment: .top, spacing: 0) {
                Form {
                    SourceSection()
                    SonosSection()
                    AboutSection()
                }
                .frame(minWidth: 360)
                Form {
                    WidgetsSection()
                    GeneralSection()
                }
                .frame(minWidth: 360)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 1060, minHeight: 680)
        // macOS 27 look: no solid title bar. Content runs underneath, toolbar controls float on glass,
        // and the window itself is translucent so the title bar area matches everything else.
        .translucentWindowChrome()
        // The menu bar icon normally provides this, but it can be hidden.
        .onAppear { WindowManager.openMainWindow = { [openWindow] in openWindow(id: "main") } }
        .navigationTitle("GlassTunes")
        .navigationSubtitle(hub.nowPlaying.isEmpty ? "Not Playing" : hub.nowPlaying.sourceName)
        .toolbar {
            ToolbarItem {
                MenuBarToolbarMenu()
            }
            ToolbarItemGroup {
                Button("Mini Player", systemImage: "pip") { WindowManager.showMiniPlayer() }
                    .help("Open the floating mini player (⇧⌘P)")
                Button("Full Player", systemImage: "rectangle.portrait") { WindowManager.showPlayer() }
                    .help("Open the full player (⇧⌘F)")
            }
        }
    }
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case iconAndText, iconOnly, textOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iconAndText: "Icon and Text"
        case .iconOnly: "Icon Only"
        case .textOnly: "Text Only"
        }
    }
}

/// Toolbar button for how GlassTunes appears in the menu bar.
private struct MenuBarToolbarMenu: View {
    @AppStorage("menuBarStyle") private var style: MenuBarStyle = .iconOnly
    @AppStorage("showMenuBarIcon") private var showInMenuBar = true

    var body: some View {
        Menu {
            Picker("Menu Bar Shows", selection: Binding(
                get: { style },
                set: { style = $0; showInMenuBar = true }
            )) {
                ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "menubar.rectangle")
                Text(showInMenuBar ? style.title : "Hidden")
            }
        }
        .menuIndicator(.visible)
        .fixedSize()
        .help("How GlassTunes appears in the menu bar. Hide it completely in General.")
    }
}

// MARK: - Now Playing

private struct NowPlayingPanel: View {
    @Environment(PlayerHub.self) private var hub

    private var np: NowPlaying { hub.nowPlaying }

    var body: some View {
        VStack(spacing: 14) {
            artwork
                .frame(maxWidth: 280, maxHeight: 280)
                .layoutPriority(-1)

            VStack(spacing: 2) {
                Text(np.isEmpty ? "Not Playing" : np.title)
                    .font(.title3.bold())
                Text(np.isEmpty ? "Play something in \(hub.selection == .automatic ? "any supported app" : hub.selection.title)" : np.artist)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity)

            Scrubber(nowPlaying: np) { hub.perform(.seek($0)) }
                .disabled(np.isEmpty)

            HStack {
                ToggleGlyph(symbol: "shuffle", isOn: np.shuffle == true, isEnabled: np.shuffle != nil) {
                    hub.perform(.toggleShuffle)
                }
                Spacer(minLength: 0)
                PlayerGlyph(symbol: "backward.fill", size: 20) { hub.perform(.previous) }
                PlayerGlyph(symbol: np.isPlaying ? "pause.fill" : "play.fill", size: 30) { hub.perform(.playPause) }
                PlayerGlyph(symbol: "forward.fill", size: 20) { hub.perform(.next) }
                Spacer(minLength: 0)
                ToggleGlyph(symbol: (np.repeatMode ?? .off).symbol, isOn: (np.repeatMode ?? .off) != .off,
                            isEnabled: np.repeatMode != nil) {
                    hub.perform(.cycleRepeat)
                }
            }

            if let volume = np.volume {
                VolumeRow(volume: volume) { hub.perform(.setVolume($0)) }
            }

            HStack {
                if let transition = np.transition {
                    Label(hub.isMixing ? "Mixing into the next song" : "\(transition) is on",
                          systemImage: transition == "AutoMix" ? "infinity" : "arrow.triangle.merge")
                        .symbolEffect(.pulse, options: .repeating, isActive: hub.isMixing)
                        .font(.caption)
                        .foregroundStyle(hub.isMixing ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                }
                Spacer(minLength: 0)
                QueueButton(size: 32)
                    .disabled(np.isEmpty)
            }

            Divider()
            RecentStripView()
        }
        .padding(20)
        .animation(.spring(duration: 0.4), value: np.isPlaying)
        .animation(.easeInOut(duration: hub.isMixing ? 1.2 : 0.3), value: np.trackID)
    }

    private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack {
                    if let art = hub.artwork {
                        Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(.quaternary)
                        Image(systemName: "music.note")
                            .font(.system(size: 64, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    if let square = hub.motion?.square {
                        LoopingVideo(url: square, isPlaying: np.isPlaying, maxPixels: 600)
                    }
                }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(.separator, lineWidth: 0.5) }
            .shadow(color: .black.opacity(np.isPlaying ? 0.25 : 0.1), radius: np.isPlaying ? 16 : 6, y: np.isPlaying ? 8 : 3)
            .scaleEffect(np.isPlaying || np.isEmpty ? 1 : 0.9)
            .id(np.trackID)
            .transition(.opacity)
    }
}

private struct RecentStripView: View {
    @Environment(PlayerHub.self) private var hub
    private let slots = 5

    var body: some View {
        let items = Array(hub.recentItems.prefix(slots))
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recently Played")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if items.isEmpty {
                    Text("Nothing yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.secondary)

            // Equal squares that always fill the panel width; empty slots keep the row balanced.
            HStack(spacing: 8) {
                ForEach(0..<slots, id: \.self) { index in
                    let item = index < items.count ? items[index] : nil
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            if let image = item?.image {
                                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Rectangle().fill(.quaternary.opacity(item == nil ? 0.5 : 1))
                                    .overlay {
                                        if item != nil {
                                            Image(systemName: "music.note").foregroundStyle(.tertiary)
                                        }
                                    }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
                        }
                        .help(item.map { "\($0.track.title) — \($0.track.artist)" } ?? "")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Settings sections

private struct SourceSection: View {
    @Environment(PlayerHub.self) private var hub

    var body: some View {
        Section("Show Music From") {
            ForEach(SourceKind.allCases) { SourceRow(kind: $0) }
        }
    }
}

private struct SourceRow: View {
    @Environment(PlayerHub.self) private var hub
    let kind: SourceKind

    var body: some View {
        let issue = hub.issue(for: kind)
        let selected = hub.selection == kind
        Button {
            hub.selection = kind
        } label: {
            HStack(spacing: 10) {
                Image(systemName: kind.symbol)
                    .frame(width: 20)
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.title)
                    Text(issue ?? status)
                        .font(.caption)
                        .foregroundStyle(issue == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
            .animation(.spring(duration: 0.35, bounce: 0.5), value: selected)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.alignment, trigger: selected)
        .help(issue ?? "")
    }

    private var status: String {
        let np = hub.nowPlaying
        if !np.isEmpty, np.source == kind || (kind == .automatic && hub.selection == .automatic) {
            return "\(np.isPlaying ? "Playing" : "Paused") · \(np.title)"
        }
        switch kind {
        case .automatic: return "Whatever is playing right now"
        case .appleMusic: return hub.isAvailable(kind) ? "Music is open" : "Music isn't open"
        case .spotify: return hub.isAvailable(kind) ? "Spotify is open" : "Spotify isn't open"
        case .youtubeMusic: return "A music.youtube.com tab in Chrome, Safari, Brave or Edge"
        case .sonos: return hub.sonos.selectedRoom.map { "Room: \($0.name)" } ?? "Choose a room below"
        }
    }
}

private struct SonosSection: View {
    @Environment(PlayerHub.self) private var hub
    @State private var manualHost = ""

    var body: some View {
        let sonos = hub.sonos
        Section {
            LabeledContent("Room") {
                HStack {
                    if sonos.rooms.isEmpty {
                        Text(sonos.selectedRoom?.name ?? "None found")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Room", selection: Binding(
                            get: { sonos.selectedRoom?.id },
                            set: { id in
                                sonos.selectedRoom = sonos.rooms.first { $0.id == id }
                                if hub.selection != .automatic { hub.selection = .sonos }
                            }
                        )) {
                            Text("None").tag(String?.none)
                            ForEach(sonos.rooms) { Text($0.name).tag(Optional($0.id)) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    if sonos.isDiscovering {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Find") { Task { await sonos.discover(manualHost: manualHost) } }
                    }
                }
            }
            TextField("Speaker IP", text: $manualHost, prompt: Text("Optional"))
                .onSubmit { Task { await sonos.discover(manualHost: manualHost) } }
        } header: {
            Text("Sonos")
        } footer: {
            if let issue = sonos.issue {
                Text(issue).foregroundStyle(.orange)
            }
        }
    }
}

private struct AboutSection: View {
    var body: some View {
        Section {
            LabeledContent("Permissions") {
                HStack {
                    Button("Automation") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                    }
                    Button("Local Network") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")!)
                    }
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("YouTube Music also needs Allow JavaScript from Apple Events — Chrome: View › Developer. Safari: Develop › Developer Settings.")
                HStack(spacing: 4) {
                    Text("GlassTunes \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") ·")
                    Link("GitHub", destination: URL(string: "https://github.com/Ebrahim-Alamoudi/Music-Widget-MacOs")!)
                }
            }
        }
    }
}

private struct WidgetsSection: View {
    @Environment(PlayerHub.self) private var hub
    @AppStorage("previewStyle") private var style: GlassStyle = .artwork
    @AppStorage("previewFamily") private var familyIndex = 1

    private let families: [(String, WidgetFamily)] = [("Small", .systemSmall), ("Medium", .systemMedium), ("Large", .systemLarge)]

    var body: some View {
        Section {
            VStack(spacing: 10) {
                Picker("Glass", selection: $style) {
                    ForEach(GlassStyle.allCases) { style in
                        Text(style == .artwork ? "Artwork" : style.title).tag(style)
                    }
                }
                Picker("Size", selection: $familyIndex) {
                    ForEach(families.indices, id: \.self) { Text(families[$0].0).tag($0) }
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)

            ScaledWidgetPreview(family: families[min(familyIndex, 2)].1, snapshot: hub.snapshot(style: style))
        } header: {
            Text("Widgets")
        } footer: {
            Text("Right-click the desktop › Edit Widgets › GlassTunes. Right-click a widget › Edit to change its glass.")
        }
    }
}

private struct GeneralSection: View {
    @Environment(PlayerHub.self) private var hub
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("miniPinned") private var miniPinned = true
    @AppStorage("hideDockIcon") private var hideDockIcon = false
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some View {
        Section {
            Toggle("Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    if enabled { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            Toggle("Keep mini player on top", isOn: $miniPinned)
            Toggle("Show in menu bar", isOn: $showMenuBarIcon)
            Toggle("Hide Dock icon", isOn: $hideDockIcon)
                .onChange(of: hideDockIcon) { _, hide in
                    NSApp.setActivationPolicy(hide ? .accessory : .regular)
                    if hide { WindowManager.showMain() }
                }
            LabeledContent("Widgets not updating?") {
                Button("Refresh") {
                    Task { await hub.refresh() }
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        } header: {
            Text("General")
        } footer: {
            if hideDockIcon && !showMenuBarIcon {
                Text("GlassTunes is hidden from the Dock and the menu bar. Open it from Applications or Spotlight to get back here.")
            }
        }
    }
}

// MARK: - Widget preview

/// The real widget view at its desktop size, scaled to fit a fixed-height box so the section never jumps.
private struct ScaledWidgetPreview: View {
    let family: WidgetFamily
    let snapshot: PlayerSnapshot
    private let boxHeight: CGFloat = 190

    private var size: CGSize {
        switch family {
        case .systemSmall: CGSize(width: 170, height: 170)
        case .systemMedium: CGSize(width: 364, height: 170)
        default: CGSize(width: 364, height: 382)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / size.width, geo.size.height / size.height, 1)
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
            GlassTunesWidgetView(family: family, snapshot: snapshot)
                .environment(\.isStaticWidgetPreview, true)
                .padding(16)
                .frame(width: size.width, height: size.height)
                .background { GlassBackdrop(snapshot: snapshot) }
                .clipShape(shape)
                .overlay { shape.strokeBorder(.separator, lineWidth: 0.5) }
                .scaleEffect(scale, anchor: .center)
                .frame(width: geo.size.width, height: geo.size.height)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .contentShape(Rectangle())
                .onTapGesture { WindowManager.showMiniPlayer() }
                .help("Click to open the mini player")
        }
        .frame(height: boxHeight)
        .padding(.vertical, 4)
    }
}
