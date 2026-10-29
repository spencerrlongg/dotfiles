# dotfiles

Config for Spencer's Mac: zsh, tmux, Neovim, Ghostty, AeroSpace, and the `~/.local/bin`
scripts (tmux screensaver, status animation, agent notifications, session launcher).
Managed with [GNU Stow](https://www.gnu.org/software/stow/). Claude Code and Codex
config live in a separate private repo.

## New Mac

```sh
git clone https://github.com/spencerrlongg/dotfiles ~/dotfiles
~/dotfiles/bootstrap.sh
```

`bootstrap.sh` runs these steps in order; name some to run only those
(`bootstrap.sh link tmux`), and any step can be re-run:

| Step | Does |
|---|---|
| `xcode` | Xcode command line tools |
| `brew` | Homebrew |
| `repos` | signs in to `gh`, clones the private repo, turns on the secret-scan hook in both |
| `bundle` | everything in `Brewfile`, including Mac App Store apps |
| `tools` | oh-my-zsh, nvm + Node + global npm packages, atuin, bun, Claude Code |
| `link` | stows every package from both repos; files in the way go to `~/.dotfiles-backup/<time>/` |
| `tmux` | TPM and the plugins in `.tmux.conf` |
| `macos` | Open in Nvim.app + file associations, LaunchAgents |
| `checklist` | prints what still needs doing by hand (sign-ins, permissions) |

`tools` runs before `link` on purpose: those installers append to `~/.zshrc` and
friends, and `link` then sets their versions aside for the repo's, which already
have the lines they need.

| Package | What it links |
|---|---|
| `zsh` | `.zshrc`, `.zprofile`, `.bashrc`, `.profile`, `.bash-preexec.sh`, atuin config |
| `git` | `.gitconfig`, `.huskyrc`, `~/.config/git/` (global ignore, secret-scan hooks) |
| `tmux` | `.tmux.conf` |
| `nvim` | `~/.config/nvim/` |
| `ghostty` | `~/.config/ghostty/config` |
| `term` | cava, btop and fastfetch configs |
| `aerospace` | `.aerospace.toml` |
| `bin` | `~/.local/bin` scripts (tmux screensaver, status animation, agent notify, dotfiles-sync, ...) |
| `misc` | jj config, `.yarnrc`, PhpStorm code style |

Not Stow packages:

| Folder | What it is |
|---|---|
| `macos/open-in-nvim/` | Builds `~/Applications/Open in Nvim.app`, a droplet that opens files in nvim in a new tmux window, and makes it the default app for the extensions in `extensions` (`install.sh`, needs `duti`) |
| `macos/LaunchAgents/` | `wifi-ethernet-toggle`: Wi-Fi off while ethernet is connected. `dotfiles-sync`: hourly commit, pull and push of both repos (log in `~/Library/Logs/dotfiles-sync.log`). `install.sh` copies and loads them |
| `blink/` | Kanagawa Dragon theme for Blink Shell on the iPad, with a pure black background. The live copy is in iCloud Drive under `Blink/` |

## Layout

Each top-level package folder mirrors its path under `~`:
`nvim/.config/nvim/` is linked to `~/.config/nvim/`.

## Using it

```sh
git clone <this repo> ~/dotfiles
cd ~/dotfiles
git config core.hooksPath hooks   # secret scan on every commit
stow --no-folding nvim            # link one package into ~
```

Always pass `--no-folding`. Without it, Stow links a whole folder (say
`~/.local/bin`) into the repo when that folder doesn't exist yet, and anything a
tool later writes there lands inside the repo.

Stow skips `.gitignore` files, so `nvim`'s own `.gitignore` stays in the repo only.

## Safety

- `.gitignore` ignores everything at the top level by default. Adding a package
  means adding its `!/<package>/` line, which is the moment to check what's in it.
- The same file also blocks known secret files everywhere (Claude/Codex/gh/ngrok
  credentials, `.ssh/`, the atuin key, Raycast), after the package lines so they win.
- `hooks/pre-commit` runs gitleaks on staged changes and refuses the commit if it
  finds a secret, or if gitleaks isn't installed.
