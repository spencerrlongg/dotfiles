#!/bin/bash
# Per-Mac macOS settings that don't travel with iCloud or the dotfiles links, copied
# from mbp. bootstrap.sh's macos step runs this; it's safe to run again.
#
#   Menu bar: icons packed closer together, and Control Center's battery icon hidden
#   (AlDente shows the battery). These are -currentHost settings, stored per Mac.
#   Ctrl+arrows: macOS's Mission Control / App windows / switch-Space shortcuts are off,
#   so Ctrl+arrows reach the terminal. nvim (LazyVim) resizes windows with them, and on
#   a Rex client the keys have to get through to the host's nvim.
set -euo pipefail

# Menu bar spacing (macOS default is about 16 for both).
defaults -currentHost write -globalDomain NSStatusItemSpacing -int 8
defaults -currentHost write -globalDomain NSStatusItemSelectionPadding -int 8
# Control Center battery: 8 = don't show in the menu bar.
defaults -currentHost write com.apple.controlcenter Battery -int 8

# Symbolic hotkeys, by id: 32 / 34 Mission Control (ctrl+up), 33 / 35 App windows
# (ctrl+down), 79 / 81 Move a Space left / right (ctrl+left / ctrl+right), 80 / 82 the
# same with shift. All off.
# XML, not the `{ enabled = 0; }` form: that one stores "0" as a string, which macOS
# reads as on (it left Ctrl+up/down opening Mission Control on the Air).
hotkey_off() {
  local value=""
  [ -n "${2:-}" ] && value="<key>value</key><dict><key>parameters</key><array><integer>65535</integer><integer>$2</integer><integer>$3</integer></array><key>type</key><string>standard</string></dict>"
  defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add "$1" \
    "<dict><key>enabled</key><false/>$value</dict>"
}
for id in 32 33 34 35; do hotkey_off "$id"; done
hotkey_off 79 123 8650752 # ctrl+left
hotkey_off 80 123 8781824 # ctrl+shift+left
hotkey_off 81 124 8650752 # ctrl+right
hotkey_off 82 124 8781824 # ctrl+shift+right
# Makes the keyboard shortcut changes take effect without logging out.
/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true

# No killall ControlCenter/SystemUIServer: on macOS 27 the restarted menu bar draws at
# the default spacing while the saved value stays 8, so it looked reset to 16. Menu bar
# spacing and the battery icon apply at the next login.
echo "macOS defaults applied (menu bar changes take effect at the next login)"
