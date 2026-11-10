# Shell integrations. Sourced after oh-my-zsh so their key bindings win.

# atuin: shell history (Ctrl+R, up arrow)
[[ -r $HOME/.atuin/bin/env ]] && . $HOME/.atuin/bin/env
(( $+commands[atuin] )) && eval "$(atuin init zsh)"

# bun completions
[[ -s $HOME/.bun/_bun ]] && source $HOME/.bun/_bun
