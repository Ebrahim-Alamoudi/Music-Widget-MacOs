// Renders the GlassTunes app icon: a liquid-glass music tile on a vivid gradient.
// Usage: swift Scripts/make-icon.swift App/Assets.xcassets/AppIcon.appiconset
import AppKit

let canvas: CGFloat = 1024
let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)

    // macOS icon grid: 824pt tile centered in 1024 with a continuous-looking corner.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow.
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    cg.addPath(tilePath)
    cg.setFillColor(NSColor.black.cgColor)
    cg.fillPath()
    cg.restoreGState()

    // Background gradient: pink → magenta → violet → blue.
    cg.saveGState()
    cg.addPath(tilePath)
    cg.clip()
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let colors = [
        NSColor(srgbRed: 1.00, green: 0.33, blue: 0.45, alpha: 1).cgColor,
        NSColor(srgbRed: 0.93, green: 0.20, blue: 0.62, alpha: 1).cgColor,
        NSColor(srgbRed: 0.53, green: 0.25, blue: 0.96, alpha: 1).cgColor,
        NSColor(srgbRed: 0.22, green: 0.45, blue: 1.00, alpha: 1).cgColor,
    ] as CFArray
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.35, 0.72, 1])!
    cg.drawLinearGradient(gradient, start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])

    // Soft color blobs for depth.
    for (center, radius, color) in [
        (CGPoint(x: 300, y: 760), 360.0, NSColor(srgbRed: 1, green: 0.62, blue: 0.4, alpha: 0.55)),
        (CGPoint(x: 780, y: 260), 380.0, NSColor(srgbRed: 0.2, green: 0.85, blue: 1, alpha: 0.45)),
    ] {
        let blob = CGGradient(colorsSpace: space, colors: [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
        cg.drawRadialGradient(blob, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    // Liquid glass disc.
    let disc = CGRect(x: 232, y: 232, width: 560, height: 560)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    cg.addEllipse(in: disc)
    cg.setFillColor(NSColor.white.withAlphaComponent(0.18).cgColor)
    cg.fillPath()
    cg.restoreGState()

    cg.saveGState()
    cg.addEllipse(in: disc)
    cg.clip()
    let sheen = CGGradient(colorsSpace: space, colors: [
        NSColor.white.withAlphaComponent(0.55).cgColor,
        NSColor.white.withAlphaComponent(0.05).cgColor,
        NSColor.white.withAlphaComponent(0.0).cgColor,
        NSColor.white.withAlphaComponent(0.18).cgColor,
    ] as CFArray, locations: [0, 0.45, 0.7, 1])!
    cg.drawLinearGradient(sheen, start: CGPoint(x: disc.minX, y: disc.maxY), end: CGPoint(x: disc.maxX, y: disc.minY), options: [])
    cg.restoreGState()

    // Rim light.
    cg.saveGState()
    cg.addEllipse(in: disc.insetBy(dx: 3, dy: 3))
    cg.setLineWidth(6)
    cg.replacePathWithStrokedPath()
    cg.clip()
    let rim = CGGradient(colorsSpace: space, colors: [
        NSColor.white.withAlphaComponent(0.95).cgColor,
        NSColor.white.withAlphaComponent(0.1).cgColor,
        NSColor.white.withAlphaComponent(0.6).cgColor,
    ] as CFArray, locations: [0, 0.5, 1])!
    cg.drawLinearGradient(rim, start: CGPoint(x: disc.minX, y: disc.maxY), end: CGPoint(x: disc.maxX, y: disc.minY), options: [])
    cg.restoreGState()

    // Music note glyph.
    let config = NSImage.SymbolConfiguration(pointSize: 300, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let note = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let noteSize = note.size
        let rect = CGRect(x: disc.midX - noteSize.width / 2 - 8, y: disc.midY - noteSize.height / 2,
                          width: noteSize.width, height: noteSize.height)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: NSColor.black.withAlphaComponent(0.25).cgColor)
        note.draw(in: rect)
        cg.restoreGState()
    }

    // Top gloss on the tile.
    let gloss = CGGradient(colorsSpace: space, colors: [
        NSColor.white.withAlphaComponent(0.28).cgColor, NSColor.white.withAlphaComponent(0).cgColor,
    ] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(gloss, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 600), options: [])
    cg.restoreGState()

    // Tile edge highlight.
    cg.addPath(CGPath(roundedRect: tile.insetBy(dx: 2, dy: 2), cornerWidth: 183, cornerHeight: 183, transform: nil))
    cg.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
    cg.setLineWidth(4)
    cg.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try! render(size: pixels).write(to: out.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(base)x\(base)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: out.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(out.path)")
