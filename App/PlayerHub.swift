import AppKit
import Observation
import WidgetKit

/// Picks the active music source, mirrors its state into the App Group for the widgets,
/// and routes play/pause/skip commands from widgets and the player windows.
@MainActor
@Observable
final class PlayerHub {
    static let shared = PlayerHub()

    var selection: SourceKind {
        didSet {
            UserDefaults.standard.set(selection.rawValue, forKey: "source")
            if selection == .youtubeMusic { UserDefaults.standard.set(true, forKey: "youtubeInAutomatic") }
            pinnedSource = nil
            Task { await refresh() }
        }
    }

    private(set) var nowPlaying = SharedStore.nowPlaying
    private(set) var artwork: NSImage?
    private(set) var recentItems: [RecentItem] = []
    private(set) var sourceIcon: NSImage?
    private(set) var motion: MotionURLs?
    /// True for a few seconds after an AutoMix/crossfade transition is detected.
    private(set) var isMixing = false

    let sonos = SonosSource()
    @ObservationIgnored private let appleMusic = AppleMusicSource()
    @ObservationIgnored private let spotify = SpotifySource()
    @ObservationIgnored private let youtube = YouTubeMusicSource()
    @ObservationIgnored private var recent = SharedStore.recent
    @ObservationIgnored private var icons: [String: NSImage] = [:]
    @ObservationIgnored private var started = false
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var refreshQueued = false
    @ObservationIgnored private var tick = 0
    @ObservationIgnored private var lastManualSkip = Date.distantPast
    /// Source the user switched to with the widget/mini player switch button (Automatic mode only).
    @ObservationIgnored private var pinnedSource: SourceKind?
    /// Last source Automatic mode showed, so it doesn't flip-flop between players.
    @ObservationIgnored private var automaticPick: SourceKind?
    /// Bumped whenever a source reports a new permission issue, so views re-read `issue(for:)`.
    private var issueStamp = 0

    private init() {
        selection = UserDefaults.standard.string(forKey: "source").flatMap(SourceKind.init) ?? .automatic
        artwork = nowPlaying.isEmpty ? nil : SharedStore.artwork(for: nowPlaying.trackID)
        sourceIcon = icon(for: nowPlaying.sourceAppID)
        rebuildRecentItems()
    }

    /// Local players first: when several are playing, Automatic prefers this Mac over Sonos.
    private var sources: [MusicSource] { [appleMusic, spotify, youtube, sonos] }

    private func source(_ kind: SourceKind) -> MusicSource? {
        sources.first { $0.kind == kind }
    }

