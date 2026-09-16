# GlassTunes 1.0.5

## What's new
- **Clear widgets:** the Clear glass style is now fully transparent on the desktop, with a light rim, a soft highlight and readable white text. Before, it could turn into a cloudy fill when you clicked the desktop.
- **Clear style tip:** when you pick **Clear** in the Widgets section, GlassTunes explains the system setting that controls the panel macOS draws behind every desktop widget, with a button that opens Appearance settings.

## Good to know
macOS draws its own glass panel behind all desktop widgets. For widgets that stay clear everywhere, set **System Settings → Appearance → Icon & widget style** to **Clear**.

## Install
1. Open the DMG and drag **GlassTunes** into **Applications**. If you have an older version, replace it.
2. **First launch:** go to **System Settings → Privacy & Security → Open Anyway**. Or run:
   ```
   xattr -dr com.apple.quarantine /Applications/GlassTunes.app
   ```
3. Widgets refresh automatically the first time the new version opens.

**Requirements:** macOS 14 or later, on Apple Silicon or Intel.
