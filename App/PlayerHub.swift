import AppKit
import Observation
import WidgetKit

/// Picks the active music source, mirrors its state into the App Group for the widgets,
/// and routes play/pause/skip commands from widgets and the player window.
@MainActor
@Observable
final class PlayerHub {
    static let shared = PlayerHub()

    var selection: SourceKind {
        didSet {
            UserDefaults.standard.set(selection.rawValue, forKey: "source")
            if selection == .youtubeMusic { UserDefaults.standard.set(true, forKey: "youtubeInAutomatic") }
            Task { await refresh() }
        }
    }

    private(set) var nowPlaying = SharedStore.nowPlaying
    private(set) var artwork: NSImage?
    private(set) var recent = SharedStore.recent
    private(set) var motion: MotionURLs?
    /// True for a few seconds after an AutoMix/crossfade transition is detected.
    private(set) var isMixing = false

    let sonos = SonosSource()
    @ObservationIgnored private let appleMusic = AppleMusicSource()
    @ObservationIgnored private let spotify = SpotifySource()
    @ObservationIgnored private let youtube = YouTubeMusicSource()
    @ObservationIgnored private var thumbnails: [String: NSImage] = [:]
    @ObservationIgnored private var started = false
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var refreshQueued = false
    @ObservationIgnored private var lastManualSkip = Date.distantPast
    @ObservationIgnored private var automaticPick: SourceKind?
    /// Bumped whenever a source reports a new permission issue, so views re-read `issue(for:)`.
    private var issueStamp = 0

    private init() {
        selection = UserDefaults.standard.string(forKey: "source").flatMap(SourceKind.init) ?? .automatic
        artwork = nowPlaying.isEmpty ? nil : SharedStore.artwork(for: nowPlaying.trackID)
    }

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
        // Browsers and Sonos don't announce changes, so poll.
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in await PlayerHub.shared.refresh() }
        }
        Task { await refresh() }
    }

    func issue(for kind: SourceKind) -> String? {
        _ = issueStamp
        return source(kind)?.issue
    }

    func isAvailable(_ kind: SourceKind) -> Bool {
        kind == .automatic || (source(kind)?.isAvailable ?? false)
    }

    // MARK: Commands

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

    // MARK: State sync

    func refresh() async {
        guard !refreshing else {
            refreshQueued = true
            return
        }
        refreshing = true
        let issuesBefore = sources.map(\.issue)
        let reading = await currentReading()
        apply(reading)
        if sources.map(\.issue) != issuesBefore { issueStamp += 1 }
        refreshing = false
        if refreshQueued {
            refreshQueued = false
            await refresh()
        }
    }

    private func currentReading() async -> SourceReading? {
        guard selection == .automatic else {
            guard let source = source(selection), source.isAvailable else { return nil }
            return await source.read()
        }
        var readings: [SourceReading] = []
        // Browsers are only scripted after the user has picked YouTube Music once, to avoid surprise permission prompts.
        let includeYouTube = UserDefaults.standard.bool(forKey: "youtubeInAutomatic")
        for source in sources where source.isAvailable && (source.kind != .youtubeMusic || includeYouTube) {
            if let reading = await source.read() { readings.append(reading) }
        }
        // Prefer whatever is playing, sticking with the current pick when several are.
        let pick = readings.first { $0.nowPlaying.isPlaying && $0.nowPlaying.source == automaticPick }
            ?? readings.first { $0.nowPlaying.isPlaying }
            ?? readings.first { $0.nowPlaying.source == automaticPick }
            ?? readings.first
        automaticPick = pick?.nowPlaying.source ?? automaticPick
        return pick
    }

    private func apply(_ reading: SourceReading?) {
        let old = nowPlaying
        var np = reading?.nowPlaying ?? .stopped
        if !np.isEmpty {
            np.trackID = Self.stableID("\(np.source.rawValue)|\(np.trackID)")
            np.capturedAt = Date()
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
        }
        if let appID = np.sourceAppID { Artwork.saveIcon(for: appID) }

        let seeked = old.isPlaying && np.isPlaying && abs(old.position(at: Date()) - np.position) > 3
        let changed = trackChanged || seeked
            || np.state != old.state || np.source != old.source
            || np.shuffle != old.shuffle || np.repeatMode != old.repeatMode
        nowPlaying = np
        SharedStore.nowPlaying = np
        if changed { WidgetCenter.shared.reloadAllTimelines() }
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
            recent: recent.prefix(4).map { RecentItem(track: $0, image: thumbnail(for: $0.id)) },
            style: style,
            sourceIcon: SharedStore.icon(for: nowPlaying.sourceAppID)
        )
    }

    private func thumbnail(for id: String) -> NSImage? {
        if let cached = thumbnails[id] { return cached }
        let image = SharedStore.artwork(for: id)
        thumbnails[id] = image
        return image
    }

    private func pruneArtwork(keeping id: String) {
        let keep = Set([id, nowPlaying.trackID] + recent.map(\.id)).map { "\($0).jpg" }
        let dir = SharedStore.artworkDirectory
        for file in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where !keep.contains(file) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
        }
        thumbnails = thumbnails.filter { keep.contains("\($0.key).jpg") }
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
                Task { @MainActor in PlayerHub.shared.perform(PlayerAction(command)) }
            }, command.notificationName as CFString, nil, .deliverImmediately)
        }
    }
}
