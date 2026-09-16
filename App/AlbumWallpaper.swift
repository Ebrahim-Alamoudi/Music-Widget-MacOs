import AppKit

/// An earlier build could turn the album cover into the desktop wallpaper. macOS has no separate
/// lock-screen wallpaper, so that feature was removed; this only puts the user's wallpaper back
/// if it was ever changed.
@MainActor
enum AlbumWallpaper {
    private static let savedKey = "wallpaperOriginals"

    static func restoreIfNeeded() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "albumWallpaper")
        guard let saved = defaults.dictionary(forKey: savedKey) as? [String: String] else { return }
        for screen in NSScreen.screens {
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
                ?? screen.localizedName
            guard let path = saved[id], FileManager.default.fileExists(atPath: path) else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: [:])
        }
        defaults.removeObject(forKey: savedKey)
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.ibrahim.glasstunes/Wallpaper")
        try? FileManager.default.removeItem(at: folder)
    }
}
