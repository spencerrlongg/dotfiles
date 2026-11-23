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

lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$lsregister" -f "$app"

# Sets the handler for each argument; prints the ones duti refused.
set_handlers() {
  local ext
  for ext in "$@"; do
    # A line with a dot is a content type (UTI): some types, like Markdown, keep a
    # handler of their own that wins over the extension's (Xcode claims Markdown).
    case "$ext" in
      *.*) duti -s "$id" "$ext" all >/dev/null 2>&1 || echo "$ext" ;;
      *) duti -s "$id" ".$ext" all >/dev/null 2>&1 || echo "$ext" ;;
    esac
  done
}

exts=()
while read -r ext; do [ -n "$ext" ] && exts+=("$ext"); done < <(grep -v '^#' "$here/extensions")
failed=()
while read -r ext; do [ -n "$ext" ] && failed+=("$ext"); done < <(set_handlers "${exts[@]}")

# An extension that no installed app declares gets a dynamic UTI (dyn.…), and
# LaunchServices refuses to set a handler for those (duti error -50). Declare those
# extensions as plain-text types in the app itself, so they get real UTIs, then retry.
if [ ${#failed[@]} -gt 0 ]; then
  $pb -c "Add :UTImportedTypeDeclarations array" "$plist"
  i=0
  for ext in "${failed[@]}"; do
    case "$ext" in *.*) continue ;; esac
    key=":UTImportedTypeDeclarations:$i"
    $pb -c "Add $key dict" \
        -c "Add $key:UTTypeIdentifier string $id.ext.$ext" \
        -c "Add $key:UTTypeDescription string .$ext file" \
        -c "Add $key:UTTypeConformsTo array" \
        -c "Add $key:UTTypeConformsTo:0 string public.plain-text" \
        -c "Add $key:UTTypeTagSpecification dict" \
        -c "Add $key:UTTypeTagSpecification:public.filename-extension array" \
        -c "Add $key:UTTypeTagSpecification:public.filename-extension:0 string $ext" \
        "$plist"
    i=$((i + 1))
  done
  codesign --force --sign - "$app"
  "$lsregister" -f "$app"
  still=()
  while read -r ext; do [ -n "$ext" ] && still+=("$ext"); done < <(set_handlers "${failed[@]}")
  [ ${#failed[@]} -gt ${#still[@]} ] && echo "declared types for: ${failed[*]}"
  failed=("${still[@]+"${still[@]}"}")
fi

echo "Open in Nvim.app installed and set as the default for $((${#exts[@]} - ${#failed[@]})) of ${#exts[@]} extensions"
[ ${#failed[@]} -eq 0 ] || echo "warning: could not set a handler for: ${failed[*]}" >&2
