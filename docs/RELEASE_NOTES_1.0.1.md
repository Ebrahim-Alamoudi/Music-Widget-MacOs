# GlassTunes 1.0.1

## What's new
- **Music Deck widget (large)** now looks like the Now Playing card in iPhone Control Center: artwork, title, the source app's icon, a scrubber, large controls, and a volume bar. Tap the speaker icons to turn the volume down or up.
- **Shuffle and repeat** turn white the moment you click them.
- **Sonos:** when music comes through Spotify Connect, AirPlay, radio or TV, shuffle and repeat are dimmed, because the speaker ignores them. Change them in the streaming app instead.
- **Widget gallery:** GlassTunes now shows its app icon in Edit Widgets.

## Install
Same as 1.0:
1. Open the DMG and drag **GlassTunes** into **Applications**. If you have 1.0, replace it.
2. **First launch:** go to **System Settings → Privacy & Security → Open Anyway**. Or run:
   ```
   xattr -dr com.apple.quarantine /Applications/GlassTunes.app
   ```
3. If a widget still shows the old layout, click **Refresh** in General, or remove the widget and add it again.

**Requirements:** macOS 14 or later, on Apple Silicon or Intel.
