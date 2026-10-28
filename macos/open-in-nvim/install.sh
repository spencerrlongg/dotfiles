#!/bin/bash
# Builds ~/Applications/Open in Nvim.app from main.applescript and makes it the
# default app for the extensions listed in `extensions` (needs duti: brew install duti).
#   install.sh [dest-dir]   build into dest-dir instead (no duti, for testing)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
dest=${1:-$HOME/Applications}
app="$dest/Open in Nvim.app"
id=com.spencerlong.open-in-nvim
pb=/usr/libexec/PlistBuddy

mkdir -p "$dest"
rm -rf "$app"
osacompile -o "$app" "$here/main.applescript"

plist="$app/Contents/Info.plist"
$pb -c "Add :CFBundleIdentifier string $id" "$plist" 2>/dev/null || $pb -c "Set :CFBundleIdentifier $id" "$plist"
# No Dock icon while it runs
$pb -c "Add :LSUIElement bool true" "$plist"
# Accept any file, as an editor, so it can be the default app for any type
$pb -c "Set :CFBundleDocumentTypes:0:CFBundleTypeRole Editor" "$plist"
$pb -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes array" "$plist"
$pb -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:0 string public.data" "$plist"
$pb -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:1 string public.content" "$plist"
# Editing Info.plist breaks osacompile's signature; re-sign ad hoc
codesign --force --sign - "$app"

[ $# -gt 0 ] && exit 0

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
grep -v '^#' "$here/extensions" | while read -r ext; do
  [ -n "$ext" ] && duti -s "$id" ".$ext" all
done
echo "Open in Nvim.app installed and set as the default for $(grep -vc '^#' "$here/extensions") extensions"
