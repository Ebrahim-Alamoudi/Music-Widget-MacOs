import AppIntents
import AppKit
import SwiftUI
import WidgetKit

// MARK: - Options (edited from the widget's own "Edit Widget" menu)

enum ClockHourCycle: String, AppEnum {
    case system, twelve, twentyFour

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Time Format"
    static let caseDisplayRepresentations: [ClockHourCycle: DisplayRepresentation] = [
        .system: "System Setting", .twelve: "12-Hour", .twentyFour: "24-Hour",
    ]
}

enum ClockBackground: String, AppEnum {
    case frosted, clear, tinted

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Background"
    static let caseDisplayRepresentations: [ClockBackground: DisplayRepresentation] = [
        .frosted: DisplayRepresentation(title: "Frosted", image: .init(systemName: "snowflake")),
        .clear: DisplayRepresentation(title: "Clear", image: .init(systemName: "circle.dotted")),
        .tinted: DisplayRepresentation(title: "Color", image: .init(systemName: "paintpalette")),
    ]
}

enum ClockColor: String, AppEnum {
    case glass, graphite, white, midnight, red, orange, yellow, green, mint, blue, purple, pink

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tile Color"
    static let caseDisplayRepresentations: [ClockColor: DisplayRepresentation] = [
        .glass: "Glass", .graphite: "Graphite", .white: "White", .midnight: "Midnight", .red: "Red",
        .orange: "Orange", .yellow: "Yellow", .green: "Green", .mint: "Mint", .blue: "Blue",
        .purple: "Purple", .pink: "Pink",
    ]

    var base: Color {
        switch self {
        case .glass: Color.white.opacity(0.08)
        case .graphite: Color(white: 0.18)
        case .white: Color(white: 0.95)
        case .midnight: Color(red: 0.08, green: 0.11, blue: 0.24)
        case .red: Color(red: 0.86, green: 0.18, blue: 0.22)
        case .orange: Color(red: 0.95, green: 0.50, blue: 0.13)
        case .yellow: Color(red: 0.96, green: 0.76, blue: 0.10)
        case .green: Color(red: 0.19, green: 0.66, blue: 0.33)
        case .mint: Color(red: 0.18, green: 0.74, blue: 0.68)
        case .blue: Color(red: 0.13, green: 0.44, blue: 0.94)
        case .purple: Color(red: 0.52, green: 0.30, blue: 0.90)
        case .pink: Color(red: 0.95, green: 0.29, blue: 0.54)
        }
    }

    var isLight: Bool { self == .white || self == .yellow }
}

enum ClockDigitColor: String, AppEnum {
    case automatic, white, black, red, orange, yellow, green, mint, blue, purple, pink

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Digit Color"
    static let caseDisplayRepresentations: [ClockDigitColor: DisplayRepresentation] = [
        .automatic: "Automatic", .white: "White", .black: "Black", .red: "Red", .orange: "Orange",
        .yellow: "Yellow", .green: "Green", .mint: "Mint", .blue: "Blue", .purple: "Purple", .pink: "Pink",
    ]

    func color(on tile: ClockColor) -> Color {
        switch self {
        case .automatic: tile.isLight ? Color(white: 0.1) : Color.white.opacity(0.92)
        case .white: .white
        case .black: Color(white: 0.08)
        default: ClockColor(rawValue: rawValue)?.base ?? .white
        }
    }
}

enum ClockFont: String, AppEnum {
    case system, rounded, monospaced, serif, avenir, futura, helvetica, gillSans, didot, georgia, baskerville, menlo, typewriter

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Font"
    static let caseDisplayRepresentations: [ClockFont: DisplayRepresentation] = [
        .system: "System", .rounded: "Rounded", .monospaced: "Monospaced", .serif: "New York",
        .avenir: "Avenir Next", .futura: "Futura", .helvetica: "Helvetica Neue", .gillSans: "Gill Sans",
        .didot: "Didot", .georgia: "Georgia", .baskerville: "Baskerville", .menlo: "Menlo",
        .typewriter: "American Typewriter",
    ]

