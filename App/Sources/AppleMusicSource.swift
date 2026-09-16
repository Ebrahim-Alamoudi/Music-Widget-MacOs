import AppKit

@MainActor
final class AppleMusicSource: MusicSource {
    static let bundleID = "com.apple.Music"

    let kind = SourceKind.appleMusic
    private(set) var issue: String?
    private var transitionCache: (value: String?, readAt: Date) = (nil, .distantPast)

    var isAvailable: Bool { Apps.isRunning(Self.bundleID) }

    private static let readScript = """
    tell application id "com.apple.Music"
        set playerStateValue to player state
        if playerStateValue is playing or playerStateValue is fast forwarding or playerStateValue is rewinding then
            set playerStatus to "playing"
        else if playerStateValue is paused then
            set playerStatus to "paused"
        else
            return {"stopped"}
        end if
        try
            set t to current track
        on error
            return {"stopped"}
        end try
        set trackName to ""
        set trackArtist to ""
        set trackAlbum to ""
        set trackLength to 0
        set trackKey to ""
        set playerPos to 0
        try
            set trackName to name of t
        end try
        try
            set trackArtist to artist of t
        end try
        try
            set trackAlbum to album of t
        end try
        try
            set trackLength to duration of t
        end try
        try
            set trackKey to persistent ID of t
        end try
        try
            set playerPos to player position
        end try
        set repeatText to song repeat as string
        return {playerStatus, trackName, trackArtist, trackAlbum, trackLength, playerPos, trackKey, shuffle enabled, repeatText, sound volume}
    end tell
    """

    private static let artworkScript = """
    tell application id "com.apple.Music"
        try
            return raw data of artwork 1 of current track
        end try
    end tell
    """

    func read() async -> SourceReading? {
        // Never launch Music just to read its state.
        guard isAvailable else { return nil }
        let d: NSAppleEventDescriptor
        switch Script.run(Self.readScript) {
        case .success(let result):
            issue = nil
            d = result
        case .failure(let error):
            issue = error.userMessage(app: "Music")
            return nil
        }
        guard d.numberOfItems >= 10, d.string(at: 1) != "stopped" else { return nil }

        var np = NowPlaying()
        np.state = d.string(at: 1) == "paused" ? .paused : .playing
        np.title = d.string(at: 2)
        np.artist = d.string(at: 3)
        np.album = d.string(at: 4)
        np.duration = d.double(at: 5)
        np.position = d.double(at: 6)
        np.trackID = d.string(at: 7).isEmpty ? "\(np.title)|\(np.artist)" : d.string(at: 7)
        np.shuffle = d.bool(at: 8)
        np.repeatMode = RepeatMode(rawValue: d.string(at: 9)) ?? .off
        np.volume = Int(d.double(at: 10))
        np.source = .appleMusic
        np.sourceName = "Apple Music"
        np.sourceAppID = Self.bundleID
        np.transition = transitionSetting()

        return SourceReading(nowPlaying: np, artwork: .loader {
            guard case .success(let result) = Script.run(Self.artworkScript) else { return nil }
            let data = result.data
            return data.isEmpty ? nil : data
        })
    }

    func perform(_ action: PlayerAction, current: NowPlaying) async {
        let command = switch action {
        case .playPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        case .toggleShuffle: "set shuffle enabled to not shuffle enabled"
        case .cycleRepeat:
            """
            if song repeat is off then
                set song repeat to all
            else if song repeat is all then
                set song repeat to one
            else
                set song repeat to off
            end if
            """
        case .seek(let seconds): "set player position to \(seconds)"
        case .setVolume(let volume): "set sound volume to \(volume)"
        }
        // Play/pause may launch Music; everything else needs it open already.
        guard action == .playPause || isAvailable else { return }
        _ = Script.run("tell application id \"com.apple.Music\"\n\(command)\nend tell")
    }

    private static let queueScript = """
    tell application id "com.apple.Music"
        try
            set thePlaylist to current playlist
            set currentIndex to index of current track
            set trackCount to count of tracks of thePlaylist
        on error
            return {}
        end try
        set lastIndex to currentIndex + 30
        if lastIndex > trackCount then set lastIndex to trackCount
        set results to {}
        repeat with trackNumber from (currentIndex + 1) to lastIndex
            set aTrack to track trackNumber of thePlaylist
            set end of results to {name of aTrack, artist of aTrack, album of aTrack, trackNumber}
        end repeat
        return results
    end tell
    """

    func upNext() async -> QueueResult {
        guard isAvailable else { return .unavailable("Music isn't open.") }
        guard case .success(let list) = Script.run(Self.queueScript) else {
            return .unavailable("Music didn't share its queue.")
        }
        guard list.numberOfItems > 0 else { return .items([]) }
        let items: [QueueItem] = (1...list.numberOfItems).compactMap { index in
            guard let row = list.atIndex(index), row.numberOfItems >= 4 else { return nil }
            let position = Int(row.double(at: 4))
            return QueueItem(id: "am\(position)", title: row.string(at: 1), artist: row.string(at: 2),
                             artwork: nil, position: position)
        }
        return .items(items)
    }

    func playQueueItem(_ item: QueueItem) async {
        _ = Script.run("tell application id \"com.apple.Music\" to play track \(item.position) of current playlist")
    }

    /// Music stores its Transitions setting (Settings → Playback) in its preferences.
    /// Style 1 is AutoMix and 0 is Crossfade; Apple doesn't document these keys.
    private func transitionSetting() -> String? {
        if Date().timeIntervalSince(transitionCache.readAt) < 30 { return transitionCache.value }
        let defaults = UserDefaults(suiteName: Self.bundleID)
        var value: String?
        if defaults?.bool(forKey: "TransitionsEnabled") == true {
            value = defaults?.integer(forKey: "TransitionStyle") == 0 ? "Crossfade" : "AutoMix"
        }
        transitionCache = (value, Date())
        return value
    }
}
