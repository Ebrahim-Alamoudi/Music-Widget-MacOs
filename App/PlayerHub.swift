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
    /// Up Next for the current song, fetched ahead of time so the queue opens instantly.
    private(set) var queue: QueueResult?
    /// Queue thumbnails by item ID, filled in as they load.
    private(set) var queueImages: [String: NSImage] = [:]
    @ObservationIgnored private var queueTrackID = ""
    @ObservationIgnored private var queueTask: Task<Void, Never>?

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
    /// Shuffle/repeat the user just chose; kept briefly while the player catches up.
    @ObservationIgnored private var pendingToggle: (shuffle: Bool?, repeatMode: RepeatMode?, until: Date)?
    /// Volume the user is dragging to; shown right away and sent without piling up commands.
    @ObservationIgnored private var pendingVolume: (value: Int, until: Date)?
    @ObservationIgnored private var volumeTask: Task<Void, Never>?
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
        switch command {
        case .nextSource:
            cycleSource()
        case .volumeDown, .volumeUp:
            guard let volume = nowPlaying.volume else { return }
            setVolume(volume + (command == .volumeUp ? 6 : -6))
            ControlHUD.show(.volume)
        case .seek:
            guard let fraction = SharedStore.commandValue, nowPlaying.duration > 0 else { return }
            perform(.seek(min(1, max(0, fraction)) * nowPlaying.duration))
            ControlHUD.show(.seek)
        case .setVolume:
            guard let level = SharedStore.commandValue else { return }
            setVolume(Int(level))
            // Widgets can't be dragged, so offer a real slider right where the user clicked.
            ControlHUD.show(.volume)
        default:
            guard let action = PlayerAction(command) else { return }
            perform(action)
        }
    }

    func perform(_ action: PlayerAction) {
        if case .setVolume(let value) = action {
            return setVolume(value)
        }
        let kind = nowPlaying.isEmpty ? (selection == .automatic ? automaticPick ?? .appleMusic : selection) : nowPlaying.source
        guard let target = source(kind) else { return }
        if action == .next || action == .previous { lastManualSkip = Date() }
        // Capture the state *before* any optimistic change: Sonos derives Play/Pause and the new
        // play mode from it, so a pre-flipped value would send the opposite command.
        let current = nowPlaying
        if action == .toggleShuffle || action == .cycleRepeat {
            if action == .toggleShuffle, let shuffle = nowPlaying.shuffle {
                nowPlaying.shuffle = !shuffle
            }
            if action == .cycleRepeat, let mode = nowPlaying.repeatMode {
                // Spotify only has repeat on/off.
                nowPlaying.repeatMode = switch mode {
                case .off: .all
                case .all: nowPlaying.source == .spotify ? .off : .one
                case .one: .off
                }
            }
            pendingToggle = (nowPlaying.shuffle, nowPlaying.repeatMode, Date().addingTimeInterval(2.5))
            SharedStore.nowPlaying = nowPlaying
        }
        if action == .playPause, !nowPlaying.isEmpty {
            nowPlaying.state = nowPlaying.isPlaying ? .paused : .playing
            nowPlaying.position = nowPlaying.position(at: Date())
            nowPlaying.capturedAt = Date()
        }
        Task {
            await target.perform(action, current: current)
            reloadWidgets()
            // Browsers and speakers take a moment to apply commands.
            for delay in [0.3, 1.2] {
                try? await Task.sleep(for: .seconds(delay))
                await refresh()
            }
        }
    }

    /// Coalesces volume changes: at most one command in flight, always sending the newest value.
    func setVolume(_ value: Int) {
        let volume = min(100, max(0, value))
        guard !nowPlaying.isEmpty, let target = source(nowPlaying.source), nowPlaying.volume != volume else { return }
        nowPlaying.volume = volume
        pendingVolume = (volume, Date().addingTimeInterval(2))
        guard volumeTask == nil else { return }
        volumeTask = Task {
            var sent: Int?
            while let latest = pendingVolume?.value, latest != sent {
                sent = latest
                await target.perform(.setVolume(latest), current: nowPlaying)
                try? await Task.sleep(for: .milliseconds(60))
            }
            volumeTask = nil
            SharedStore.nowPlaying = nowPlaying
            reloadWidgets()
        }
    }

    // MARK: Play again

    /// Whether this past song can be started again (Apple Music and Spotify can; others can't).
    func canPlayAgain(_ track: RecentTrack) -> Bool {
        guard let kind = track.source, let source = source(kind), source.isAvailable else { return false }
        return source.canPlayAgain(track)
    }

    func playAgain(_ track: RecentTrack) {
        guard let kind = track.source, let source = source(kind), source.canPlayAgain(track) else { return }
        lastManualSkip = Date()
        Task {
            await source.playAgain(track)
            for delay in [0.4, 1.2] {
                try? await Task.sleep(for: .seconds(delay))
                await refresh()
            }
        }
    }

    // MARK: Queue

    /// Loads Up Next for the current song. Concurrent calls share one request.
    func refreshQueue() async {
        guard !nowPlaying.isEmpty, let source = source(nowPlaying.source) else {
            queue = .unavailable("Nothing is playing.")
            queueTrackID = nowPlaying.trackID
            return
        }
        if let queueTask { return await queueTask.value }
        let trackID = nowPlaying.trackID
        let task = Task {
            let result = await source.upNext()
            guard nowPlaying.trackID == trackID else { return }
            if case .items(let items) = result {
                // Show anything already cached in the same update as the list.
                queueImages = Dictionary(items.compactMap { item in QueueArtwork.cached(item).map { (item.id, $0) } },
                                         uniquingKeysWith: { a, _ in a })
            }
            queue = result
            queueTrackID = trackID
            if case .items(let items) = result {
                await QueueArtwork.load(items) { id, image in
                    guard self.queueTrackID == trackID, self.queueImages[id] == nil else { return }
                    self.queueImages[id] = image
                }
            }
        }
        queueTask = task
        await task.value
        queueTask = nil
    }

    /// The cached queue, if it belongs to the song that's playing now.
    var currentQueue: QueueResult? {
        queueTrackID == nowPlaying.trackID ? queue : nil
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
            np.sourceTrackID = np.trackID
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
            queue = nil
        } else {
            np.tint = old.tint
            if let pending = pendingVolume {
                if Date() < pending.until { np.volume = pending.value } else { pendingVolume = nil }
            }
            if let pending = pendingToggle {
                if Date() < pending.until {
                    np.shuffle = pending.shuffle
                    np.repeatMode = pending.repeatMode
                } else {
                    pendingToggle = nil
                }
            }
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
            || np.volume != old.volume
        nowPlaying = np
        SharedStore.nowPlaying = np
        if widgetsNeedReload {
            if trackChanged, !np.isEmpty, artwork == nil {
                // Wait for the cover so the widget redraws once, with artwork.
                waitForArtworkThenReload(trackID: np.trackID)
            } else {
                reloadWidgets()
            }
        }
        NowPlayingPublisher.update(np, artwork: artwork)
        // Warm the queue in the background so opening it is instant (Spotify has none to fetch).
        if trackChanged, !np.isEmpty, np.source != .spotify {
            Task { await refreshQueue() }
        }
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
        list.insert(RecentTrack(id: np.trackID, title: np.title, artist: np.artist,
                                source: np.source, sourceTrackID: np.sourceTrackID), at: 0)
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

    // MARK: Widget reloads

    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var artworkWaitID: String?

    /// macOS limits how often a background app may reload widgets, so bursts are merged into one.
    func reloadWidgets() {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func waitForArtworkThenReload(trackID: String) {
        artworkWaitID = trackID
        Task {
            try? await Task.sleep(for: .seconds(4))
            // No cover after 4 seconds: show the song anyway.
            finishArtworkWait(for: trackID)
        }
    }

    private func finishArtworkWait(for trackID: String) {
        guard artworkWaitID == trackID else { return }
        artworkWaitID = nil
        reloadWidgets()
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
            guard let data, let image = NSImage(data: data), nowPlaying.trackID == id else {
                if nowPlaying.trackID == id { finishArtworkWait(for: id) }
                return
            }
            adopt(image, id: id)
            SharedStore.nowPlaying = nowPlaying
            // Redraw with the cover whether or not the 4-second wait already ran out.
            artworkWaitID = nil
            reloadWidgets()
        }
    }

    private func adopt(_ image: NSImage, id: String) {
        guard let jpeg = Artwork.jpeg(image, maxSide: 600) else { return }
        try? jpeg.write(to: SharedStore.artworkURL(for: id), options: .atomic)
        artwork = NSImage(data: jpeg)
        if nowPlaying.trackID == id || nowPlaying.isEmpty {
            nowPlaying.tint = artwork.flatMap(Artwork.averageColor)
            NowPlayingPublisher.update(nowPlaying, artwork: artwork)
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
