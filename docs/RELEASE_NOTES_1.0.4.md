# GlassTunes 1.0.4

## What's new
- **Slide the widget bars:** clicking a widget's progress bar or volume control now also pops up a small glass slider at your pointer, so you can keep dragging. macOS widgets themselves can only be clicked.
- **Large widget:** the volume bar is gone, and the artwork and controls are bigger.
- **Clear glass style:** see-through Liquid Glass, with a bright rim, a soft highlight and readable white text.
- **Widget artwork:** after a song changes, widgets wait for its cover before redrawing, and quick updates are grouped together, so covers don't go missing.
- **Refresh Widgets:** reloads every GlassTunes widget on the desktop. It also runs automatically after an update, so you don't need to remove and re-add widgets.
- **Sonos in Control Center:** Sonos playback appears in macOS Now Playing, with working play/pause and skip. Turn it on or off in General.
- **Players and slider pop-up:**
  - They respond to the first click, so you can drag them while another app is in front.
  - They no longer take focus from the app you're using.
  - They no longer have an invisible border that blocked clicks on windows underneath.

## Install
1. Open the DMG and drag **GlassTunes** into **Applications**. If you have an older version, replace it.
2. **First launch:** go to **System Settings → Privacy & Security → Open Anyway**. Or run:
   ```
   xattr -dr com.apple.quarantine /Applications/GlassTunes.app
   ```
3. Widgets refresh automatically the first time the new version opens.

**Requirements:** macOS 14 or later, on Apple Silicon or Intel.
