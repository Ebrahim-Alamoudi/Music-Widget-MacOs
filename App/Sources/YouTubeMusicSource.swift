import AppKit

/// Reads and controls music.youtube.com running in a browser tab by running JavaScript over AppleScript.
/// Firefox has no scripting support, so only Safari and Chromium browsers work.
@MainActor
final class YouTubeMusicSource: MusicSource {
    struct Browser {
        var bundleID: String
        var name: String
        var isSafari: Bool
    }

    static let browsers = [
        Browser(bundleID: "com.google.Chrome", name: "Chrome", isSafari: false),
        Browser(bundleID: "com.apple.Safari", name: "Safari", isSafari: true),
        Browser(bundleID: "com.brave.Browser", name: "Brave", isSafari: false),
        Browser(bundleID: "com.microsoft.edgemac", name: "Edge", isSafari: false),
    ]

    let kind = SourceKind.youtubeMusic
    private(set) var issue: String?
    /// The browser that last had a YouTube Music tab.
    private var activeBrowser: Browser?

    var isAvailable: Bool { Self.browsers.contains { Apps.isRunning($0.bundleID) } }

    private static let readJS = """
    (function(){
      var v = document.querySelector('video');
      var m = navigator.mediaSession && navigator.mediaSession.metadata;
      if (!v || !m || !m.title) return '';
      var art = (m.artwork && m.artwork.length) ? m.artwork[m.artwork.length - 1].src : '';
      var bar = document.querySelector('ytmusic-player-bar');
      var rep = bar && bar.querySelector('.repeat');
      var id = new URLSearchParams(location.search).get('v') || m.title;
      return JSON.stringify({
        title: m.title, artist: m.artist || '', album: m.album || '',
        duration: isFinite(v.duration) ? v.duration : 0, position: v.currentTime || 0,
        paused: v.paused, artwork: art, id: id,
        repeatLabel: rep ? (rep.getAttribute('title') || rep.getAttribute('aria-label') || '') : '',
        volume: Math.round(v.volume * 100)
      });
    })()
    """

    private struct Payload: Decodable {
        var title: String
        var artist: String
        var album: String
        var duration: Double
        var position: Double
        var paused: Bool
        var artwork: String
        var id: String
        var repeatLabel: String
        var volume: Int
    }

    func read() async -> SourceReading? {
        var fallback: SourceReading?
        var problem: String?
        for browser in Self.browsers where Apps.isRunning(browser.bundleID) {
            switch runInTab(Self.readJS, browser: browser) {
            case .success(let json):
                guard let reading = parse(json, browser: browser) else { continue }
                if reading.nowPlaying.isPlaying {
                    activeBrowser = browser
                    issue = nil
                    return reading
                }
                if fallback == nil {
                    fallback = reading
                    activeBrowser = browser
                }
            case .failure(let error):
                problem = problem ?? message(for: error, browser: browser)
            }
        }
        issue = fallback == nil ? problem : nil
        return fallback
    }

    func perform(_ action: PlayerAction, current: NowPlaying) async {
        let body = switch action {
        case .playPause: "return click('#play-pause-button');"
        case .next: "return click('.next-button');"
        case .previous: "return click('.previous-button');"
        case .toggleShuffle: "return click('.shuffle');"
        case .cycleRepeat: "return click('.repeat');"
        case .seek(let seconds): "var v = document.querySelector('video'); if (v) { v.currentTime = \(seconds); } return 'ok';"
        case .setVolume(let volume): "var v = document.querySelector('video'); if (v) { v.volume = \(Double(volume) / 100); } return 'ok';"
        }
        let js = """
        (function(){
          var bar = document.querySelector('ytmusic-player-bar');
          var click = function(sel){ var e = bar && bar.querySelector(sel); if (e) { e.click(); return 'ok'; } return 'missing'; };
          \(body)
        })()
        """
        if let browser = activeBrowser ?? Self.browsers.first(where: { Apps.isRunning($0.bundleID) }),
           case .success(let result) = runInTab(js, browser: browser), result != "none" {
            return
        }
        if action == .playPause {
            NSWorkspace.shared.open(URL(string: "https://music.youtube.com")!)
        }
    }

    // MARK: Queue

