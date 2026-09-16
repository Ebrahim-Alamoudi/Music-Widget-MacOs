import ServiceManagement
import SwiftUI
import WidgetKit

enum AppPage: String, CaseIterable, Identifiable {
    case nowPlaying, widgets, sources, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nowPlaying: "Now Playing"
        case .widgets: "Widgets"
        case .sources: "Sources"
        case .general: "General"
        }
    }

    var symbol: String {
        switch self {
        case .nowPlaying: "play.circle.fill"
        case .widgets: "square.grid.2x2.fill"
        case .sources: "hifispeaker.2.fill"
        case .general: "gearshape.fill"
        }
    }
}

@MainActor
@Observable
final class AppNavigation {
    static let shared = AppNavigation()
    var page: AppPage = .nowPlaying
}

struct MainView: View {
    @Environment(PlayerHub.self) private var hub
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        NavigationSplitView {
            List(AppPage.allCases, selection: Binding($navigation.page)) { page in
                Label(page.title, systemImage: page.symbol)
                    .tag(page)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .safeAreaInset(edge: .bottom) { SidebarNowPlaying() }
        } detail: {
            ZStack {
                AppBackdrop()
                switch navigation.page {
                case .nowPlaying: NowPlayingPage()
                case .widgets: WidgetsPage()
                case .sources: SourcesPage()
                case .general: GeneralPage()
                }
            }
            .navigationTitle(navigation.page.title)
            .toolbar {
                ToolbarItemGroup {
                    Button("Mini Player", systemImage: "rectangle.inset.topright.filled") { WindowManager.showMiniPlayer() }
                        .help("Open the floating mini player")
                    Button("Full Player", systemImage: "rectangle.portrait.inset.filled") { WindowManager.showPlayer() }
                        .help("Open the full player")
                }
            }
        }
        .frame(minWidth: 820, minHeight: 560)
    }
}

// MARK: - Shared page chrome

/// Scrollable page with a large title, used by every section.
private struct Page<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(subtitle)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                content
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.automatic)
    }
}

private struct Card<Content: View>: View {
    var title: String?
    var symbol: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label(title, systemImage: symbol ?? "circle")
                    .labelStyle(.titleAndIcon)
                    .font(.system(.headline, design: .rounded))
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

private struct AppBackdrop: View {
    @Environment(PlayerHub.self) private var hub

    var body: some View {
        let tint = (hub.nowPlaying.tint ?? GT.fallbackTint).color
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(colors: [tint.opacity(0.45), tint.opacity(0.08), .clear],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let art = hub.artwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 90)
                    .opacity(0.45)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: hub.nowPlaying.trackID)
    }
}

private struct SidebarNowPlaying: View {
    @Environment(PlayerHub.self) private var hub

    var body: some View {
        let np = hub.nowPlaying
        Button {
            WindowManager.showMiniPlayer()
        } label: {
            HStack(spacing: 10) {
                ArtworkView(image: hub.artwork, tint: (np.tint ?? GT.fallbackTint).color, corner: 8)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(np.isEmpty ? "Not Playing" : np.title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(np.isEmpty ? hub.selection.title : np.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: np.isPlaying ? "waveform" : "pause.fill")
                    .symbolEffect(.variableColor.iterative, isActive: np.isPlaying)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        .padding(10)
        .help("Open the mini player")
    }
}

// MARK: - Now Playing

private struct NowPlayingPage: View {
    @Environment(PlayerHub.self) private var hub

    private var np: NowPlaying { hub.nowPlaying }
    private var tint: Color { (np.tint ?? GT.fallbackTint).color }

    var body: some View {
        Page(title: "Now Playing", subtitle: np.isEmpty ? "Nothing is playing right now." : np.sourceName) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 32) {
                    hero(size: 300)
                    details.frame(minWidth: 340)
                }
                VStack(alignment: .leading, spacing: 24) {
                    hero(size: 260).frame(maxWidth: .infinity)
                    details
                }
            }
            .padding(24)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
            .animation(.spring(duration: 0.5), value: np.isPlaying)
            .animation(.easeInOut(duration: hub.isMixing ? 1.4 : 0.4), value: np.trackID)

            RecentlyPlayedSection()
        }
    }

