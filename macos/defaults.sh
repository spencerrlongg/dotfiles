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

# Symbolic hotkeys, by id: 32 Mission Control (ctrl+up), 33 App windows (ctrl+down),
# 34 Show Desktop, 79 / 81 Move a Space left / right (ctrl+left / ctrl+right).
hotkey_off() { defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add "$1" "$2"; }
hotkey_off 32 '{ enabled = 0; }'
hotkey_off 33 '{ enabled = 0; }'
hotkey_off 34 '{ enabled = 0; }'
hotkey_off 79 '{ enabled = 0; value = { parameters = (65535, 123, 8650752); type = standard; }; }'
hotkey_off 81 '{ enabled = 0; value = { parameters = (65535, 124, 8650752); type = standard; }; }'
# Makes the keyboard shortcut changes take effect without logging out.
/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true

# No killall ControlCenter/SystemUIServer: on macOS 27 the restarted menu bar draws at
# the default spacing while the saved value stays 8, so it looked reset to 16. Menu bar
# spacing and the battery icon apply at the next login.
echo "macOS defaults applied (menu bar changes take effect at the next login)"