    var family: String? {
        switch self {
        case .avenir: "Avenir Next"
        case .futura: "Futura"
        case .helvetica: "Helvetica Neue"
        case .gillSans: "Gill Sans"
        case .didot: "Didot"
        case .georgia: "Georgia"
        case .baskerville: "Baskerville"
        case .menlo: "Menlo"
        case .typewriter: "American Typewriter"
        default: nil
        }
    }
}

enum ClockWeight: String, AppEnum {
    case ultraLight, thin, light, regular, medium, semibold, bold, heavy

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Weight"
    static let caseDisplayRepresentations: [ClockWeight: DisplayRepresentation] = [
        .ultraLight: "Ultralight", .thin: "Thin", .light: "Light", .regular: "Regular",
        .medium: "Medium", .semibold: "Semibold", .bold: "Bold", .heavy: "Heavy",
    ]

    var system: NSFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        }
    }

    /// NSFontManager's 0–15 weight scale.
    var managerWeight: Int {
        switch self {
        case .ultraLight: 2
        case .thin: 3
        case .light: 4
        case .regular: 5
        case .medium: 6
        case .semibold: 8
        case .bold: 9
        case .heavy: 11
        }
    }
}

enum ClockDateFormat: String, AppEnum {
    case short, medium, long, numeric

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Date Format"
    static let caseDisplayRepresentations: [ClockDateFormat: DisplayRepresentation] = [
        .short: "Sep 17", .medium: "Sep 17, 2026", .long: "17 September 2026", .numeric: "17/09/2026",
    ]

    var template: String {
        switch self {
        case .short: "MMM d"
        case .medium: "MMM d y"
        case .long: "d MMMM y"
        case .numeric: "dd MM y"
        }
    }
}

struct TimeZoneOptions: DynamicOptionsProvider {
    func results() async throws -> [String] {
        TimeZone.knownTimeZoneIdentifiers.sorted()
    }
}

struct FlipClockIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Flip Clock"
    static let description = IntentDescription("Choose how the flip clock looks.")

    @Parameter(title: "Time Format", default: .system)
    var hourCycle: ClockHourCycle

    @Parameter(title: "Show Seconds", default: true)
    var showSeconds: Bool

    @Parameter(title: "Font", default: .system)
    var font: ClockFont

    @Parameter(title: "Weight", default: .regular)
    var weight: ClockWeight

    @Parameter(title: "Background", default: .frosted)
    var background: ClockBackground

    @Parameter(title: "Tile Color", default: .glass)
    var tileColor: ClockColor

    @Parameter(title: "Digit Color", default: .automatic)
    var digitColor: ClockDigitColor

    @Parameter(title: "Custom Digit Color", description: "A hex color like #FF9500. Overrides Digit Color when set.")
    var digitColorHex: String?

    @Parameter(title: "Custom Tile Color", description: "A hex color like #1C1C2E. Overrides Tile Color when set.")
    var tileColorHex: String?

    @Parameter(title: "Show Day Name", default: true)
    var showWeekday: Bool

    @Parameter(title: "Show Date", default: true)
    var showDate: Bool

    @Parameter(title: "Date Format", default: .medium)
    var dateFormat: ClockDateFormat

    @Parameter(title: "Show AM/PM", default: true)
    var showPeriod: Bool

    @Parameter(title: "Time Zone", description: "Leave empty to use this Mac's time zone.", optionsProvider: TimeZoneOptions())
    var timeZone: String?

    init() {}

    static var parameterSummary: some ParameterSummary {
        Summary {
            \.$hourCycle
            \.$showSeconds
            \.$font
            \.$weight
            \.$background
            \.$tileColor
            \.$digitColor
            \.$digitColorHex
            \.$tileColorHex
            \.$showWeekday
            \.$showDate
            \.$dateFormat
            \.$showPeriod
            \.$timeZone
        }
    }
}

// MARK: - Timeline

struct ClockEntry: TimelineEntry {
    let date: Date
    let configuration: FlipClockIntent
}

