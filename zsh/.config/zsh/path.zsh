# PATH for interactive shells.
typeset -U path   # drop duplicates, keeping the first (frontmost) copy

# Homebrew in front of the system tools (git, curl). .zshenv adds it, but in login
# shells /etc/zprofile (path_helper) then moves it behind /usr/bin. Herd's bin,
# added by the block in .zshrc, stays ahead of Homebrew: Herd's mysql and psql win.
path=(${(M)path:#*/Herd/bin*} /opt/homebrew/bin /opt/homebrew/sbin $path)

# Java and Android, for React Native builds
export JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home
export ANDROID_HOME=$HOME/Library/Android/sdk
path+=($ANDROID_HOME/emulator $ANDROID_HOME/platform-tools)

# Node: the nvm default version's bin goes on PATH directly. Sourcing nvm.sh at
# startup took about a second, so nvm itself loads the first time you run it.
export NVM_DIR=$HOME/.nvm
() {
  local want=${$(<$NVM_DIR/alias/default 2>/dev/null)#v}
  [[ $want == (node|stable|'') ]] && want=
  local versions=($NVM_DIR/versions/node/v${want}*(N/n))
  (( $#versions )) && path=($versions[-1]/bin $path)
}
nvm() {
  unfunction nvm
  source $NVM_DIR/nvm.sh
  [[ -s $NVM_DIR/bash_completion ]] && source $NVM_DIR/bash_completion
  nvm "$@"
}

# bun
export BUN_INSTALL=$HOME/.bun
path=($BUN_INSTALL/bin $path)

# Scripts from the dotfiles bin package, ahead of everything
path=($HOME/.local/bin $path)
