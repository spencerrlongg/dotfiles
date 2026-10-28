#!/bin/bash
# Sets up a new Mac from this repo and dotfiles-private.
#
#   git clone https://github.com/spencerrlongg/dotfiles ~/dotfiles
#   ~/dotfiles/bootstrap.sh            # every step, in order
#   ~/dotfiles/bootstrap.sh link tmux  # only the named steps
#
# Every step can be re-run. Steps: xcode brew repos bundle tools link tmux macos checklist
set -euo pipefail

DOTFILES=${DOTFILES:-$(cd "$(dirname "$0")" && pwd)}
DOTFILES_PRIVATE=${DOTFILES_PRIVATE:-$HOME/dotfiles-private}
PRIVATE_REPO=spencerrlongg/dotfiles-private
PACKAGES=(zsh git tmux nvim ghostty term aerospace bin misc)
PRIVATE_PACKAGES=(claude codex)   # plus memory, linked separately (see link_memory)
NODE_VERSION=24
NPM_GLOBALS=(@openai/codex corepack)
BACKUP=$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)

say()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mwarning: %s\033[0m\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

step_xcode() {
  say "Xcode command line tools"
  if xcode-select -p >/dev/null 2>&1; then echo "already installed"; return; fi
  xcode-select --install
  read -rp "Finish the install dialog, then press Return. "
}

step_brew() {
  say "Homebrew"
  if ! have brew && [ ! -x /opt/homebrew/bin/brew ]; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  eval "$(/opt/homebrew/bin/brew shellenv)"
  brew --version | head -1
}

step_repos() {
  say "dotfiles-private (needs gh, signed in)"
  have gh || brew install gh
  gh auth status >/dev/null 2>&1 || gh auth login --git-protocol https --web
  if [ -d "$DOTFILES_PRIVATE/.git" ]; then
    git -C "$DOTFILES_PRIVATE" pull --ff-only
  else
    gh repo clone "$PRIVATE_REPO" "$DOTFILES_PRIVATE"
  fi
  # Secret scan on every commit in both repos
  git -C "$DOTFILES" config core.hooksPath hooks
  git -C "$DOTFILES_PRIVATE" config core.hooksPath hooks
}

step_bundle() {
  say "brew bundle (apps and tools from the Brewfile)"
  echo "Mac App Store apps need you signed in to the App Store app first."
  read -rp "Press Return when signed in (or to skip them failing). "
  # A failed entry (often a mas app) shouldn't stop the rest of the bootstrap
  brew bundle --file "$DOTFILES/Brewfile" || warn "some Brewfile entries failed; rerun: brew bundle --file $DOTFILES/Brewfile"
}

# These installers write to ~/.zshrc, ~/.bashrc and friends. They run before `link`,
# which moves whatever they wrote into the backup folder and links the repo's files
# instead (those already have the lines these tools need).
step_tools() {
  say "oh-my-zsh"
  if [ -d "$HOME/.oh-my-zsh" ]; then echo "already installed"
  else RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  fi

  say "nvm, Node $NODE_VERSION, global npm packages"
  if [ ! -s "$HOME/.nvm/nvm.sh" ]; then
    tag=$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')
    PROFILE=/dev/null bash -c "$(curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${tag:-master}/install.sh")"
  fi
  export NVM_DIR="$HOME/.nvm"
  # nvm's own scripts trip over -e and -u
  set +eu
  . "$NVM_DIR/nvm.sh"
  nvm install "$NODE_VERSION" && nvm alias default "$NODE_VERSION" && npm install -g "${NPM_GLOBALS[@]}"
  local ok=$?
  set -eu
  [ $ok -eq 0 ] || warn "Node setup failed; rerun: $0 tools"

  say "atuin"
  if [ -x "$HOME/.atuin/bin/atuin" ]; then echo "already installed"
  else curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
  fi

  say "bun"
  if [ -x "$HOME/.bun/bin/bun" ]; then echo "already installed"
  else curl -fsSL https://bun.sh/install | bash
  fi

  say "Claude Code"
  if [ -e "$HOME/.local/bin/claude" ]; then echo "already installed"
  else curl -fsSL https://claude.ai/install.sh | bash
  fi
}