    private func hero(size: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return ZStack {
            if let art = hub.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [tint, tint.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note").font(.system(size: size * 0.25, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            }
            if let square = hub.motion?.square {
                LoopingVideo(url: square, isPlaying: np.isPlaying)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.white.opacity(0.15), lineWidth: 0.5) }
        .shadow(color: .black.opacity(np.isPlaying ? 0.4 : 0.15), radius: np.isPlaying ? 26 : 10, y: np.isPlaying ? 14 : 5)
        .scaleEffect(np.isPlaying || np.isEmpty ? 1 : 0.88)
        .overlay(alignment: .topLeading) {
            if hub.motion?.square != nil {
                Label("Motion", systemImage: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassEffect(.clear, in: .capsule)
                    .padding(10)
            }
        }
        .id(np.trackID)
        .transition(.opacity)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(np.isEmpty ? "Not Playing" : np.title)
                    .font(.system(size: 28, weight: .bold))
                    .lineLimit(2)
                Text(np.isEmpty ? "Start music in any supported app, or press play." : np.artist)
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !np.album.isEmpty {
                    Text(np.album)
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .id("titles" + np.trackID)
            .transition(.opacity)

            Scrubber(nowPlaying: np) { hub.perform(.seek($0)) }
                .opacity(np.isEmpty ? 0.35 : 1)

            HStack {
                Spacer()
                PlayerGlyph(symbol: "backward.fill", size: 24) { hub.perform(.previous) }
                PlayerGlyph(symbol: np.isPlaying ? "pause.fill" : "play.fill", size: 36) { hub.perform(.playPause) }
                PlayerGlyph(symbol: "forward.fill", size: 24) { hub.perform(.next) }
                Spacer()
            }

            if let volume = np.volume {
                VolumeRow(volume: volume) { hub.perform(.setVolume($0)) }
            }

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    ToggleGlyph(symbol: "shuffle", isOn: np.shuffle == true, isEnabled: np.shuffle != nil) {
                        hub.perform(.toggleShuffle)
                    }
                    ToggleGlyph(symbol: (np.repeatMode ?? .off).symbol, isOn: (np.repeatMode ?? .off) != .off,
                                isEnabled: np.repeatMode != nil) {
                        hub.perform(.cycleRepeat)
                    }
                    if let transition = np.transition {
                        Label(hub.isMixing ? "Mixing…" : transition,
                              systemImage: transition == "AutoMix" ? "infinity" : "arrow.triangle.merge")
                            .symbolEffect(.pulse, options: .repeating, isActive: hub.isMixing)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .glassEffect(hub.isMixing ? .regular.tint(tint.opacity(0.5)) : .regular, in: .capsule)
                    }
                    Spacer(minLength: 0)
                    SourceMenu()
                }
            }
        }
    }
}

private struct RecentlyPlayedSection: View {
    @Environment(PlayerHub.self) private var hub

    var body: some View {
        let items = hub.snapshot(style: .artwork).recent
        VStack(alignment: .leading, spacing: 12) {
            Text("Recently Played")
                .font(.system(.title3, design: .rounded).weight(.semibold))
            if items.isEmpty {
                Text("Songs you play will show up here.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16)], alignment: .leading, spacing: 16) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            ArtworkView(image: item.image, tint: (hub.nowPlaying.tint ?? GT.fallbackTint).color, corner: 12)
                                .aspectRatio(1, contentMode: .fit)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.track.title).font(.system(size: 13, weight: .semibold))
                                Text(item.track.artist).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            .lineLimit(1)
                        }
                        .padding(10)
                        .glassEffect(.regular, in: .rect(cornerRadius: 18))
                    }
                }
            }
        }
    }
}

