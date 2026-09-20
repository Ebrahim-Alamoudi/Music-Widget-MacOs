# GlassTunes 1.2

## Flip Clock widget
- **Seconds** now show as their own cards, in the same design as the hours and minutes — same size, spacing, font and colors.
- **Every card changes as two halves**, the top dropping in from above and the bottom rising from below, like a split-flap board.
- **Digits fit every font.** Each font is measured so numbers always sit inside their card, in Didot, Futura, Georgia, American Typewriter and the rest.
- **Custom colors:** type any hex value for the digits or the cards, alongside the presets.
- **Light:** the widget process sits at about 0% CPU and 9 MB, even while updating every second.

Right-click the clock → **Edit Widget** for the time format, seconds, font, weight, colors, background, date options and time zone.

## Music
- **Recently Played:** click a cover in the app to play that song again (Apple Music, Spotify, and Sonos when the song came from its own queue).

## Good to know
macOS draws widgets as prepared frames, so on a busy Mac it may occasionally skip one second. The hours and minutes are always correct.

## Install
1. Open the DMG and drag **GlassTunes** into **Applications**, replacing any older version.
2. **First launch:** go to **System Settings → Privacy & Security → Open Anyway**. Or run:
   ```
   xattr -dr com.apple.quarantine /Applications/GlassTunes.app
   ```
3. If a widget looks outdated, remove it and add it again from Edit Widgets.

**Requirements:** macOS 14 or later, on Apple Silicon or Intel.
