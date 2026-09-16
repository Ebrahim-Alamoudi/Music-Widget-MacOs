# GlassTunes 1.0

Liquid Glass music widgets and a floating mini player for macOS. They work with **Apple Music, Spotify, YouTube Music and Sonos**.

## Requirements
- macOS 26 or later (built and tested on macOS 27)
- Apple Silicon or Intel Mac

## Install
1. Download **GlassTunes-1.0.dmg**, open it, and drag **GlassTunes** into **Applications**.
2. Open GlassTunes from Applications.
3. **First launch only:** this build isn't notarized by Apple yet, so macOS says it "can't be verified". To open it:
   - Click **Done** in that message.
   - Open **System Settings → Privacy & Security**, scroll down, click **Open Anyway** next to GlassTunes, and confirm.

   Or run this command in Terminal instead:
   ```
   xattr -dr com.apple.quarantine /Applications/GlassTunes.app
   ```
4. Allow the permission prompts: controlling Music, Spotify or your browser, and **Local Network** if you use Sonos.
5. Right-click the desktop → **Edit Widgets** → search **GlassTunes**.

## Features
- **Three widgets:** Now Playing (small), Player (medium) and Music Deck (large), each in Artwork Tint, Frosted or Clear glass.
- **Sources:** Automatic (prefers music playing on the Mac over Sonos), Apple Music, Spotify, YouTube Music (Chrome, Safari, Brave or Edge) and Sonos rooms. The switch button on a widget moves between active players.
- **Mini player and full player:** real Liquid Glass, with Apple Music's animated album art when the album has it.
- **Up Next queue:** for Apple Music, Sonos and YouTube Music. Click a song to play it.
- **Controls:** shuffle, repeat, volume, seek, and an AutoMix/Crossfade indicator.
- **Menu bar:** show an icon, the song title, or both, or hide it. The Dock icon can be hidden too.

## Known limits
- Spotify doesn't share its queue or crossfade setting with other apps.
- YouTube Music needs **Allow JavaScript from Apple Events** turned on in the browser. Firefox isn't supported.
- Widgets update only while GlassTunes is running. Turn on **Open at login** in General.

**Checksums (SHA-256):** see `SHA256SUMS.txt` attached to this release.
