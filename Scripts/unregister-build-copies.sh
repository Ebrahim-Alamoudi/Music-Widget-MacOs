#!/bin/zsh
# Removes GlassTunes build products from Launch Services and PlugInKit.
cd "$(dirname "$0")/.."
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
for app in $PWD/build/**/GlassTunes.app(N/); do
  pluginkit -r "$app/Contents/PlugIns/GlassTunesWidgets.appex" 2>/dev/null || true
  "$LSR" -u "$app" 2>/dev/null || true
done
# Paths that were deleted but are still registered.
"$LSR" -dump 2>/dev/null | sed -nE 's/^path: +(.*GlassTunes\.app) \(0x[0-9a-f]+\)$/\1/p' | sort -u | while read -r app; do
  [[ "$app" == /Applications/GlassTunes.app ]] && continue
  pluginkit -r "$app/Contents/PlugIns/GlassTunesWidgets.appex" 2>/dev/null || true
  "$LSR" -u "$app" 2>/dev/null || true
done
