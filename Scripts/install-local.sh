#!/bin/zsh
# Builds GlassTunes, installs it to /Applications and makes sure macOS only uses that copy
# (Xcode registers every build product, and stale copies can leave widgets blank).
set -euo pipefail

cd "$(dirname "$0")/.."
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

xcodegen generate >/dev/null
xcodebuild -project GlassTunes.xcodeproj -scheme GlassTunes -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build -allowProvisioningUpdates build | grep -E "error:|BUILD" || true

pkill -x GlassTunes || true
sleep 1
rm -rf /Applications/GlassTunes.app
ditto build/Build/Products/Release/GlassTunes.app /Applications/GlassTunes.app

Scripts/unregister-build-copies.sh
"$LSR" -f -R -trusted /Applications/GlassTunes.app
pluginkit -a /Applications/GlassTunes.app/Contents/PlugIns/GlassTunesWidgets.appex

open /Applications/GlassTunes.app
# Restart the widget service so desktop widgets reload from the installed copy.
killall chronod 2>/dev/null || true
echo "Installed. Registered widget extensions:"
pluginkit -m -v -i com.ibrahim.glasstunes.widgets