// MARK: - Widgets

private struct WidgetsPage: View {
    @Environment(PlayerHub.self) private var hub
    @AppStorage("previewStyle") private var style: GlassStyle = .artwork

    var body: some View {
        let snapshot = hub.snapshot(style: style)
        Page(title: "Widgets", subtitle: "Three sizes, three kinds of glass. Click a preview to open the mini player.") {
            Picker("Glass", selection: $style) {
                ForEach(GlassStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)

            // Wraps to fewer columns when the window is narrow.
            FlowLayout(spacing: 24) {
                WidgetPreview(title: "Now Playing · Small", family: .systemSmall, snapshot: snapshot)
                WidgetPreview(title: "Player · Medium", family: .systemMedium, snapshot: snapshot)
                WidgetPreview(title: "Music Deck · Large", family: .systemLarge, snapshot: snapshot)
            }

            Card(title: "Add them to your desktop", symbol: "plus.rectangle.on.rectangle") {
                VStack(alignment: .leading, spacing: 8) {
                    Step(number: 1, text: "Right-click an empty part of the desktop and choose **Edit Widgets**.")
                    Step(number: 2, text: "Search for **GlassTunes** and drag in Now Playing, Player or Music Deck.")
                    Step(number: 3, text: "Right-click a placed widget → **Edit** to pick Artwork Tint, Frosted or Clear.")
                    Step(number: 4, text: "Click a widget any time to open the mini player.")
                }
            }
        }
    }
}

private struct Step: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .frame(width: 20, height: 20)
                .glassEffect(.regular, in: .circle)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Left-to-right layout that wraps onto new rows.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let added = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += added
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

// MARK: - Sources

private struct SourcesPage: View {
    var body: some View {
        Page(title: "Sources", subtitle: "Choose where GlassTunes gets music from.") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    SourcesCard().frame(minWidth: 360)
                    VStack(spacing: 20) {
                        SonosCard()
                        PermissionsCard()
                    }
                    .frame(minWidth: 320)
                }
                VStack(spacing: 20) {
                    SourcesCard()
                    SonosCard()
                    PermissionsCard()
                }
            }
        }
    }
}

private struct SourcesCard: View {
    var body: some View {
        Card(title: "Show music from", symbol: "music.note.list") {
            VStack(spacing: 4) {
                ForEach(SourceKind.allCases) { SourceRow(kind: $0) }
            }
        }
    }
}

private struct SourceRow: View {
    @Environment(PlayerHub.self) private var hub
    let kind: SourceKind

    private var isSelected: Bool { hub.selection == kind }

    var body: some View {
        let issue = hub.issue(for: kind)
        Button {
            hub.selection = kind
        } label: {
            HStack(spacing: 12) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.1))))
                    .foregroundStyle(isSelected ? .white : .primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                    Text(issue ?? status)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(issue == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.tint)
                }
            }
            .padding(10)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(isSelected ? 0.1 : 0)))
        }
        .buttonStyle(.plain)
    }

    private var status: String {
        let np = hub.nowPlaying
        if !np.isEmpty, np.source == kind || (kind == .automatic && isSelected) {
            return "\(np.isPlaying ? "Playing" : "Paused") · \(np.title)"
        }
        switch kind {
        case .automatic: return "Whatever is playing right now"
        case .appleMusic: return hub.isAvailable(kind) ? "Music is open" : "Music isn't open"
        case .spotify: return hub.isAvailable(kind) ? "Spotify is open" : "Spotify isn't open"
        case .youtubeMusic: return "music.youtube.com in Chrome, Safari, Brave or Edge"
        case .sonos: return hub.sonos.selectedRoom.map { "Room: \($0.name)" } ?? "Pick a room in the Sonos card"
        }
    }
}