struct FlipClockProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ClockEntry {
        ClockEntry(date: .now, configuration: FlipClockIntent())
    }

    func snapshot(for configuration: FlipClockIntent, in context: Context) async -> ClockEntry {
        ClockEntry(date: .now, configuration: configuration)
    }

    /// One entry per minute: WidgetKit prepares every entry ahead of time, so per-second entries
    /// would keep the widget process busy. Seconds tick with a live timer instead (`SecondsTile`).
    func timeline(for configuration: FlipClockIntent, in context: Context) async -> Timeline<ClockEntry> {
        let now = Date()
        let minute = Calendar.current.dateInterval(of: .minute, for: now)?.start ?? now
        let entries = (0..<90).map { ClockEntry(date: minute.addingTimeInterval(Double($0) * 60), configuration: configuration) }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

// MARK: - Time and fonts

struct ClockFace {
    let hourDigits: [Character]
    let minuteDigits: [Character]
    let secondDigits: [Character]
    let minuteStart: Date
    let header: String
    let weekday: String
    let dateText: String
    let period: String?

    init(date: Date, configuration c: FlipClockIntent) {
        let zone = c.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        var calendar = Calendar.current
        calendar.timeZone = zone

        let uses12Hour: Bool = switch c.hourCycle {
        case .twelve: true
        case .twentyFour: false
        case .system: DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false
        }

        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        var hour = parts.hour ?? 0
        if uses12Hour {
            hour %= 12
            if hour == 0 { hour = 12 }
        }
        hourDigits = Array(String(format: "%02d", hour))
        minuteDigits = Array(String(format: "%02d", parts.minute ?? 0))
        secondDigits = Array(String(format: "%02d", parts.second ?? 0))
        minuteStart = date.addingTimeInterval(-Double(parts.second ?? 0))

        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.locale = .current
        if uses12Hour && c.showPeriod {
            formatter.dateFormat = "a"
            period = formatter.string(from: date)
        } else {
            period = nil
        }
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        weekday = formatter.string(from: date)
        formatter.setLocalizedDateFormatFromTemplate(c.dateFormat.template)
        dateText = formatter.string(from: date)

        // "Thursday, Sep 17, 2026  AM · Tokyo"
        var line = [c.showWeekday ? weekday : nil, c.showDate ? dateText : nil].compactMap { $0 }.joined(separator: ", ")
        if let period { line += line.isEmpty ? period : "  \(period)" }
        if c.timeZone != nil, zone.identifier != TimeZone.current.identifier,
           let city = zone.identifier.split(separator: "/").last {
            line += (line.isEmpty ? "" : " · ") + city.replacingOccurrences(of: "_", with: " ")
        }
        header = line
    }
}

/// A font with tabular digits (numbers keep their width), measured so it always fits its card:
/// fonts differ a lot in how wide and tall their digits are at the same point size.
struct DigitFont {
    let font: Font
    /// Width of one digit.
    let advance: CGFloat
    /// Width of the "0:" that macOS puts in front of a countdown's seconds.
    let prefixWidth: CGFloat

    init(_ choice: ClockFont, weight: ClockWeight, size: CGFloat) {
        self.init(Self.make(choice, weight: weight, size: size))
    }

    /// Picks the largest size whose digits fit inside `tile` (one digit per tile).
    init(_ choice: ClockFont, weight: ClockWeight, fitting tile: CGSize) {
        var nsFont = Self.make(choice, weight: weight, size: max(4, tile.height * 0.78))
        // Height: keep the digits inside the card, using the font's own cap height.
        let capRatio = nsFont.capHeight / nsFont.pointSize
        if capRatio > 0 {
            let maxSize = tile.height * 0.72 / capRatio
            if maxSize < nsFont.pointSize {
                nsFont = Self.make(choice, weight: weight, size: max(4, maxSize))
            }
        }
        // Width: shrink again if a digit is wider than the card allows.
        let width = ("0" as NSString).size(withAttributes: [.font: nsFont]).width
        if width > tile.width * 0.82 {
            nsFont = Self.make(choice, weight: weight, size: max(4, nsFont.pointSize * tile.width * 0.82 / width))
        }
        self.init(nsFont)
    }

    private init(_ nsFont: NSFont) {
        font = Font(nsFont as CTFont)
        advance = ("0" as NSString).size(withAttributes: [.font: nsFont]).width
        prefixWidth = ("0:" as NSString).size(withAttributes: [.font: nsFont]).width
    }

    private static func make(_ choice: ClockFont, weight: ClockWeight, size: CGFloat) -> NSFont {
        var nsFont: NSFont
        switch choice {
        case .system:
            nsFont = .systemFont(ofSize: size, weight: weight.system)
        case .rounded:
            let base = NSFont.systemFont(ofSize: size, weight: weight.system)
            nsFont = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        case .monospaced:
            nsFont = .monospacedSystemFont(ofSize: size, weight: weight.system)
        case .serif:
            let base = NSFont.systemFont(ofSize: size, weight: weight.system)
            nsFont = base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        default:
            nsFont = choice.family.flatMap {
                NSFontManager.shared.font(withFamily: $0, traits: [], weight: weight.managerWeight, size: size)
            } ?? .systemFont(ofSize: size, weight: weight.system)
        }
        // Tabular (equal-width) numbers, so digits don't shift as they change.
        let tabular = nsFont.fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
            ]],
        ])
        return NSFont(descriptor: tabular, size: size) ?? nsFont
    }
}

