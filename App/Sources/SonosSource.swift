import Foundation
import Observation

struct SonosRoom: Codable, Hashable, Identifiable {
    /// Coordinator UUID of the group.
    var id: String
    var name: String
    var host: String
    var memberIDs: [String]
}

/// Talks to Sonos speakers over their local UPnP/SOAP API (port 1400).
@MainActor
@Observable
final class SonosSource: MusicSource {
    static let bundleID = "com.sonos.macController2"

    let kind = SourceKind.sonos
    private(set) var issue: String?
    private(set) var rooms: [SonosRoom] = []
    private(set) var isDiscovering = false
    var selectedRoom: SonosRoom? {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(selectedRoom), forKey: "sonosRoom") }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "sonosRoom") {
            selectedRoom = try? JSONDecoder().decode(SonosRoom.self, from: data)
        }
    }

    var isAvailable: Bool { selectedRoom != nil }

    // MARK: Discovery

    /// Finds speakers with SSDP (plus an optional manual IP) and lists their groups.
    func discover(manualHost: String? = nil) async {
        isDiscovering = true
        defer { isDiscovering = false }
        var hosts = await SSDP.discoverSonosHosts()
        if let manualHost, !manualHost.isEmpty { hosts.insert(manualHost, at: 0) }
        for host in hosts {
            if let found = try? await Self.topology(from: host), !found.isEmpty {
                rooms = found.sorted { $0.name < $1.name }
                issue = nil
                if let selected = selectedRoom {
                    selectedRoom = rooms.first { $0.memberIDs.contains(selected.id) } ?? selected
                }
                return
            }
        }
        issue = "No Sonos speakers found. Check that this Mac is on the same network and allowed Local Network access."
    }

    private static func topology(from host: String) async throws -> [SonosRoom] {
        let response = try await SOAP.call(host: host, path: "/ZoneGroupTopology/Control", service: "ZoneGroupTopology",
                                           action: "GetZoneGroupState", arguments: "")
        guard let state = SOAP.value("ZoneGroupState", in: response) else { return [] }
        return ZoneGroupParser.rooms(from: state)
    }

    // MARK: Reading

    func read() async -> SourceReading? {
        guard let room = selectedRoom else { return nil }
        let host = room.host
        let instance = "<InstanceID>0</InstanceID>"
        do {
            async let transport = SOAP.call(host: host, path: SOAP.avTransport, service: "AVTransport", action: "GetTransportInfo", arguments: instance)
            async let position = SOAP.call(host: host, path: SOAP.avTransport, service: "AVTransport", action: "GetPositionInfo", arguments: instance)
            async let settings = SOAP.call(host: host, path: SOAP.avTransport, service: "AVTransport", action: "GetTransportSettings", arguments: instance)
            async let crossfade = SOAP.call(host: host, path: SOAP.avTransport, service: "AVTransport", action: "GetCrossfadeMode", arguments: instance)
            async let volume = SOAP.call(host: host, path: "/MediaRenderer/GroupRenderingControl/Control", service: "GroupRenderingControl", action: "GetGroupVolume", arguments: instance)
            async let media = SOAP.call(host: host, path: SOAP.avTransport, service: "AVTransport", action: "GetMediaInfo", arguments: instance)

            let (t, p, s) = try await (transport, position, settings)
            let fade = (try? await crossfade).flatMap { SOAP.value("CrossfadeMode", in: $0) }
            let groupVolume = (try? await volume).flatMap { SOAP.value("CurrentVolume", in: $0) }
            let currentURI = (try? await media).flatMap { SOAP.value("CurrentURI", in: $0) } ?? ""
            issue = nil

            let trackURI = SOAP.value("TrackURI", in: p) ?? ""
            if trackURI.hasPrefix("x-rincon:") {
                // This speaker joined another group; follow the new coordinator next time.
                Task { await discover(manualHost: host) }
            }

            let transportState = SOAP.value("CurrentTransportState", in: t) ?? ""
            guard transportState != "NO_MEDIA_PRESENT" else { return nil }

            var np = NowPlaying()
            np.state = ["PLAYING", "TRANSITIONING"].contains(transportState) ? .playing : .paused
            let didl = SOAP.value("TrackMetaData", in: p) ?? ""
            np.title = SOAP.value("title", in: didl) ?? ""
            np.artist = SOAP.value("creator", in: didl) ?? ""
            np.album = SOAP.value("album", in: didl) ?? ""
            // Radio streams put "Artist - Title" in streamContent.
            if let stream = SOAP.value("streamContent", in: didl), stream.contains(" - ") {
                let parts = stream.components(separatedBy: " - ")
                np.artist = parts[0]
                np.title = parts.dropFirst().joined(separator: " - ")
            }
            if trackURI.contains("htastream") { np.title = "TV" }
            guard !np.title.isEmpty else { return nil }

            np.duration = Self.seconds(SOAP.value("TrackDuration", in: p))
            np.position = Self.seconds(SOAP.value("RelTime", in: p))
            np.trackID = "\(trackURI)|\(np.title)"
            // Shuffle/repeat only apply to the speaker's own queue. With Spotify Connect, AirPlay, radio or TV
            // the speaker accepts the command but ignores it, so leave the buttons disabled.
            if currentURI.hasPrefix("x-rincon-queue:") {
                let mode = SOAP.value("PlayMode", in: s) ?? "NORMAL"
                np.shuffle = mode.hasPrefix("SHUFFLE")
                np.repeatMode = mode.hasSuffix("REPEAT_ONE") ? .one : (mode == "REPEAT_ALL" || mode == "SHUFFLE") ? .all : .off
            }
            np.transition = fade == "1" ? "Crossfade" : nil
            np.volume = groupVolume.flatMap { Int($0) }
            np.source = .sonos
            np.sourceName = "Sonos · \(room.name)"
            np.sourceAppID = Self.bundleID

            var artwork: ArtworkSource?
            if var art = SOAP.value("albumArtURI", in: didl), !art.isEmpty {
                if art.hasPrefix("/") { art = "http://\(host):1400\(art)" }
                artwork = URL(string: art).map { .url($0) }
            }
            return SourceReading(nowPlaying: np, artwork: artwork)
        } catch {
            issue = "Can't reach \(room.name). Make sure the speaker is on."
            return nil
        }
    }

    // MARK: Queue

    func upNext() async -> QueueResult {
        guard let host = selectedRoom?.host else { return .unavailable("Choose a Sonos room first.") }
        let instance = "<InstanceID>0</InstanceID>"
        async let mediaCall = SOAP.call(host: host, path: SOAP.avTransport, service: "AVTransport",
                                        action: "GetMediaInfo", arguments: instance)
        async let positionCall = SOAP.call(host: host, path: SOAP.avTransport, service: "AVTransport",
                                           action: "GetPositionInfo", arguments: instance)
        guard let media = try? await mediaCall, let position = try? await positionCall else {
            return .unavailable("Can't reach the speaker.")
        }
        guard (SOAP.value("CurrentURI", in: media) ?? "").hasPrefix("x-rincon-queue:") else {
            return .unavailable("This music isn't playing from the Sonos queue (for example Spotify Connect, AirPlay or radio), so the speaker can't list what's next.")
        }
        let current = Int(SOAP.value("Track", in: position) ?? "") ?? 0
        let arguments = "<ObjectID>Q:0</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag>"
            + "<Filter>dc:title,dc:creator,upnp:albumArtURI</Filter>"
            + "<StartingIndex>\(current)</StartingIndex><RequestedCount>30</RequestedCount><SortCriteria></SortCriteria>"
        guard let response = try? await SOAP.call(host: host, path: "/MediaServer/ContentDirectory/Control",
                                                  service: "ContentDirectory", action: "Browse", arguments: arguments),
              let didl = SOAP.value("Result", in: response) else {
            return .unavailable("The speaker didn't return its queue.")
        }
        var items: [QueueItem] = []
        for (offset, entry) in SOAP.elements("item", in: didl).enumerated() {
            var art = SOAP.value("albumArtURI", in: entry) ?? ""
            if art.hasPrefix("/") { art = "http://\(host):1400\(art)" }
            let number = current + offset + 1 // 1-based track number in the queue
            items.append(QueueItem(id: "sonos\(number)", title: SOAP.value("title", in: entry) ?? "Unknown",
                                   artist: SOAP.value("creator", in: entry) ?? "",
                                   artwork: URL(string: art), position: number))
        }
        return .items(items)
    }

    func playQueueItem(_ item: QueueItem) async {
        guard let host = selectedRoom?.host else { return }
        _ = try? await SOAP.call(host: host, path: SOAP.avTransport, service: "AVTransport", action: "Seek",
                                 arguments: "<InstanceID>0</InstanceID><Unit>TRACK_NR</Unit><Target>\(item.position)</Target>")
        _ = try? await SOAP.call(host: host, path: SOAP.avTransport, service: "AVTransport", action: "Play",
                                 arguments: "<InstanceID>0</InstanceID><Speed>1</Speed>")
    }

    // MARK: Control

    func perform(_ action: PlayerAction, current: NowPlaying) async {
        guard let host = selectedRoom?.host else { return }
        let instance = "<InstanceID>0</InstanceID>"
        func transport(_ name: String, _ extra: String = "") async {
            _ = try? await SOAP.call(host: host, path: SOAP.avTransport, service: "AVTransport", action: name, arguments: instance + extra)
        }
        let shuffle = current.shuffle ?? false
        let repeatMode = current.repeatMode ?? .off
        switch action {
        case .playPause:
            if current.isPlaying { await transport("Pause") } else { await transport("Play", "<Speed>1</Speed>") }
        case .next: await transport("Next")
        case .previous: await transport("Previous")
        case .toggleShuffle:
            await transport("SetPlayMode", "<NewPlayMode>\(Self.playMode(shuffle: !shuffle, repeat: repeatMode))</NewPlayMode>")
        case .cycleRepeat:
            let next: RepeatMode = switch repeatMode { case .off: .all; case .all: .one; case .one: .off }
            await transport("SetPlayMode", "<NewPlayMode>\(Self.playMode(shuffle: shuffle, repeat: next))</NewPlayMode>")
        case .seek(let seconds):
            await transport("Seek", "<Unit>REL_TIME</Unit><Target>\(Self.timestamp(seconds))</Target>")
        case .setVolume(let volume):
            _ = try? await SOAP.call(host: host, path: "/MediaRenderer/GroupRenderingControl/Control", service: "GroupRenderingControl",
                                     action: "SetGroupVolume", arguments: instance + "<DesiredVolume>\(volume)</DesiredVolume>")
        }
    }

    private static func playMode(shuffle: Bool, repeat mode: RepeatMode) -> String {
        switch (shuffle, mode) {
        case (false, .off): "NORMAL"
        case (false, .all): "REPEAT_ALL"
        case (false, .one): "REPEAT_ONE"
        case (true, .off): "SHUFFLE_NOREPEAT"
        case (true, .all): "SHUFFLE"
        case (true, .one): "SHUFFLE_REPEAT_ONE"
        }
    }

    private static func seconds(_ text: String?) -> Double {
        guard let parts = text?.split(separator: ":").compactMap({ Double($0) }), parts.count == 3 else { return 0 }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    private static func timestamp(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }
}