    private static let queueJS = """
    (function(){
      var items = document.querySelectorAll('ytmusic-player-queue-item');
      if (!items.length) return 'empty';
      var current = -1;
      items.forEach(function(e, i){ if (e.hasAttribute('selected')) current = i; });
      var out = [];
      for (var i = current + 1; i < items.length && out.length < 30; i++) {
        var e = items[i];
        var t = e.querySelector('.song-title');
        var b = e.querySelector('.byline');
        var img = e.querySelector('img');
        out.push({title: t ? t.textContent.trim() : '', artist: b ? b.textContent.trim() : '', artwork: img ? img.src : '', index: i});
      }
      return JSON.stringify(out);
    })()
    """

    private struct QueuePayload: Decodable {
        var title: String
        var artist: String
        var artwork: String
        var index: Int
    }

    func upNext() async -> QueueResult {
        guard let browser = activeBrowser else { return .unavailable("Open music.youtube.com in Chrome or Safari.") }
        guard case .success(let json) = runInTab(Self.queueJS, browser: browser), json != "none" else {
            return .unavailable("Couldn't read the YouTube Music tab.")
        }
        if json == "empty" { return .unavailable("Open the player page in YouTube Music to see Up Next.") }
        guard let rows = try? JSONDecoder().decode([QueuePayload].self, from: Data(json.utf8)) else {
            return .unavailable("Couldn't read the YouTube Music queue.")
        }
        return .items(rows.map {
            QueueItem(id: "yt\($0.index)", title: $0.title, artist: $0.artist,
                      artwork: $0.artwork.hasPrefix("http") ? URL(string: $0.artwork) : nil, position: $0.index)
        })
    }

    func playQueueItem(_ item: QueueItem) async {
        guard let browser = activeBrowser else { return }
        let js = """
        (function(){
          var e = document.querySelectorAll('ytmusic-player-queue-item')[\(item.position)];
          if (!e) return 'missing';
          (e.querySelector('ytmusic-play-button-renderer') || e).click();
          return 'ok';
        })()
        """
        _ = runInTab(js, browser: browser)
    }

    // MARK: Helpers

    private func parse(_ json: String, browser: Browser) -> SourceReading? {
        guard !json.isEmpty, json != "none",
              let payload = try? JSONDecoder().decode(Payload.self, from: Data(json.utf8)) else { return nil }
        var np = NowPlaying()
        np.state = payload.paused ? .paused : .playing
        np.title = payload.title
        np.artist = payload.artist
        np.album = payload.album
        np.duration = payload.duration
        np.position = payload.position
        np.trackID = payload.id
        let repeatLabel = payload.repeatLabel.lowercased()
        np.repeatMode = repeatLabel.contains("one") ? .one : repeatLabel.contains("all") ? .all : .off
        np.volume = payload.volume
        np.source = .youtubeMusic
        np.sourceName = "YouTube Music · \(browser.name)"
        np.sourceAppID = browser.bundleID
        return SourceReading(nowPlaying: np, artwork: URL(string: payload.artwork).map { .url($0) })
    }

    /// Runs JavaScript in the first music.youtube.com tab. Returns "none" when there is no such tab.
    private func runInTab(_ js: String, browser: Browser) -> Result<String, ScriptError> {
        let js = Script.quoted(js.replacingOccurrences(of: "\n", with: " "))
        let execute = browser.isSafari
            ? "do JavaScript \"\(js)\" in target"
            : "execute target javascript \"\(js)\""
        let source = """
        tell application id "\(browser.bundleID)"
            set target to missing value
            repeat with w in windows
                try
                    repeat with t in tabs of w
                        if (URL of t as string) starts with "https://music.youtube.com" then
                            set target to contents of t
                            exit repeat
                        end if
                    end repeat
                end try
                if target is not missing value then exit repeat
            end repeat
            if target is missing value then return "none"
            return \(execute)
        end tell
        """
        return Script.run(source).map { $0.stringValue ?? "" }
    }

    private func message(for error: ScriptError, browser: Browser) -> String? {
        if let permission = error.userMessage(app: browser.name) { return permission }
        let text = error.message.lowercased()
        guard text.contains("javascript") else { return nil }
        return browser.isSafari
            ? "In Safari, turn on Develop → Developer Settings → Allow JavaScript from Apple Events."
            : "In \(browser.name), turn on View → Developer → Allow JavaScript from Apple Events."
    }
}
