import AppKit
import MediaPlayer
import WidgetKit

/// Publishes Sonos playback to macOS Now Playing (Control Center and, where macOS shows it, the
/// lock screen) and handles the play/pause/skip buttons there. Apple Music, Spotify and browsers
/// already publish their own, so this stays quiet for them to avoid duplicates.
@MainActor
enum NowPlayingPublisher {
    private static var commandsInstalled = false
    private static var publishedTrackID = ""
    private static var artworkForTrack = ""

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "publishNowPlaying") as? Bool ?? true
    }

    static func update(_ np: NowPlaying, artwork: NSImage?) {
        let center = MPNowPlayingInfoCenter.default()
        guard isEnabled, !np.isEmpty, np.source == .sonos else {
            if !publishedTrackID.isEmpty {
                center.nowPlayingInfo = nil
                center.playbackState = .stopped
                setCommandsEnabled(false)
                publishedTrackID = ""
                artworkForTrack = ""
            }
            return
        }
        installCommands()
        setCommandsEnabled(true)

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: np.title,
            MPMediaItemPropertyArtist: np.artist,
            MPMediaItemPropertyAlbumTitle: np.album,
            MPMediaItemPropertyPlaybackDuration: np.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: np.position(at: Date()),
            MPNowPlayingInfoPropertyPlaybackRate: np.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        // Keep the artwork object while the song is the same so it isn't re-sent every update.
        if let existing = center.nowPlayingInfo?[MPMediaItemPropertyArtwork], artworkForTrack == np.trackID {
            info[MPMediaItemPropertyArtwork] = existing
        } else if let artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
            artworkForTrack = np.trackID
        }
        center.nowPlayingInfo = info
        center.playbackState = np.isPlaying ? .playing : .paused
        publishedTrackID = np.trackID
    }

    private static func installCommands() {
        guard !commandsInstalled else { return }
        commandsInstalled = true
        let commands = MPRemoteCommandCenter.shared()
        func on(_ command: MPRemoteCommand, _ action: @escaping @MainActor () -> Void) {
            command.addTarget { _ in
                MainActor.assumeIsolated { action() }
                return .success
            }
        }
        let hub = { PlayerHub.shared }
        on(commands.togglePlayPauseCommand) { hub().perform(.playPause) }
        on(commands.playCommand) { if !hub().nowPlaying.isPlaying { hub().perform(.playPause) } }
        on(commands.pauseCommand) { if hub().nowPlaying.isPlaying { hub().perform(.playPause) } }
        on(commands.nextTrackCommand) { hub().perform(.next) }
        on(commands.previousTrackCommand) { hub().perform(.previous) }
        commands.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let seconds = event.positionTime
            MainActor.assumeIsolated { PlayerHub.shared.perform(.seek(seconds)) }
            return .success
        }
    }

    private static func setCommandsEnabled(_ enabled: Bool) {
        let commands = MPRemoteCommandCenter.shared()
        for command in [commands.togglePlayPauseCommand, commands.playCommand, commands.pauseCommand,
                        commands.nextTrackCommand, commands.previousTrackCommand, commands.changePlaybackPositionCommand] {
            command.isEnabled = enabled
        }
    }
}

/// Makes desktop widgets pick up changes without removing and re-adding them.
@MainActor
enum WidgetRefresher {
    static func forceRefresh() {
        WidgetCenter.shared.reloadAllTimelines()
        if let plugins = Bundle.main.builtInPlugInsURL {
            // Make sure macOS uses the extension inside this copy of the app.
            run("/usr/bin/pluginkit", ["-a", plugins.appendingPathComponent("GlassTunesWidgets.appex").path])
        }
        // The widget service restarts on its own and redraws every widget from scratch.
        run("/usr/bin/killall", ["chronod"])
        Task {
            try? await Task.sleep(for: .seconds(2))
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// After an update, refresh once so widgets don't keep showing the old version.
    static func refreshIfAppChanged() {
        let build = "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "")-\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "")"
        guard UserDefaults.standard.string(forKey: "lastRefreshedBuild") != build else { return }
        UserDefaults.standard.set(build, forKey: "lastRefreshedBuild")
        forceRefresh()
    }

    private static func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
