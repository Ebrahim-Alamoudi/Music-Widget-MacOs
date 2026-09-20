import AppIntents
import SwiftUI
import WidgetKit

// The clock's design lives in Shared/FlipClockCore.swift; this file is the widget's own
// settings (Edit Widget) and its timeline.

extension ClockHourCycle: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Time Format"
    static let caseDisplayRepresentations: [ClockHourCycle: DisplayRepresentation] = [
        .system: "System Setting", .twelve: "12-Hour", .twentyFour: "24-Hour",
    ]
}

extension ClockBackground: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Background"
    static let caseDisplayRepresentations: [ClockBackground: DisplayRepresentation] = [
        .frosted: DisplayRepresentation(title: "Frosted", image: .init(systemName: "snowflake")),
        .clear: DisplayRepresentation(title: "Clear", image: .init(systemName: "circle.dotted")),
        .tinted: DisplayRepresentation(title: "Color", image: .init(systemName: "paintpalette")),
    ]
}

extension ClockColor: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tile Color"
    static let caseDisplayRepresentations: [ClockColor: DisplayRepresentation] = [
        .glass: "Glass", .graphite: "Graphite", .white: "White", .midnight: "Midnight", .red: "Red",
        .orange: "Orange", .yellow: "Yellow", .green: "Green", .mint: "Mint", .blue: "Blue",
        .purple: "Purple", .pink: "Pink",
    ]
}

extension ClockDigitColor: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Digit Color"
    static let caseDisplayRepresentations: [ClockDigitColor: DisplayRepresentation] = [
        .automatic: "Automatic", .white: "White", .black: "Black", .red: "Red", .orange: "Orange",
        .yellow: "Yellow", .green: "Green", .mint: "Mint", .blue: "Blue", .purple: "Purple", .pink: "Pink",
    ]
}

extension ClockFont: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Font"
    static let caseDisplayRepresentations: [ClockFont: DisplayRepresentation] = [
        .system: "System", .rounded: "Rounded", .monospaced: "Monospaced", .serif: "New York",
        .avenir: "Avenir Next", .futura: "Futura", .helvetica: "Helvetica Neue", .gillSans: "Gill Sans",
        .didot: "Didot", .georgia: "Georgia", .baskerville: "Baskerville", .menlo: "Menlo",
        .typewriter: "American Typewriter",
    ]
}

extension ClockWeight: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Weight"
    static let caseDisplayRepresentations: [ClockWeight: DisplayRepresentation] = [
        .ultraLight: "Ultralight", .thin: "Thin", .light: "Light", .regular: "Regular",
        .medium: "Medium", .semibold: "Semibold", .bold: "Bold", .heavy: "Heavy",
    ]
}

extension ClockDateFormat: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Date Format"
    static let caseDisplayRepresentations: [ClockDateFormat: DisplayRepresentation] = [
        .short: "Sep 17", .medium: "Sep 17, 2026", .long: "17 September 2026", .numeric: "17/09/2026",
    ]
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


extension FlipClockIntent {
    /// The widget's settings as the shared views want them.
    var style: ClockStyle {
        ClockStyle(hourCycle: hourCycle, showSeconds: showSeconds, font: font, weight: weight,
                   background: background, tileColor: tileColor, digitColor: digitColor,
                   digitColorHex: digitColorHex, tileColorHex: tileColorHex, showWeekday: showWeekday,
                   showDate: showDate, dateFormat: dateFormat, showPeriod: showPeriod, timeZone: timeZone)
    }
}

// MARK: - Widget

struct FlipClockWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "GlassTunes.FlipClock", intent: FlipClockIntent.self, provider: FlipClockProvider()) { entry in
            FlipClockView(date: entry.date, style: entry.configuration.style)
                .containerBackground(for: .widget) { ClockBackdrop(configuration: entry.configuration.style) }
                .widgetURL(URL(string: "glasstunes://clock"))
        }
        .configurationDisplayName("Flip Clock")
        .description("A flip clock with seconds, the day and the date. Right-click it › Edit Widget to customize. For flipping seconds, open the Flip Clock window from the GlassTunes menu.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
