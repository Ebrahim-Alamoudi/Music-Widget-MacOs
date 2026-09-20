# GlassTunes 1.1

## Flip Clock widget
A new widget in small, medium and large: the hours and minutes flip over, the seconds tick live, and it shows the day and date. Right-click it → **Edit Widget** to customize:

- **Time:** system, 12-hour or 24-hour; seconds on or off; any time zone (its city name then appears on the widget).
- **Text:** day name, four date formats, and AM/PM.
- **Fonts:** 13 choices — System, Rounded, Monospaced, New York, Avenir Next, Futura, Helvetica Neue, Gill Sans, Didot, Georgia, Baskerville, Menlo and American Typewriter — in 8 weights.
- **Colors:** tile color (including a soft Glass tile) and a separate digit color.
- **Background:** Frosted, Clear or a color tint, matching the music widgets.
- **Clicking it** opens macOS's Clock app.

## Play again from Recently Played
Click a cover in the app's Now Playing panel to play that song again.

- **Apple Music:** plays it from your library.
- **Spotify:** plays it by its track link.
- **Sonos:** adds it back to the speaker's queue and jumps to it.
- Songs that can't be replayed — Spotify Connect, AirPlay, radio, TV and YouTube Music — stay dim and say why when you hover them.

## Install
1. Open the DMG and drag **GlassTunes** into **Applications**. If you have an older version, replace it.
2. **First launch:** go to **System Settings → Privacy & Security → Open Anyway**. Or run:
   ```
   xattr -dr com.apple.quarantine /Applications/GlassTunes.app
   ```
3. Widgets refresh automatically the first time the new version opens.

**Requirements:** macOS 14 or later, on Apple Silicon or Intel.