// MARK: - Views

struct FlipClockView: View {
    let entry: ClockEntry
    var familyOverride: WidgetFamily?
    @Environment(\.widgetFamily) private var environmentFamily

    private var c: FlipClockIntent { entry.configuration }
    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    var body: some View {
        let face = ClockFace(date: entry.date, configuration: c)
        Group {
            switch family {
            case .systemSmall: small(face)
            case .systemLarge: large(face)
            default: medium(face)
            }
        }
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(c.background == .clear ? 0.3 : 0), radius: 2, y: 1)
    }

    private var style: TileStyle {
        TileStyle(tile: c.tileColor,
                  digit: Color(hex: c.digitColorHex) ?? c.digitColor.color(on: c.tileColor),
                  background: c.background,
                  tileOverride: Color(hex: c.tileColorHex))
    }

    // Medium: date line, then HH MM (SS) as grouped pairs — like a classic flip clock.
    private func medium(_ face: ClockFace) -> some View {
        VStack(spacing: 10) {
            headerLine(face.header, size: 15)
            GeometryReader { geo in
                let inner: CGFloat = 5, outer: CGFloat = c.showSeconds ? 16 : 26
                let height = geo.size.height
                // The seconds sit smaller than the hours and minutes, so they stay the main event.
                let secondsHeight = height * 0.62
                let secondsWidth = c.showSeconds
                    ? SecondsTile.width(for: DigitFont(c.font, weight: c.weight,
                                                       fitting: CGSize(width: secondsHeight * 0.62, height: secondsHeight)))
                    : 0
                let groups: CGFloat = c.showSeconds ? 3 : 2
                let tileWidth = (geo.size.width - 2 * inner - (groups - 1) * outer - secondsWidth) / 4
                HStack(spacing: outer) {
                    pair(face.hourDigits, slot: "h", width: tileWidth, height: height, gap: inner)
                    pair(face.minuteDigits, slot: "m", width: tileWidth, height: height, gap: inner)
                    if c.showSeconds {
                        SecondsTile(minuteStart: face.minuteStart, height: secondsHeight,
                                    font: c.font, weight: c.weight, style: style)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // Small: date line, HH over MM; seconds live under them if enabled.
    private func small(_ face: ClockFace) -> some View {
        VStack(spacing: 6) {
            headerLine(face.header, size: 11)
            GeometryReader { geo in
                let gap: CGFloat = 5
                let rows: CGFloat = c.showSeconds ? 2.45 : 2
                let height = (geo.size.height - gap * (rows > 2 ? 2 : 1)) / rows
                let tileWidth = min((geo.size.width - gap) / 2, height * 0.9)
                VStack(spacing: gap) {
                    pair(face.hourDigits, slot: "h", width: tileWidth, height: height, gap: gap)
                    pair(face.minuteDigits, slot: "m", width: tileWidth, height: height, gap: gap)
                    if c.showSeconds {
                        SecondsTile(minuteStart: face.minuteStart, height: height * 0.45,
                                    font: c.font, weight: c.weight, style: style)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // Large: big day name and date, HH MM row, seconds row.
    private func large(_ face: ClockFace) -> some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                if c.showWeekday {
                    Text(face.weekday)
                        .font(DigitFont(c.font, weight: c.weight == .regular ? .semibold : c.weight, size: 26).font)
                        .widgetAccentable()
                }
                let details = [c.showDate ? face.dateText : nil, face.period].compactMap { $0 }.joined(separator: "  ")
                if !details.isEmpty {
                    Text(details)
                        .font(DigitFont(c.font, weight: .regular, size: 15).font)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            GeometryReader { geo in
                let inner: CGFloat = 7, outer: CGFloat = 16
                let tileWidth = (geo.size.width - inner * 2 - outer) / 4
                let secondsHeight = c.showSeconds ? geo.size.height * 0.3 : 0
                let height = geo.size.height - secondsHeight - (c.showSeconds ? 10 : 0)
                VStack(spacing: 10) {
                    HStack(spacing: outer) {
                        pair(face.hourDigits, slot: "h", width: tileWidth, height: height, gap: inner)
                        pair(face.minuteDigits, slot: "m", width: tileWidth, height: height, gap: inner)
                    }
                    if c.showSeconds {
                        SecondsTile(minuteStart: face.minuteStart, height: secondsHeight,
                                    font: c.font, weight: c.weight, style: style)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func pair(_ digits: [Character], slot: String, width: CGFloat, height: CGFloat, gap: CGFloat) -> some View {
        let font = DigitFont(c.font, weight: c.weight, fitting: CGSize(width: width, height: height)).font
        return HStack(spacing: gap) {
            ForEach(0..<2, id: \.self) { index in
                FlipTile(digit: digits[index], slot: "\(slot)\(index)", font: font, style: style)
                    .frame(width: max(0, width), height: max(0, height))
            }
        }
    }

    @ViewBuilder
    private func headerLine(_ text: String, size: CGFloat) -> some View {
        if !text.isEmpty {
            Text(text)
                .font(DigitFont(c.font, weight: .regular, size: size).font)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .widgetAccentable()
        }
    }
}

struct TileStyle {
    var tile: ClockColor
    var digit: Color
    var background: ClockBackground
    /// Set when the user typed a hex color for the tiles.
    var tileOverride: Color?
}

extension Color {
    /// "#FF9500", "FF9500" or "#FF9500CC" → a color; anything else → nil.
    init?(hex: String?) {
        guard var text = hex?.trimmingCharacters(in: .whitespaces).uppercased(), !text.isEmpty else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        guard [6, 8].contains(text.count), let value = UInt64(text, radix: 16) else { return nil }
        let hasAlpha = text.count == 8
        let shift = hasAlpha ? 8 : 0
        self.init(.sRGB,
                  red: Double((value >> (16 + shift)) & 0xFF) / 255,
                  green: Double((value >> (8 + shift)) & 0xFF) / 255,
                  blue: Double((value >> shift) & 0xFF) / 255,
                  opacity: hasAlpha ? Double(value & 0xFF) / 255 : 1)
    }
}

/// The card behind a digit: rounded, split by a hairline seam, top half catching a little light.
struct TileFace: View {
    let style: TileStyle

    var body: some View {
        GeometryReader { geo in
            let corner = min(geo.size.width, geo.size.height) * 0.1
            let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
            ZStack {
                shape.fill(fill)
                VStack(spacing: 0) {
                    Rectangle().fill(.white.opacity(style.tile.isLight ? 0.08 : 0.04))
                    Rectangle().fill(.black.opacity(style.tile == .glass ? 0.02 : 0.06))
                }
                .clipShape(shape)
            }
            .overlay { shape.strokeBorder(.white.opacity(style.background == .clear ? 0.28 : 0.1), lineWidth: 0.6) }
        }
    }

    private var fill: AnyShapeStyle {
        if let custom = style.tileOverride {
            return AnyShapeStyle(LinearGradient(colors: [custom.opacity(0.92), custom], startPoint: .top, endPoint: .bottom))
        }
        if style.tile == .glass {
            return AnyShapeStyle(Color.white.opacity(style.background == .clear ? 0.1 : 0.08))
        }
        return AnyShapeStyle(LinearGradient(colors: [style.tile.base.opacity(0.92), style.tile.base],
                                            startPoint: .top, endPoint: .bottom))
    }
}

/// Seam drawn over the digit, like the split of a real flip card.
private struct Seam: View {
    let style: TileStyle

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(style.tile.isLight ? Color.white.opacity(0.9) : Color.black.opacity(0.35))
                .frame(height: max(1, geo.size.height * 0.008))
                .frame(maxHeight: .infinity)
        }
    }
}

struct FlipTile: View {
    let digit: Character
    let slot: String
    let font: Font
    let style: TileStyle

    var body: some View {
        ZStack {
            TileFace(style: style)
            Text(String(digit))
                .font(font)
                .minimumScaleFactor(0.3)
                .foregroundStyle(style.digit)
                .widgetAccentable()
                .id("\(slot)-\(digit)")
                .transition(.push(from: .top))
            Seam(style: style)
        }
    }
}

/// Seconds card. macOS updates its own countdown text inside a widget, and that text reads "0:SS".
/// It must be left completely alone — clipping, resizing or recoloring it with a gradient makes
/// WidgetKit stop updating it — so the card is simply made wide enough to hold it.
struct SecondsTile: View {
    let minuteStart: Date
    let height: CGFloat
    let font: ClockFont
    let weight: ClockWeight
    let style: TileStyle

    /// Width this card needs for the whole "0:SS".
    static func width(for font: DigitFont) -> CGFloat { font.prefixWidth + font.advance * 2 + 10 }

    var body: some View {
        let digitFont = DigitFont(font, weight: weight, fitting: CGSize(width: height * 0.62, height: height))
        let width = Self.width(for: digitFont)
        ZStack {
            TileFace(style: style)
            Text(timerInterval: minuteStart...minuteStart.addingTimeInterval(60), countsDown: false)
                .font(digitFont.font)
                .foregroundStyle(style.digit)
            Seam(style: style)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: min(width, height) * 0.1, style: .continuous))
    }
}

struct ClockBackdrop: View {
    let configuration: FlipClockIntent

    var body: some View {
        switch configuration.background {
        case .clear:
            ClearLiquidGlass()
        case .frosted:
            ZStack {
                Color(red: 0.14, green: 0.14, blue: 0.19)
                if let tint = Color(hex: configuration.tileColorHex) ?? (configuration.tileColor == .glass ? nil : configuration.tileColor.base) {
                    RadialGradient(colors: [tint.opacity(0.3), .clear],
                                   center: .topLeading, startRadius: 0, endRadius: 300)
                }
                LinearGradient(stops: [.init(color: .white.opacity(0.1), location: 0), .init(color: .clear, location: 0.5)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        case .tinted:
            let tint = Color(hex: configuration.tileColorHex)
                ?? (configuration.tileColor == .glass ? Color(red: 0.35, green: 0.33, blue: 0.62) : configuration.tileColor.base)
            ZStack {
                LinearGradient(colors: [tint, tint.opacity(0.55), .black.opacity(0.85)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                LinearGradient(stops: [.init(color: .white.opacity(0.18), location: 0), .init(color: .clear, location: 0.45)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
}

// MARK: - Widget

struct FlipClockWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "GlassTunes.FlipClock", intent: FlipClockIntent.self, provider: FlipClockProvider()) { entry in
            FlipClockView(entry: entry)
                .containerBackground(for: .widget) { ClockBackdrop(configuration: entry.configuration) }
                .widgetURL(URL(string: "glasstunes://clock"))
        }
        .configurationDisplayName("Flip Clock")
        .description("A flip clock with seconds, the day and the date. Right-click it › Edit Widget to customize.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
