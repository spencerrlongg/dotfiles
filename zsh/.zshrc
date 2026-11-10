# Interactive zsh. The pieces live in ~/.config/zsh/:
#   path.zsh     PATH, Java/Android, nvm (loaded on first use), bun
#   tools.zsh    atuin, completions
#   aliases.zsh  aliases

# --- oh-my-zsh ---
export ZSH=$HOME/.oh-my-zsh
ZSH_THEME=robbyrussell
plugins=(git)
source $ZSH/oh-my-zsh.sh

# --- Written by apps ---
# Herd and LM Studio look for their own lines in this file and add them again
# when they're missing, so they stay here instead of in path.zsh. Herd adds a
# line for each PHP version it installs.

# Herd injected PHP binary.
export PATH="/Users/spencer/Library/Application Support/Herd/bin/":$PATH
# Herd injected PHP 7.4 configuration.
export HERD_PHP_74_INI_SCAN_DIR="/Users/spencer/Library/Application Support/Herd/config/php/74/"
# Herd injected PHP 8.0 configuration.
export HERD_PHP_80_INI_SCAN_DIR="/Users/spencer/Library/Application Support/Herd/config/php/80/"
# Herd injected PHP 8.1 configuration.
export HERD_PHP_81_INI_SCAN_DIR="/Users/spencer/Library/Application Support/Herd/config/php/81/"
# Herd injected PHP 8.2 configuration.
export HERD_PHP_82_INI_SCAN_DIR="/Users/spencer/Library/Application Support/Herd/config/php/82/"
# Herd injected PHP 8.3 configuration.
export HERD_PHP_83_INI_SCAN_DIR="/Users/spencer/Library/Application Support/Herd/config/php/83/"
# Herd injected PHP 8.4 configuration.
export HERD_PHP_84_INI_SCAN_DIR="/Users/spencer/Library/Application Support/Herd/config/php/84/"
# Herd injected PHP 8.5 configuration.
export HERD_PHP_85_INI_SCAN_DIR="/Users/spencer/Library/Application Support/Herd/config/php/85/"
# Herd injected PHP 8.6 configuration.
export HERD_PHP_86_INI_SCAN_DIR="/Users/spencer/Library/Application Support/Herd/config/php/86"

# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/spencer/.lmstudio/bin"
# End of LM Studio CLI section

# --- Our config ---
for f in path tools aliases; do
  [[ -r $HOME/.config/zsh/$f.zsh ]] && source $HOME/.config/zsh/$f.zsh
done
unset f

# Remote logins (ssh, and mosh, which keeps SSH_CONNECTION) go straight into tmux:
# the most recent session, or the full layout from tmux-start when no server is
# running. Detaching drops back to this shell.
if [[ -o interactive && -n $SSH_CONNECTION && -z $TMUX && -z $CLAUDECODE ]] && command -v tmux >/dev/null; then
  if tmux has-session 2>/dev/null; then
    tmux attach
  else
    tmux-start
  fi
fi

# Great Wave + system info on new shells (~/.config/fastfetch). Skipped inside
# Claude Code and Neovim terminals, and when the window is too small to fit it.
if [[ -o interactive && -z $CLAUDECODE && -z $NVIM ]] && (( COLUMNS >= 80 && LINES >= 20 )) && command -v fastfetch >/dev/null; then
  fastfetch
fi
