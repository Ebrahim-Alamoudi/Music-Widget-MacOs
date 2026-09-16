import AppKit

enum Artwork {
    static func jpeg(_ image: NSImage, maxSide: CGFloat) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, maxSide / CGFloat(max(cg.width, cg.height)))
        let width = max(1, Int(CGFloat(cg.width) * scale))
        let height = max(1, Int(CGFloat(cg.height) * scale))
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .jpeg, properties: [.compressionFactor: 0.88])
    }

    /// Small decoded copy for lists, so thumbnails don't keep full-size bitmaps in memory.
    static func thumbnail(_ image: NSImage, side: CGFloat) -> NSImage {
        guard let data = jpeg(image, maxSide: side * 2), let small = NSImage(data: data) else { return image }
        small.size = NSSize(width: side, height: side)
        return small
    }

    /// Average color, nudged to be saturated and mid-bright so it works as a glass tint.
    static func averageColor(of image: NSImage) -> RGBColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        let base = NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
        let tuned = NSColor(hue: base.hueComponent,
                            saturation: min(1, base.saturationComponent * 1.35),
                            brightness: min(0.8, max(0.4, base.brightnessComponent)),
                            alpha: 1)
        return RGBColor(r: tuned.redComponent, g: tuned.greenComponent, b: tuned.blueComponent)
    }

    /// Writes an app's icon into the App Group so the sandboxed widget can show it.
    static func saveIcon(for bundleID: String) {
        let url = SharedStore.iconURL(for: bundleID)
        guard !FileManager.default.fileExists(atPath: url.path),
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        let size = NSSize(width: 64, height: 64)
        guard let rep = icon.bestRepresentation(for: NSRect(origin: .zero, size: size), context: nil, hints: nil),
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        rep.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url, options: .atomic)
    }
}

// MARK: - Apple catalog lookups

/// Uses Apple's public iTunes Search API to match any track (from any source) to its Apple Music album.
enum ITunesSearch {
    struct Item: Decodable {
        let artistName: String?
        let collectionName: String?
        let collectionViewUrl: String?
        let artworkUrl100: String?
    }

    private struct Response: Decodable { let results: [Item] }

    static func album(artist: String, album: String, title: String) async -> Item? {
        guard !artist.isEmpty else { return nil }
        let useAlbum = !album.isEmpty
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            .init(name: "term", value: "\(artist) \(useAlbum ? album : title)"),
            .init(name: "entity", value: useAlbum ? "album" : "song"),
            .init(name: "country", value: Locale.current.region?.identifier ?? "US"),
            .init(name: "limit", value: "8"),
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let results = try? JSONDecoder().decode(Response.self, from: data).results, !results.isEmpty else { return nil }

        let wantArtist = normalize(artist)
        let wantAlbum = normalize(album)
        func artistMatches(_ item: Item) -> Bool {
            let name = normalize(item.artistName ?? "")
            return name.contains(wantArtist) || wantArtist.contains(name)
        }
        if useAlbum, let exact = results.first(where: { artistMatches($0) && normalize($0.collectionName ?? "") == wantAlbum }) {
            return exact
        }
        return results.first(where: artistMatches) ?? results.first
    }

    static func artwork(artist: String, album: String, title: String) async -> Data? {
        guard let small = await self.album(artist: artist, album: album, title: title)?.artworkUrl100,
              let large = URL(string: small.replacingOccurrences(of: "100x100", with: "600x600")) else { return nil }
        return try? await URLSession.shared.data(from: large).0
    }

    /// Lowercased, without " - Single"/" - EP" and bracketed edition notes.
    private static func normalize(_ text: String) -> String {
        var s = text.lowercased()
        for suffix in [" - single", " - ep"] where s.hasSuffix(suffix) { s.removeLast(suffix.count) }
        s = s.replacingOccurrences(of: "\\s*[\\(\\[].*?[\\)\\]]", with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }
}

struct MotionURLs: Equatable {
    /// Square animated cover.
    var square: URL?
    /// Full-height animated cover shown behind the player on iPhone.
    var tall: URL?
}

/// Finds Apple Music's animated album art. The public album page embeds the HLS stream URLs.
enum MotionArtwork {
    @MainActor private static var cache: [String: MotionURLs?] = [:]

    @MainActor
    static func lookup(artist: String, album: String, title: String) async -> MotionURLs? {
        let key = "\(artist)|\(album.isEmpty ? title : album)".lowercased()
        if let cached = cache[key] { return cached }
        let result = await fetch(artist: artist, album: album, title: title)
        cache[key] = result
        return result
    }

    private static func fetch(artist: String, album: String, title: String) async -> MotionURLs? {
        guard let page = await ITunesSearch.album(artist: artist, album: album, title: title)?.collectionViewUrl,
              var components = URLComponents(string: page) else { return nil }
        components.query = nil
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/19.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        let html = String(decoding: data, as: UTF8.self)
        let urls = MotionURLs(square: video(for: "motionDetailSquare", in: html), tall: video(for: "motionDetailTall", in: html))
        return urls.square == nil && urls.tall == nil ? nil : urls
    }

    private static func video(for key: String, in html: String) -> URL? {
        let pattern = "\"\(key)\":\\{.{0,2000}?\"video\":\"(https://[^\"]+?\\.m3u8)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return URL(string: String(html[range]))
    }
}
