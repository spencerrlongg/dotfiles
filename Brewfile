# Everything Homebrew installs on a new Mac: `brew bundle --file ~/dotfiles/Brewfile`.
# Built from this Mac on 2026-10-27 (brew bundle dump, plus apps that were installed by
# hand and have a cask). Commented-out lines are installed today but probably not
# wanted again; uncomment to keep.
#
# Not here, installed by bootstrap instead: oh-my-zsh, tmux's TPM, atuin, nvm + Node
# (and the global npm packages), bun, Claude Code. PHP and Composer come with Herd.

tap "nikitabobko/tap", trusted: true   # AeroSpace
tap "anomalyco/tap", trusted: true     # opencode

# --- Shell and terminal --------------------------------------------------------------
brew "tmux"
brew "neovim"
brew "fzf"
brew "fd"
brew "ripgrep"
brew "lazygit"
brew "gh"
brew "jj"
brew "stow"
brew "gitleaks"      # global pre-commit secret scan (~/.config/git/secret-scan)
brew "duti"          # sets Open in Nvim.app as the default for dev file types
brew "mosh"          # iPad (Blink) to Mac over Tailscale
brew "curl"
brew "qrencode"
cask "ghostty"
cask "font-jetbrains-mono-nerd-font"

# tmux showcase, screensaver and status-bar animations
brew "asciiquarium"
brew "astroterm"
brew "btop"
brew "cava"
brew "cbonsai"
brew "cmatrix"
brew "fastfetch"
brew "pipes-sh"
brew "tty-clock"

# --- Development -----------------------------------------------------------------------
brew "mysql", restart_service: :changed   # Snipe-IT
brew "libpq"
brew "freetds"
brew "cocoapods"     # React Native / Expo iOS builds
brew "watchman"
brew "rbenv"
# brew "nginx"       # left over from Valet; Herd runs its own
brew "anomalyco/tap/opencode"
cask "herd"          # PHP, Composer, nginx for Laravel sites
cask "phpstorm"
# cask "jetbrains-toolbox"
cask "android-studio"
cask "zulu@17"       # JDK for Android builds
# cask "expo-orbit"
cask "tableplus"
# cask "charles"
cask "requestly"
cask "ngrok"
cask "gitbutler"
cask "gitify"
cask "tuple"
cask "warp"
cask "lm-studio"
cask "claude"
cask "sublime-text"
# cask "cursor"              # not used since 2024-25
# cask "visual-studio-code"  # not used since 2024-25
# cask "iterm2"              # replaced by Ghostty

# --- Mac utilities ---------------------------------------------------------------------
cask "nikitabobko/tap/aerospace"
cask "thaw@beta"     # menu bar manager; Thaw 3 beta is the macOS 27 build (`thaw` is 26 only)
cask "raycast"
cask "aldente"
# cask "soundsource" not using this rn 
cask "reflector"
cask "grandperspective"
# cask "logi-options+"
cask "focusrite-control"
cask "clamxav"
# cask "private-internet-access"
# cask "jordanbaird-ice"     # replaced by Thaw
# cask "bartender"           # replaced by Thaw

# --- Apps ------------------------------------------------------------------------------
cask "obsidian"
cask "notion"
# cask "hey-desktop"
cask "discord"
cask "zoom"
cask "google-chrome"
cask "firefox"
# cask "inkscape"
cask "copilot-money"
cask "steam"

# --- Mac App Store (needs `mas` and an App Store sign-in) -----------------------------
brew "mas"
mas "Xcode", id: 497799835
mas "Tailscale", id: 1475387142
mas "Slack", id: 803453959
mas "Xdebug Key", id: 1441712067
mas "Refined GitHub", id: 1519867270
mas "Userscripts", id: 1463298887
mas "Vimkey", id: 1585682577
mas "Kagi for Safari", id: 1622835804
mas "Dato", id: 1470584107
mas "Hush", id: 1544743900
mas "Squirrel", id: 1669664068
mas "Vidimote", id: 1585702412
mas "Pages", id: 409201541
mas "Numbers", id: 409203825
mas "Keynote", id: 409183694
mas "GarageBand", id: 682658836
mas "Logic Pro", id: 634148309
mas "Minesweeper", id: 1475921958
mas "Snake.io+", id: 6443553808
mas "ZenPinballParty", id: 1536783591

# Installed by hand today, no cask or App Store ID found; download these yourself:
# Astropad Workbench, CARROT Weather, Festivitas, Hue Sync, Mirage Host, SnipeMate,
# StemRoller, ThreadWatch, Cities Skylines and Factorio (Steam).
