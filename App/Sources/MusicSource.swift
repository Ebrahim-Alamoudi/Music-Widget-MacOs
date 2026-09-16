import AppKit

enum PlayerAction: Equatable {
    case playPause, next, previous, toggleShuffle, cycleRepeat
    case seek(Double)
    case setVolume(Int)

    init?(_ command: PlayerCommand) {
        switch command {
        case .playPause: self = .playPause
        case .next: self = .next
        case .previous: self = .previous
        case .shuffle: self = .toggleShuffle
        case .repeatMode: self = .cycleRepeat
        case .nextSource: return nil
        }
    }
}

enum ArtworkSource {
    case data(Data)
    case url(URL)
    case loader(@MainActor () -> Data?)
}

struct SourceReading {
    /// `trackID` holds the source's raw track key; the hub turns it into a file-safe ID.
    var nowPlaying: NowPlaying
    var artwork: ArtworkSource?
}

/// One place that music can come from.
@MainActor
protocol MusicSource: AnyObject {
    var kind: SourceKind { get }
    /// Cheap check used to skip sources that can't be playing.
    var isAvailable: Bool { get }
    /// A permission or setup problem the user needs to fix, if any.
    var issue: String? { get }
    func read() async -> SourceReading?
    func perform(_ action: PlayerAction, current: NowPlaying) async
    /// The songs after the current one, or why they can't be shown.
    func upNext() async -> QueueResult
    func playQueueItem(_ item: QueueItem) async
}

enum Apps {
    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }
}

// MARK: - AppleScript

struct ScriptError: Error {
    var code: Int
    var message: String

    var isPermissionDenied: Bool { code == -1743 }

    func userMessage(app: String) -> String? {
        if isPermissionDenied {
            return "Allow GlassTunes to control \(app) in System Settings → Privacy & Security → Automation."
        }
        return nil
    }
}

@MainActor
enum Script {
    private static var cache: [String: NSAppleScript] = [:]

    static func run(_ source: String) -> Result<NSAppleEventDescriptor, ScriptError> {
        let script: NSAppleScript
        if let cached = cache[source] {
            script = cached
        } else {
            guard let compiled = NSAppleScript(source: source) else {
                return .failure(ScriptError(code: 0, message: "Could not create script"))
            }
            cache[source] = compiled
            script = compiled
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            return .failure(ScriptError(code: error[NSAppleScript.errorNumber] as? Int ?? 0,
                                        message: error[NSAppleScript.errorMessage] as? String ?? ""))
        }
        return .success(result)
    }

    /// Escapes text for use inside an AppleScript string literal.
    static func quoted(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

extension NSAppleEventDescriptor {
    func string(at index: Int) -> String { atIndex(index)?.stringValue ?? "" }
    func double(at index: Int) -> Double { atIndex(index)?.doubleValue ?? 0 }
    func bool(at index: Int) -> Bool { atIndex(index)?.booleanValue ?? false }
}
