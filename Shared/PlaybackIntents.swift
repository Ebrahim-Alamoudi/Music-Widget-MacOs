import AppIntents

enum GlassStyle: String, AppEnum, CaseIterable, Identifiable {
    case artwork, frosted, clear

    var id: String { rawValue }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Glass Style"
    static let caseDisplayRepresentations: [GlassStyle: DisplayRepresentation] = [
        .artwork: DisplayRepresentation(title: "Artwork Tint", image: .init(systemName: "paintpalette")),
        .frosted: DisplayRepresentation(title: "Frosted", image: .init(systemName: "snowflake")),
        .clear: DisplayRepresentation(title: "Clear", image: .init(systemName: "circle.dotted")),
    ]

    var title: String {
        switch self {
        case .artwork: "Artwork Tint"
        case .frosted: "Frosted"
        case .clear: "Clear"
        }
    }
}

private func send(_ command: PlayerCommand) async {
    command.post()
    if command == .playPause { SharedStore.optimisticToggle() }
    // Give the helper app a moment to update the player and write the new state before the widget reloads.
    try? await Task.sleep(for: .milliseconds(700))
}

struct TogglePlaybackIntent: AppIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await send(.playPause)
        return .result()
    }
}

struct NextTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Track"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await send(.next)
        return .result()
    }
}

struct ToggleShuffleIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Shuffle"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await send(.shuffle)
        return .result()
    }
}

struct CycleRepeatIntent: AppIntent {
    static let title: LocalizedStringResource = "Change Repeat"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await send(.repeatMode)
        return .result()
    }
}

struct PreviousTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Previous Track"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await send(.previous)
        return .result()
    }
}