private struct SonosCard: View {
    @Environment(PlayerHub.self) private var hub
    @State private var manualHost = ""

    var body: some View {
        let sonos = hub.sonos
        Card(title: "Sonos", symbol: "hifispeaker.2.fill") {
            HStack {
                if !sonos.rooms.isEmpty {
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
                } else {
                    Text(sonos.selectedRoom.map { "Using \($0.name)" } ?? "No speakers found yet")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if sonos.isDiscovering {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Find Speakers", systemImage: "magnifyingglass") {
                        Task { await sonos.discover(manualHost: manualHost) }
                    }
                    .buttonStyle(.glass)
                }
            }
            TextField("Speaker IP address (optional)", text: $manualHost)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await sonos.discover(manualHost: manualHost) } }
            if let issue = sonos.issue {
                Text(issue)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            if sonos.rooms.isEmpty { await sonos.discover() }
        }
    }
}

private struct PermissionsCard: View {
    var body: some View {
        Card(title: "Permissions", symbol: "lock.shield") {
            Text("macOS asks once for each app GlassTunes controls. YouTube Music also needs **Allow JavaScript from Apple Events** turned on in the browser (Chrome: View → Developer; Safari: Develop → Developer Settings).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Automation Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                }
                Button("Local Network Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")!)
                }
            }
            .buttonStyle(.glass)
        }
    }
}

// MARK: - General

private struct GeneralPage: View {
    @Environment(PlayerHub.self) private var hub
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("miniPinned") private var miniPinned = true
    @AppStorage("hideDockIcon") private var hideDockIcon = false

    var body: some View {
        Page(title: "General", subtitle: "How GlassTunes behaves on your Mac.") {
            Card(title: "Startup", symbol: "power") {
                Toggle("Open GlassTunes at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        if enabled { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                Text("Keep GlassTunes running so widgets stay up to date and their buttons work.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Card(title: "Windows", symbol: "macwindow") {
                Toggle("Keep the mini player above other windows", isOn: $miniPinned)
                Toggle("Hide the Dock icon (use the menu bar icon instead)", isOn: $hideDockIcon)
                    .onChange(of: hideDockIcon) { _, hide in
                        NSApp.setActivationPolicy(hide ? .accessory : .regular)
                        if hide { WindowManager.showMain() }
                    }
            }
            Card(title: "Widgets", symbol: "square.grid.2x2") {
                HStack {
                    Text("Widgets not updating? Force a refresh.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh Widgets", systemImage: "arrow.clockwise") {
                        Task { await hub.refresh() }
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                    .buttonStyle(.glass)
                }
            }
            Card(title: "About", symbol: "info.circle") {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GlassTunes").font(.system(.title3, design: .rounded).weight(.bold))
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                            .foregroundStyle(.secondary)
                        Link("github.com/Ebrahim-Alamoudi/Music-Widget-MacOs",
                             destination: URL(string: "https://github.com/Ebrahim-Alamoudi/Music-Widget-MacOs")!)
                            .font(.caption)
                    }
                }
            }
        }
    }
}

// MARK: - Widget preview

/// Renders the real widget views at desktop widget sizes.
struct WidgetPreview: View {
    let title: String
    let family: WidgetFamily
    let snapshot: PlayerSnapshot

    private var size: CGSize {
        switch family {
        case .systemSmall: CGSize(width: 170, height: 170)
        case .systemMedium: CGSize(width: 364, height: 170)
        default: CGSize(width: 364, height: 382)
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
            Button {
                WindowManager.showMiniPlayer()
            } label: {
                GlassTunesWidgetView(family: family, snapshot: snapshot)
                    .padding(16)
                    .frame(width: size.width, height: size.height)
                    .background { GlassBackdrop(snapshot: snapshot) }
                    .clipShape(shape)
                    .overlay { shape.strokeBorder(.white.opacity(0.25), lineWidth: 0.8) }
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
            }
            .buttonStyle(.plain)
        }
    }
}
