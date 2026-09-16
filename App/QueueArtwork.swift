import AppKit

/// Finds and caches small artwork thumbnails for Up Next.
/// - Apple Music: one background `osascript` run saves each song's artwork straight from Music
///   (kept on disk by persistent ID, so it's instant next time).
/// - Sonos / YouTube Music: the image URL the player provides.
/// - Anything still missing: Apple's catalog, looked up once per album.
@MainActor
enum QueueArtwork {
    private static let memory: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        return cache
    }()
    private static var misses = Set<String>()

    static let folder: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.ibrahim.glasstunes/QueueArtwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func cached(_ item: QueueItem) -> NSImage? {
        memory.object(forKey: key(for: item) as NSString)
    }

    /// Loads artwork for every item, reporting each image as soon as it's ready.
    static func load(_ items: [QueueItem], update: @escaping (String, NSImage) -> Void) async {
        var missing: [QueueItem] = []
        for item in items {
            if let image = cached(item) {
                update(item.id, image)
            } else if !misses.contains(key(for: item)) {
                missing.append(item)
            }
        }
        guard !missing.isEmpty else { return }

        // 1. Apple Music: files saved earlier, then one export run for the rest.
        let musicItems = missing.filter { $0.persistentID != nil }
        if !musicItems.isEmpty {
            var notOnDisk: [QueueItem] = []
            for item in musicItems {
                if let image = await thumbnail(fromFile: fileURL(for: item)) {
                    store(image, for: item, update: update)
                } else {
                    notOnDisk.append(item)
                }
            }
            if !notOnDisk.isEmpty {
                await exportFromMusic(notOnDisk)
                for item in notOnDisk {
                    if let image = await thumbnail(fromFile: fileURL(for: item)) {
                        store(image, for: item, update: update)
                    }
                }
            }
        }

        // 2. URLs from the player, 3. catalog search (one request per album).
        let remaining = missing.filter { cached($0) == nil }
        var groups: [String: [QueueItem]] = [:]
        for item in remaining { groups[key(for: item), default: []].append(item) }

        await withTaskGroup(of: (String, NSImage?).self) { group in
            var running = 0
            for (groupKey, members) in groups {
                guard let sample = members.first else { continue }
                if running >= 6 {
                    if let (doneKey, image) = await group.next() {
                        finish(doneKey, image, groups: groups, update: update)
                    }
                    running -= 1
                }
                running += 1
                let url = sample.artwork
                let artist = sample.artist, album = sample.album, title = sample.title
                group.addTask {
                    var image: NSImage?
                    if let url { image = await download(url) }
                    if image == nil, let found = await catalogArtworkURL(artist: artist, album: album, title: title) {
                        image = await download(found)
                    }
                    return (groupKey, image)
                }
            }
            for await (doneKey, image) in group {
                finish(doneKey, image, groups: groups, update: update)
            }
        }
    }

    // MARK: Helpers

    private static func finish(_ groupKey: String, _ image: NSImage?, groups: [String: [QueueItem]],
                               update: (String, NSImage) -> Void) {
        guard let image else {
            misses.insert(groupKey)
            return
        }
        for item in groups[groupKey] ?? [] { store(image, for: item, update: update) }
    }

    private static func store(_ image: NSImage, for item: QueueItem, update: (String, NSImage) -> Void) {
        memory.setObject(image, forKey: key(for: item) as NSString)
        update(item.id, image)
    }

    private static func key(for item: QueueItem) -> String {
        if let id = item.persistentID { return "pid:\(id)" }
        if let url = item.artwork { return url.absoluteString }
        return "search:\(item.artist)|\(item.album.isEmpty ? item.title : item.album)".lowercased()
    }

    private static func fileURL(for item: QueueItem) -> URL {
        folder.appendingPathComponent("\(item.persistentID ?? "none").img")
    }

    private nonisolated static func thumbnail(fromFile url: URL) async -> NSImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return makeThumbnail(data)
        }.value
    }

    private nonisolated static func download(_ url: URL) async -> NSImage? {
        guard url.scheme == "http" || url.scheme == "https",
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return makeThumbnail(data)
    }

    /// Decodes straight to a small bitmap so big covers never sit in memory.
    private nonisolated static func makeThumbnail(_ data: Data, side: CGFloat = 96) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: side,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: side / 2, height: side / 2))
    }

    private nonisolated static func catalogArtworkURL(artist: String, album: String, title: String) async -> URL? {
        guard let small = await ITunesSearch.album(artist: artist, album: album, title: title)?.artworkUrl100 else { return nil }
        return URL(string: small.replacingOccurrences(of: "100x100", with: "200x200"))
    }

    // MARK: Apple Music export

    private static let exportScript = """
    on run argv
        set outDir to item 1 of argv
        set trackIndexes to rest of argv
        set blobs to {}
        tell application id "com.apple.Music"
            set thePlaylist to current playlist
            repeat with trackIndex in trackIndexes
                try
                    set theTrack to track (trackIndex as integer) of thePlaylist
                    set end of blobs to {persistent ID of theTrack, raw data of artwork 1 of theTrack}
                end try
            end repeat
        end tell
        repeat with blob in blobs
            set outPath to outDir & (item 1 of blob) & ".img"
            try
                set fileRef to open for access (POSIX file outPath) with write permission
                set eof fileRef to 0
                write (item 2 of blob) to fileRef
                close access fileRef
            on error
                try
                    close access (POSIX file outPath)
                end try
            end try
        end repeat
    end run
    """

    /// Runs in a separate `osascript` process so the app never waits on Music.
    private static func exportFromMusic(_ items: [QueueItem]) async {
        let scriptURL = folder.deletingLastPathComponent().appendingPathComponent("export-artwork.applescript")
        if (try? String(contentsOf: scriptURL, encoding: .utf8)) != exportScript {
            try? exportScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        }
        let arguments = [scriptURL.path, folder.path + "/"] + items.map { String($0.position) }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
                // Don't wait forever if Music is busy or a permission prompt is open.
                DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
                    if process.isRunning { process.terminate() }
                }
            } catch {
                continuation.resume()
            }
        }
    }
}
