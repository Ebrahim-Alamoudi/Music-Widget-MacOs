# GlassTunes 1.0.3

## What's new
- **Sonos play/pause fixed:** pressing pause on a Sonos speaker now pauses it. Before, it could send Play. Shuffle and repeat on Sonos now change to the value you pick.
- **Tappable widget bars:** click anywhere on a widget's scrubber to jump to that point. On the large widget, click the volume bar to set the level in 5% steps.
- **Artwork in Up Next:**
  - **Apple Music:** covers come straight from Music and are kept for next time.
  - **Sonos and YouTube Music:** they use the player's own images.
  - **Anything missing:** the cover is looked up in Apple's catalog.
- **Smaller switch button:** the button for switching between players on widgets is now a small circle on the app icon.
- **AutoMix label:** on the large widget, it sits a bit lower, clear of the scrubber.
- **Blank widget fix:** reinstalling GlassTunes no longer leaves widgets empty.

## Install
1. Open the DMG and drag **GlassTunes** into **Applications**. If you have an older version, replace it.
2. **First launch:** go to **System Settings → Privacy & Security → Open Anyway**. Or run:
   ```
   xattr -dr com.apple.quarantine /Applications/GlassTunes.app
   ```
3. If a widget looks outdated or empty after updating, remove it and add it again from **Edit Widgets**.

**Requirements:** macOS 14 or later, on Apple Silicon or Intel.