# Moves a target that isn't already our link into the backup folder, keeping its path
set_aside() {
  local target=$1 source=$2
  [ -e "$target" ] || [ -L "$target" ] || return 0
  [ "$(readlink -f "$target")" = "$(readlink -f "$source")" ] && return 0
  mkdir -p "$BACKUP/$(dirname "${target#"$HOME"/}")"
  mv "$target" "$BACKUP/${target#"$HOME"/}"
  echo "moved aside: ~/${target#"$HOME"/}"
}

# stow --no-folding: every file is linked on its own, and folders are created as
# real folders, so files tools write there later never land in the repo
link_packages() {
  local repo=$1; shift
  local pkg f
  for pkg in "$@"; do
    while IFS= read -r f; do
      set_aside "$HOME/${f#"$pkg"/}" "$repo/$f"
    done < <(cd "$repo" && find "$pkg" \( -type f -o -type l \) ! -name .DS_Store)
    stow --no-folding -d "$repo" -t "$HOME" "$pkg"
    echo "linked $pkg"
  done
}

# memory is the one package linked with folding: each memory folder becomes a single
# link, so memories written later land in the repo. Its parent folders must exist
# first, or Stow would link ~/.claude/projects (session transcripts and all).
link_memory() {
  local d
  while IFS= read -r d; do
    mkdir -p "$HOME/$(dirname "$d")"
    set_aside "$HOME/$d" "$DOTFILES_PRIVATE/memory/$d"
  done < <(cd "$DOTFILES_PRIVATE/memory" && find . -type d \( -name memory -o -name user-memory \) -prune | sed 's|^\./||')
  stow -d "$DOTFILES_PRIVATE" -t "$HOME" memory
  echo "linked memory"
}

step_link() {
  say "Linking dotfiles"
  have stow || brew install stow
  mkdir -p "$HOME/.config" "$HOME/.local/bin" "$HOME/.claude" "$HOME/.codex"
  link_packages "$DOTFILES" "${PACKAGES[@]}"
  if [ -d "$DOTFILES_PRIVATE" ]; then
    link_packages "$DOTFILES_PRIVATE" "${PRIVATE_PACKAGES[@]}"
    link_memory
  else
    warn "$DOTFILES_PRIVATE not found; run the repos step, then link again"
  fi
  [ -d "$BACKUP" ] && echo "Files that were in the way are in $BACKUP"
  return 0
}

step_tmux() {
  say "tmux plugins (TPM)"
  [ -d "$HOME/.tmux/plugins/tpm" ] || git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  "$HOME/.tmux/plugins/tpm/bin/install_plugins"
}

step_macos() {
  say "Open in Nvim.app and file associations"
  "$DOTFILES/macos/open-in-nvim/install.sh"
  say "LaunchAgents"
  "$DOTFILES/macos/LaunchAgents/install.sh"
}

step_checklist() {
  say "Still to do by hand"
  cat <<'EOF'
  - Sign in: App Store, iCloud, 1Password, Raycast (turn on cloud sync), JetBrains
    (Settings Sync), Slack, Notion, HEY, Discord, Tailscale
  - Claude Code: claude, then /login. Plugins come back from enabledPlugins in settings.json
  - Codex: codex login, then /hooks to trust the hooks again (trust is per hook hash)
  - atuin: atuin login, using the key saved from the old Mac (~/.local/share/atuin/key)
  - Ghostty: System Settings > Privacy & Security > Screen & System Audio Recording >
    System Audio Recording Only: add Ghostty. Quit Ghostty fully, relaunch, restart the
    tmux server. Without it cava never runs.
  - AeroSpace and Thaw: grant Accessibility when asked
  - macOS screen saver delay must stay above tmux lock-after-time (210 s)
  - Herd: open it once (installs PHP, writes its PATH lines to ~/.zshrc, which is a
    link into ~/dotfiles: check git diff there afterwards)
  - Xcode: open once to accept the license and install simulators; Android Studio:
    SDK and emulator images
  - Tailscale: note the new IP for Expo (npx expo start --host <ip>); update the host
    in Blink on the iPad
  - snipe-it-mobile: re-add the stub .git/hooks/pre-commit that runs
    ~/.config/git/secret-scan (its own hooksPath skips the global hooks)
  - Download by hand: Astropad Workbench, CARROT Weather, Festivitas, Hue Sync,
    Mirage Host, SnipeMate, StemRoller, ThreadWatch; Steam games
  - Old Mac: check every repo in ~/dev for uncommitted or unpushed work before wiping
EOF
}

ALL=(xcode brew repos bundle tools link tmux macos checklist)
steps=("$@")
[ ${#steps[@]} -eq 0 ] && steps=("${ALL[@]}")
# Later steps need brew on PATH even when run on their own
[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
for s in "${steps[@]}"; do
  declare -F "step_$s" >/dev/null || { echo "unknown step: $s (steps: ${ALL[*]})" >&2; exit 2; }
  "step_$s"
done
