# GlassTunes

Liquid Glass music widgets for macOS 26+ (built with Xcode 27 on macOS 27).
Works with **Apple Music, Spotify, YouTube Music (Chrome/Safari/Brave/Edge) and Sonos**.
Click any widget to open a floating Liquid Glass mini player with animated album art.

<p align="center"><img src="App/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" width="160" alt="GlassTunes icon"></p>

## The app

- **Now Playing:** big animated artwork, a seek bar, controls, volume, shuffle/repeat, AutoMix, and a Recently Played grid.
- **Widgets:** live previews of all three widgets in each glass style, plus how to add them.
- **Sources:** choose a source, pick a Sonos room, and find permission settings.
- **General:** open at login, keep the mini player on top, hide the Dock icon, and refresh widgets.
- **Mini player:** a 340×156 floating panel on real Liquid Glass (`NSGlassEffectView`). Hover it to pin, expand or close.
- **Full player:** a 360×660 window in the style of Apple Music's full-screen player.
- **Playback menu:** ⌥Space play/pause, ⌘→ / ⌘← to skip, ⇧⌘S shuffle, ⇧⌘R repeat, ⇧⌘P mini player, ⇧⌘F full player.

Every page scrolls and rearranges itself to fit smaller windows.

| Widget | Size | What it shows |
| --- | --- | --- |
| Now Playing | Small | iPhone Control Center tile: artwork, source app, title, controls |
| Player | Medium | iPhone Lock Screen player: artwork, source app, scrubber, controls |
| Music Deck | Large | Big artwork, scrubber, AutoMix badge, shuffle/repeat, recently played |

Each widget has a **Glass Style** option (right-click → Edit): Artwork Tint, Frosted, or Clear.

## Sources

Pick one in the settings window, the menu bar menu or the player: **Automatic** (whatever is playing), Apple Music, Spotify, YouTube Music, or a Sonos room.

- **YouTube Music** is controlled through its browser tab. Turn on *Allow JavaScript from Apple Events*: in Chrome, View → Developer; in Safari, Develop → Developer Settings. Firefox can't be scripted.
- **Sonos** speakers are found on your local network (SSDP) and controlled over their local API. You can also type a speaker's IP address.
- macOS asks once per app for Automation permission (Privacy & Security → Automation).

## Full player

- Animated album art comes from Apple Music's public album page. GlassTunes finds the album with the iTunes Search API, for any source.
- It shows an **AutoMix** or **Crossfade** badge when transitions are on (Apple Music settings, Sonos crossfade). When a song hands off to the next one shortly before its end, the player animates "Mixing into next song". No player reports AutoMix directly, so this is inferred.

## How it works

- `App/` — a menu bar helper app. `Sources/` has one adapter per player. `PlayerHub` chooses a source, saves the state and artwork into the shared App Group folder, and reloads the widgets.
- `Widget/` — the WidgetKit extension. It runs in a sandbox, so its buttons send Darwin notifications that the helper turns into Music commands.
- `Shared/` — the model, the button actions (App Intents) and the widget views. Both targets compile this folder.

If a Music track has no artwork it can read over AppleScript, the helper looks up the artwork with Apple's iTunes Search API.

## Build

Requires Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). Set `DEVELOPMENT_TEAM` in `project.yml` to your own team ID.

```bash
xcodegen generate
xcodebuild -project GlassTunes.xcodeproj -scheme GlassTunes -derivedDataPath build -allowProvisioningUpdates build
ditto build/Build/Products/Debug/GlassTunes.app /Applications/GlassTunes.app
open /Applications/GlassTunes.app
```

To redraw the app icon, run `swift Scripts/make-icon.swift App/Assets.xcassets/AppIcon.appiconset`.

Signing uses the team in `project.yml` (`DEVELOPMENT_TEAM`). Keep GlassTunes running (turn on "Open at login") so the widgets stay up to date.
