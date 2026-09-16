import AppKit
import SwiftUI

enum GT {
    /// Injected from the `GT_APP_GROUP` build setting via Info.plist so the app and widget always agree.
    static let appGroupID = Bundle.main.object(forInfoDictionaryKey: "GTAppGroupID") as? String ?? "com.ibrahim.glasstunes"
    static let openPlayerURL = URL(string: "glasstunes://player")!
    static let fallbackTint = RGBColor(r: 0.98, g: 0.24, b: 0.35)
}

// MARK: - Model

struct RGBColor: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double

    var color: Color { Color(red: r, green: g, blue: b) }
}

enum SourceKind: String, Codable, CaseIterable, Identifiable {
    case automatic, appleMusic, spotify, youtubeMusic, sonos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .youtubeMusic: "YouTube Music"
        case .sonos: "Sonos"
        }
    }

    var symbol: String {
        switch self {
        case .automatic: "sparkles"
        case .appleMusic: "music.note"
        case .spotify: "dot.radiowaves.left.and.right"
        case .youtubeMusic: "play.rectangle.fill"
        case .sonos: "hifispeaker.2.fill"
        }
    }
}

enum RepeatMode: String, Codable {
    case off, all, one

    var symbol: String { self == .one ? "repeat.1" : "repeat" }
}

struct NowPlaying: Codable, Equatable {
    enum State: String, Codable { case playing, paused, stopped }

    var state: State = .stopped
    var trackID = ""
    var title = ""
    var artist = ""
    var album = ""
    var duration: Double = 0
    var position: Double = 0
    var capturedAt = Date()
    var tint: RGBColor?

    var source: SourceKind = .automatic
    /// e.g. "Spotify", "YouTube Music · Chrome", "Sonos · Kitchen"
    var sourceName = ""
    /// Bundle ID of the app whose icon represents the source.
    var sourceAppID: String?
    var shuffle: Bool?
    var repeatMode: RepeatMode?
    /// "AutoMix" / "Crossfade" when the player has song transitions turned on.
    var transition: String?
    var volume: Int?
    /// Players that currently have something loaded (Automatic mode), for the switch-source button.
    var availableSources: [SourceKind]?

    static let stopped = NowPlaying()

    var isPlaying: Bool { state == .playing }
    var isEmpty: Bool { state == .stopped || title.isEmpty }
    var startDate: Date { capturedAt.addingTimeInterval(-position) }
    var endDate: Date { startDate.addingTimeInterval(duration) }

    func position(at date: Date) -> Double {
        isPlaying ? min(duration, position + date.timeIntervalSince(capturedAt)) : position
    }
}

struct RecentTrack: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var artist: String
}

// MARK: - Commands (widget → app)

/// Widgets run sandboxed and can't talk to other apps, so they post a Darwin notification
/// that the GlassTunes helper app listens for.
enum PlayerCommand: String, CaseIterable {
    case playPause, next, previous, shuffle, repeatMode, nextSource, volumeDown, volumeUp

    var notificationName: String { "com.ibrahim.glasstunes.command.\(rawValue)" }

    init?(notificationName: String) {
        guard let match = Self.allCases.first(where: { $0.notificationName == notificationName }) else { return nil }
        self = match
    }

    func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificationName as CFString), nil, nil, true
        )
    }
}

// MARK: - Storage in the App Group container

enum SharedStore {
    static var containerURL: URL {
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GT.appGroupID)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("GlassTunes")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var artworkDirectory: URL {
        let url = containerURL.appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var nowPlaying: NowPlaying {
        get { load(NowPlaying.self, "nowplaying.json") ?? .stopped }
        set { save(newValue, "nowplaying.json") }
    }

    static var recent: [RecentTrack] {
        get { load([RecentTrack].self, "recent.json") ?? [] }
        set { save(newValue, "recent.json") }
    }

    static func artworkURL(for id: String) -> URL {
        artworkDirectory.appendingPathComponent("\(id).jpg")
    }

    static func artwork(for id: String) -> NSImage? {
        guard !id.isEmpty else { return nil }
        return NSImage(contentsOf: artworkURL(for: id))
    }

    static func iconURL(for bundleID: String) -> URL {
        containerURL.appendingPathComponent("icon-\(bundleID).png")
    }

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        return NSImage(contentsOf: iconURL(for: bundleID))
    }

    /// Instant feedback in the widget before the helper app reports the real state.
    static func optimisticToggle() {
        var np = nowPlaying
        guard !np.isEmpty else { return }
        let now = Date()
        np.position = np.position(at: now)
        np.capturedAt = now
        np.state = np.isPlaying ? .paused : .playing
        nowPlaying = np
    }

    private static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: containerURL.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: containerURL.appendingPathComponent(name), options: .atomic)
    }
}