    func start() {
        guard !started else { return }
        started = true
        for name in ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"] {
            DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { _ in
                Task { @MainActor in await PlayerHub.shared.refresh() }
            }
        }
        CommandListener.start()
        // Music and Spotify announce changes; browsers and Sonos have to be polled.
        let timer = Timer(timeInterval: 3, repeats: true) { _ in
            Task { @MainActor in PlayerHub.shared.pollTick() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        Task { await refresh() }
    }

    private func pollTick() {
        tick += 1
        let needsFastPoll: Bool = switch selection {
        case .youtubeMusic, .sonos: true
        case .automatic: sonos.isAvailable || (UserDefaults.standard.bool(forKey: "youtubeInAutomatic") && youtube.isAvailable)
        default: false
        }
        if needsFastPoll || tick % 5 == 0 {
            Task { await refresh() }
        }
    }

    func issue(for kind: SourceKind) -> String? {
        _ = issueStamp
        return source(kind)?.issue
    }

    func isAvailable(_ kind: SourceKind) -> Bool {
        kind == .automatic || (source(kind)?.isAvailable ?? false)
    }

    // MARK: Commands

    func handle(_ command: PlayerCommand) {
        if command == .nextSource {
            cycleSource()
        } else if let action = PlayerAction(command) {
            perform(action)
        }
    }

    func perform(_ action: PlayerAction) {
        let kind = nowPlaying.isEmpty ? (selection == .automatic ? automaticPick ?? .appleMusic : selection) : nowPlaying.source
        guard let target = source(kind) else { return }
        if action == .next || action == .previous { lastManualSkip = Date() }
        if action == .playPause, !nowPlaying.isEmpty {
            nowPlaying.state = nowPlaying.isPlaying ? .paused : .playing
            nowPlaying.position = nowPlaying.position(at: Date())
            nowPlaying.capturedAt = Date()
        }
        let current = nowPlaying
        Task {
            await target.perform(action, current: current)
            WidgetCenter.shared.reloadAllTimelines()
            // Browsers and speakers take a moment to apply commands.
            for delay in [0.3, 1.2] {
                try? await Task.sleep(for: .seconds(delay))
                await refresh()
            }
        }
    }

    // MARK: Queue

    func upNext() async -> QueueResult {
        guard !nowPlaying.isEmpty, let source = source(nowPlaying.source) else {
            return .unavailable("Nothing is playing.")
        }
        return await source.upNext()
    }

    func playQueueItem(_ item: QueueItem) {
        guard let source = source(nowPlaying.source) else { return }
        lastManualSkip = Date()
        Task {
            await source.playQueueItem(item)
            for delay in [0.4, 1.5] {
                try? await Task.sleep(for: .seconds(delay))
                await refresh()
            }
        }
    }

    /// Shows the next player that has something loaded (Automatic mode).
    func cycleSource() {
        let active = nowPlaying.availableSources ?? []
        guard active.count > 1 else { return }
        let index = active.firstIndex(of: nowPlaying.source) ?? -1
        pinnedSource = active[(index + 1) % active.count]
        if selection != .automatic { selection = .automatic }
        Task { await refresh() }
    }

    // MARK: State sync

    func refresh() async {
        guard !refreshing else {
            refreshQueued = true
            return
        }
        refreshing = true
        let issuesBefore = sources.map(\.issue)
        let (reading, available) = await currentReading()
        apply(reading, available: available)
        if sources.map(\.issue) != issuesBefore { issueStamp += 1 }
        refreshing = false
        if refreshQueued {
            refreshQueued = false
            await refresh()
        }
    }

    private func currentReading() async -> (SourceReading?, [SourceKind]) {
        guard selection == .automatic else {
            guard let source = source(selection), source.isAvailable, let reading = await source.read() else { return (nil, []) }
            return (reading, [selection])
        }
        var readings: [SourceReading] = []
        // Browsers are only scripted after the user has picked YouTube Music once, to avoid surprise permission prompts.
        let includeYouTube = UserDefaults.standard.bool(forKey: "youtubeInAutomatic")
        for source in sources where source.isAvailable && (source.kind != .youtubeMusic || includeYouTube) {
            if let reading = await source.read() { readings.append(reading) }
        }
        let available = readings.map(\.nowPlaying.source)
        if let pinned = pinnedSource, !available.contains(pinned) { pinnedSource = nil }

        func first(_ match: (NowPlaying) -> Bool) -> SourceReading? {
            readings.first { match($0.nowPlaying) }
        }
        // 1. what the user switched to, 2. something playing on this Mac, 3. something playing anywhere,
        // 4. whatever was shown before, 5. anything paused.
        let pick = first { $0.source == self.pinnedSource }
            ?? first { $0.isPlaying && $0.source != .sonos }
            ?? first { $0.isPlaying }
            ?? first { $0.source == self.automaticPick }
            ?? readings.first
        automaticPick = pick?.nowPlaying.source ?? automaticPick
        return (pick, available)
    }

    private func apply(_ reading: SourceReading?, available: [SourceKind]) {
        let old = nowPlaying
        var np = reading?.nowPlaying ?? .stopped
        if !np.isEmpty {
            np.trackID = Self.stableID("\(np.source.rawValue)|\(np.trackID)")
            np.capturedAt = Date()
            np.availableSources = available
        }
        let trackChanged = np.trackID != old.trackID

        if trackChanged {
            detectMix(from: old, to: np)
            if !old.title.isEmpty { pushRecent(old) }
            motion = nil
            artwork = SharedStore.artwork(for: np.trackID)
            np.tint = artwork.flatMap(Artwork.averageColor)
            if !np.isEmpty {
                if artwork == nil { loadArtwork(reading?.artwork, for: np) }
                lookUpMotion(for: np)
            }
        } else {
            np.tint = old.tint
            // Keep the old timestamp while playback is on schedule so unchanged state compares equal.
            if np.state == old.state, abs(old.position(at: np.capturedAt) - np.position) < 2 {
                np.position = old.position
                np.capturedAt = old.capturedAt
            }
        }
        guard np != old else { return }

        if np.sourceAppID != old.sourceAppID { sourceIcon = icon(for: np.sourceAppID) }
        let seeked = np.capturedAt != old.capturedAt && np.state == old.state && !trackChanged
        let widgetsNeedReload = trackChanged || seeked || np.state != old.state || np.source != old.source
            || np.shuffle != old.shuffle || np.repeatMode != old.repeatMode || np.availableSources != old.availableSources
        nowPlaying = np
        SharedStore.nowPlaying = np
        if widgetsNeedReload { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// Music apps don't report AutoMix/crossfade, so infer it: a song that changed on its own
    /// shortly before it would have ended, with transitions turned on.
    private func detectMix(from old: NowPlaying, to new: NowPlaying) {
        guard old.isPlaying, old.transition != nil, !new.isEmpty, old.source == new.source,
              old.duration > 0, Date().timeIntervalSince(lastManualSkip) > 4 else { return }
        let remaining = old.duration - old.position(at: Date())
        guard remaining > 0.5, remaining < 25 else { return }
        isMixing = true
        Task {
            try? await Task.sleep(for: .seconds(6))
            isMixing = false
        }
    }

    private func pushRecent(_ np: NowPlaying) {
        var list = recent.filter { $0.id != np.trackID }
        list.insert(RecentTrack(id: np.trackID, title: np.title, artist: np.artist), at: 0)
        recent = Array(list.prefix(8))
        SharedStore.recent = recent
        rebuildRecentItems()
    }

    private func rebuildRecentItems() {
        let previous = Dictionary(recentItems.map { ($0.id, $0.image) }, uniquingKeysWith: { a, _ in a })
        recentItems = recent.map { track in
            RecentItem(track: track, image: previous[track.id] ?? SharedStore.artwork(for: track.id).map { Artwork.thumbnail($0, side: 120) })
        }
    }

    private func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = icons[bundleID] { return cached }
        Artwork.saveIcon(for: bundleID)
        let image = SharedStore.icon(for: bundleID)
        icons[bundleID] = image
        return image
    }

    // MARK: Artwork

    private func loadArtwork(_ source: ArtworkSource?, for np: NowPlaying) {
        let id = np.trackID
        if case .data(let data) = source, let image = NSImage(data: data) {
            return adopt(image, id: id)
        }
        if case .loader(let load) = source, let data = load(), let image = NSImage(data: data) {
            return adopt(image, id: id)
        }
        Task {
            var data: Data?
            if case .url(let url) = source {
                data = try? await URLSession.shared.data(from: url).0
            }
            if data.flatMap(NSImage.init(data:)) == nil {
                data = await ITunesSearch.artwork(artist: np.artist, album: np.album, title: np.title)
            }
            guard let data, let image = NSImage(data: data), nowPlaying.trackID == id else { return }
            adopt(image, id: id)
            SharedStore.nowPlaying = nowPlaying
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func adopt(_ image: NSImage, id: String) {
        guard let jpeg = Artwork.jpeg(image, maxSide: 600) else { return }
        try? jpeg.write(to: SharedStore.artworkURL(for: id), options: .atomic)
        artwork = NSImage(data: jpeg)
        if nowPlaying.trackID == id || nowPlaying.isEmpty {
            nowPlaying.tint = artwork.flatMap(Artwork.averageColor)
        }
        pruneArtwork(keeping: id)
    }

    private func lookUpMotion(for np: NowPlaying) {
        let id = np.trackID
        Task {
            let urls = await MotionArtwork.lookup(artist: np.artist, album: np.album, title: np.title)
            if nowPlaying.trackID == id { motion = urls }
        }
    }

    func snapshot(style: GlassStyle) -> PlayerSnapshot {
        PlayerSnapshot(
            nowPlaying: nowPlaying,
            artwork: nowPlaying.isEmpty ? nil : artwork,
            recent: Array(recentItems.prefix(4)),
            style: style,
            sourceIcon: sourceIcon
        )
    }

    private func pruneArtwork(keeping id: String) {
        let keep = Set([id, nowPlaying.trackID] + recent.map(\.id)).map { "\($0).jpg" }
        let dir = SharedStore.artworkDirectory
        for file in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where !keep.contains(file) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
        }
    }

    private static func stableID(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(hash, radix: 16)
    }
}

// MARK: - Darwin notification listener

private enum CommandListener {
    private final class Token {}
    private static let token = Token()

    static func start() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(token).toOpaque()
        for command in PlayerCommand.allCases {
            CFNotificationCenterAddObserver(center, observer, { _, _, name, _, _ in
                guard let raw = name?.rawValue as String?, let command = PlayerCommand(notificationName: raw) else { return }
                Task { @MainActor in PlayerHub.shared.handle(command) }
            }, command.notificationName as CFString, nil, .deliverImmediately)
        }
    }
}
