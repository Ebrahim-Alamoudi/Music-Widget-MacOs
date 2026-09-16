# GlassTunes 1.0.2

## What's new
- **Smooth volume:** the slider follows your pointer right away, and only the latest volume is sent to the player, so it no longer lags or jumps back.
- **Faster Up Next:** the queue is loaded ahead of time, so it usually opens instantly. Apple Music's queue now loads in two requests instead of dozens, and Sonos requests run at the same time.
- **Press effect:**
  - **Where:** the play, skip, shuffle, repeat, queue and header buttons.
  - **What happens:** the icon bounces, a soft ripple spreads out, and Force Touch trackpads give a light tap.
  - **Sources:** choosing a source pops its checkmark.

## Install
1. Open the DMG and drag **GlassTunes** into **Applications**. If you have an older version, replace it.
2. **First launch:** go to **System Settings → Privacy & Security → Open Anyway**. Or run:
   ```
   xattr -dr com.apple.quarantine /Applications/GlassTunes.app
   ```

**Requirements:** macOS 14 or later, on Apple Silicon or Intel.