// MARK: - SOAP

enum SOAP {
    static let avTransport = "/MediaRenderer/AVTransport/Control"

    struct Failure: Error {}

    static func call(host: String, path: String, service: String, action: String, arguments: String) async throws -> String {
        guard let url = URL(string: "http://\(host):1400\(path)") else { throw Failure() }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"urn:schemas-upnp-org:service:\(service):1#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data("""
        <?xml version="1.0" encoding="utf-8"?>\
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\
        <s:Body><u:\(action) xmlns:u="urn:schemas-upnp-org:service:\(service):1">\(arguments)</u:\(action)></s:Body></s:Envelope>
        """.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure() }
        return String(decoding: data, as: UTF8.self)
    }

    /// Text inside the first `<tag>` (namespace prefix optional), XML-unescaped.
    static func value(_ tag: String, in xml: String) -> String? {
        let pattern = "<(?:[A-Za-z0-9]+:)?\(tag)(?:\\s[^>]*)?>(.*?)</(?:[A-Za-z0-9]+:)?\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else { return nil }
        return unescape(String(xml[range]))
    }

    /// Every `<tag ...>...</tag>` element in the document, as raw XML.
    static func elements(_ tag: String, in xml: String) -> [String] {
        let pattern = "<\(tag)[\\s>].*?</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap {
            Range($0.range, in: xml).map { String(xml[$0]) }
        }
    }

    static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

private final class ZoneGroupParser: NSObject, XMLParserDelegate {
    private struct Member { var id: String; var name: String; var host: String; var invisible: Bool }

    private var rooms: [SonosRoom] = []
    private var coordinator = ""
    private var members: [Member] = []

    static func rooms(from xml: String) -> [SonosRoom] {
        let delegate = ZoneGroupParser()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = delegate
        parser.parse()
        return delegate.rooms
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch name {
        case "ZoneGroup":
            coordinator = attributes["Coordinator"] ?? ""
            members = []
        case "ZoneGroupMember":
            let host = attributes["Location"].flatMap { URL(string: $0)?.host } ?? ""
            members.append(Member(id: attributes["UUID"] ?? "", name: attributes["ZoneName"] ?? "Sonos",
                                  host: host, invisible: attributes["Invisible"] == "1"))
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard name == "ZoneGroup", let lead = members.first(where: { $0.id == coordinator }), !lead.host.isEmpty else { return }
        let visible = members.filter { !$0.invisible }
        let others = Set(visible.map(\.name)).subtracting([lead.name]).count
        rooms.append(SonosRoom(id: coordinator,
                               name: others > 0 ? "\(lead.name) + \(others)" : lead.name,
                               host: lead.host,
                               memberIDs: members.map(\.id)))
    }
}

// MARK: - SSDP discovery

enum SSDP {
    static func discoverSonosHosts(timeout: TimeInterval = 2) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: search(timeout: timeout))
            }
        }
    }

    private static func search(timeout: TimeInterval) -> [String] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var wait = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(1900).bigEndian
        address.sin_addr.s_addr = inet_addr("239.255.255.250")

        let message = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n\r\n"
        let bytes = Array(message.utf8)
        for _ in 0..<2 {
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    _ = sendto(fd, bytes, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        let regex = try! NSRegularExpression(pattern: "LOCATION:\\s*http://([0-9.]+):1400", options: .caseInsensitive)
        var hosts: [String] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let count = recv(fd, &buffer, buffer.count, 0)
            guard count > 0 else { continue }
            let text = String(decoding: buffer[0..<count], as: UTF8.self)
            if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text), !hosts.contains(String(text[range])) {
                hosts.append(String(text[range]))
            }
        }
        return hosts
    }
}
