import AppKit

@MainActor
final class SpotifySource: MusicSource {
    static let bundleID = "com.spotify.client"

    let kind = SourceKind.spotify
    private(set) var issue: String?

    var isAvailable: Bool { Apps.isRunning(Self.bundleID) }

    private static let readScript = """
    tell application id "com.spotify.client"
        set playerStateValue to player state
        if playerStateValue is playing then
            set playerStatus to "playing"
        else if playerStateValue is paused then
            set playerStatus to "paused"
        else
            return {"stopped"}
        end if
        set t to current track
        set trackName to ""
        set trackArtist to ""
        set trackAlbum to ""
        set trackLength to 0
        set trackKey to ""
        set artURL to ""
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
            set trackKey to id of t
        end try
        try
            set artURL to artwork url of t
        end try
        return {playerStatus, trackName, trackArtist, trackAlbum, trackLength, player position, trackKey, artURL, shuffling, repeating, sound volume}
    end tell
    """

    func read() async -> SourceReading? {
        guard isAvailable else { return nil }
        let d: NSAppleEventDescriptor
        switch Script.run(Self.readScript) {
        case .success(let result):
            issue = nil
            d = result
        case .failure(let error):
            issue = error.userMessage(app: "Spotify")
            return nil
        }
        guard d.numberOfItems >= 11, d.string(at: 1) != "stopped" else { return nil }

        var np = NowPlaying()
        np.state = d.string(at: 1) == "paused" ? .paused : .playing
        np.title = d.string(at: 2)
        np.artist = d.string(at: 3)
        np.album = d.string(at: 4)
        np.duration = d.double(at: 5) / 1000 // Spotify reports milliseconds
        np.position = d.double(at: 6)
        np.trackID = d.string(at: 7).isEmpty ? "\(np.title)|\(np.artist)" : d.string(at: 7)
        np.shuffle = d.bool(at: 9)
        np.repeatMode = d.bool(at: 10) ? .all : .off
        np.volume = Int(d.double(at: 11))
        np.source = .spotify
        np.sourceName = "Spotify"
        np.sourceAppID = Self.bundleID

        let art = URL(string: d.string(at: 8))
        return SourceReading(nowPlaying: np, artwork: art.map { .url($0) })
    }

    func perform(_ action: PlayerAction, current: NowPlaying) async {
        let command = switch action {
        case .playPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        case .toggleShuffle: "set shuffling to not shuffling"
        case .cycleRepeat: "set repeating to not repeating"
        case .seek(let seconds): "set player position to \(seconds)"
        case .setVolume(let volume): "set sound volume to \(volume)"
        }
        guard action == .playPause || isAvailable else { return }
        _ = Script.run("tell application id \"com.spotify.client\"\n\(command)\nend tell")
    }
}
