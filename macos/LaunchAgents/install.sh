#!/bin/bash
# Copies each LaunchAgent plist here into ~/Library/LaunchAgents and (re)loads it.
# Copied, not stowed: launchd doesn't reliably load symlinked plists at login.
# The plists name /Users/spencer; that is replaced with this account's $HOME.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p ~/Library/LaunchAgents
for src in "$here"/*.plist; do
  name=$(basename "$src")
  label=${name%.plist}
  dst=~/Library/LaunchAgents/$name
  sed "s|/Users/spencer|$HOME|g" "$src" > "$dst"
  plutil -lint -s "$dst"
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$dst"
  echo "loaded $label"
done
