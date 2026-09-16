import AppKit
import CoreImage

/// Optional: turns the current album cover into the desktop (and lock screen) wallpaper.
/// The user's own wallpaper is remembered and put back when this is turned off or the app quits.
@MainActor
final class AlbumWallpaper {
    static let shared = AlbumWallpaper()

    private let defaults = UserDefaults.standard
    private let savedKey = "wallpaperOriginals"
    private var lastTrackID = ""
    private var renderTask: Task<Void, Never>?

    var isEnabled: Bool { defaults.bool(forKey: "albumWallpaper") }

    private var folder: URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.ibrahim.glasstunes/Wallpaper", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Called when the setting changes.
    func setEnabled(_ enabled: Bool) {
        if enabled {
            saveOriginals()
            lastTrackID = ""
            let hub = PlayerHub.shared
            update(artwork: hub.artwork, trackID: hub.nowPlaying.trackID)
        } else {
            renderTask?.cancel()
            restoreOriginals()
        }
    }

    /// Called whenever the song or its artwork changes.
    func update(artwork: NSImage?, trackID: String) {
        guard isEnabled, let artwork, !trackID.isEmpty, trackID != lastTrackID,
              let cg = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        lastTrackID = trackID
        let screens = NSScreen.screens.map { (id: Self.displayID($0), size: Self.pixelSize($0), screen: $0) }
        let folder = folder
        renderTask?.cancel()
        renderTask = Task {
            var results: [(NSScreen, URL)] = []
            for target in screens {
                // A new file name per song: macOS caches wallpapers by URL.
                let url = folder.appendingPathComponent("\(trackID)-\(target.id).jpg")
                let ok = await Task.detached(priority: .utility) {
                    FileManager.default.fileExists(atPath: url.path) || Self.render(cg, size: target.size, to: url)
                }.value
                if ok { results.append((target.screen, url)) }
            }
            guard !Task.isCancelled, isEnabled else { return }
            for (screen, url) in results {
                try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                    .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                    .allowClipping: true,
                ])
            }
            pruneOldFiles(keeping: trackID)
        }
    }

    /// Puts the user's wallpaper back (on quit, or when the setting is turned off).
    func restoreOriginals() {
        guard let saved = defaults.dictionary(forKey: savedKey) as? [String: String] else { return }
        for screen in NSScreen.screens {
            guard let path = saved[Self.displayID(screen)] else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: [:])
        }
        defaults.removeObject(forKey: savedKey)
        lastTrackID = ""
    }

    private func saveOriginals() {
        // Keep the first saved set so repeated toggles never overwrite the user's real wallpaper.
        var saved = defaults.dictionary(forKey: savedKey) as? [String: String] ?? [:]
        for screen in NSScreen.screens {
            let id = Self.displayID(screen)
            guard saved[id] == nil, let url = NSWorkspace.shared.desktopImageURL(for: screen),
                  !url.path.hasPrefix(folder.path) else { continue }
            saved[id] = url.path
        }
        defaults.set(saved, forKey: savedKey)
    }

    private func pruneOldFiles(keeping trackID: String) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where !file.lastPathComponent.hasPrefix(trackID) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func displayID(_ screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? screen.localizedName
    }

    private static func pixelSize(_ screen: NSScreen) -> CGSize {
        let scale = min(screen.backingScaleFactor, 2)
        return CGSize(width: min(screen.frame.width * scale, 5000), height: min(screen.frame.height * scale, 5000))
    }

    /// Blurred, darkened cover filling the screen with the sharp cover in the middle.
    nonisolated private static func render(_ cover: CGImage, size: CGSize, to url: URL) -> Bool {
        let width = Int(size.width), height = Int(size.height)
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)

        // Background: the cover shrunk to a few pixels, then stretched and softly blurred,
        // which gives a smooth field of its colors (like Apple Music's backdrops).
        let tinySide = 12
        if let tinyContext = CGContext(data: nil, width: tinySide, height: tinySide, bitsPerComponent: 8, bytesPerRow: 0,
                                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
            tinyContext.interpolationQuality = .high
            tinyContext.draw(cover, in: CGRect(x: 0, y: 0, width: tinySide, height: tinySide))
            if let tiny = tinyContext.makeImage() {
                let side = max(bounds.width, bounds.height)
                let scale = side / CGFloat(tinySide)
                let field = CIImage(cgImage: tiny)
                    .samplingLinear()
                    .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    .clampedToExtent()
                    .applyingGaussianBlur(sigma: scale * 0.8)
                    .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.35, kCIInputBrightnessKey: -0.05])
                let origin = CGPoint(x: (side - bounds.width) / 2, y: (side - bounds.height) / 2)
                if let background = CIContext().createCGImage(field, from: CGRect(origin: origin, size: bounds.size)) {
                    ctx.draw(background, in: bounds)
                }
            }
        }

        // Soft vignette for legibility of the clock and login controls.
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        if let vignette = CGGradient(colorsSpace: space, colors: [
            CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.35),
        ] as CFArray, locations: [0.4, 1]) {
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            ctx.drawRadialGradient(vignette, startCenter: center, startRadius: 0, endCenter: center,
                                   endRadius: max(bounds.width, bounds.height) * 0.75, options: [.drawsAfterEndLocation])
        }

        // Sharp cover in the middle with a rounded mask and shadow.
        let coverSide = bounds.height * 0.38
        let coverRect = CGRect(x: bounds.midX - coverSide / 2, y: bounds.midY - coverSide / 2 + bounds.height * 0.04,
                               width: coverSide, height: coverSide)
        let path = CGPath(roundedRect: coverRect, cornerWidth: coverSide * 0.06, cornerHeight: coverSide * 0.06, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -coverSide * 0.03), blur: coverSide * 0.12,
                      color: CGColor(gray: 0, alpha: 0.45))
        ctx.addPath(path)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.interpolationQuality = .high
        ctx.draw(cover, in: coverRect)
        ctx.restoreGState()

        guard let image = ctx.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
