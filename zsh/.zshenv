# zsh reads this file for every shell, including the non-interactive one sshd
# starts for `ssh host <command>`. That shell skips .zprofile and .zshrc, so
# its PATH is only /usr/bin:/bin:/usr/sbin:/sbin. Mosh connects this way to
# start mosh-server, which lives in Homebrew.
if [[ -d /opt/homebrew/bin && ":$PATH:" != *:/opt/homebrew/bin:* ]]; then
  export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
fi
