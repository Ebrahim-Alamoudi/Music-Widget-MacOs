#!/bin/zsh
# Builds a Release copy of GlassTunes and packages it for a GitHub release.
# Usage: Scripts/make-release.sh            -> dist/GlassTunes-<version>.dmg (+ .zip, checksums)
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
DIST="$ROOT/dist"
BUILD="$ROOT/build/release"

xcodegen generate >/dev/null
rm -rf "$BUILD" "$DIST"
mkdir -p "$DIST"

# Generic destination = universal binary (Apple Silicon + Intel).
xcodebuild -project GlassTunes.xcodeproj -scheme GlassTunes -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$BUILD" -allowProvisioningUpdates clean build | grep -E "error:|BUILD" || true

APP="$BUILD/Build/Products/Release/GlassTunes.app"
[[ -d "$APP" ]] || { echo "Build failed"; exit 1; }
codesign --verify --deep --strict "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
NAME="GlassTunes-$VERSION"

# DMG with a drag-to-Applications shortcut.
STAGE=$(mktemp -d)
ditto "$APP" "$STAGE/GlassTunes.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "GlassTunes $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DIST/$NAME.dmg" >/dev/null
rm -rf "$STAGE"

# ZIP for people who prefer it (ditto keeps signatures and bundle structure intact).
ditto -c -k --keepParent "$APP" "$DIST/$NAME.zip"

(cd "$DIST" && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS.txt)

# Keep macOS from using this build copy for desktop widgets.
Scripts/unregister-build-copies.sh
echo "Created:"
ls -lh "$DIST"
