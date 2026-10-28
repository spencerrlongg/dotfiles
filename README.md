# dotfiles

Config for Spencer's Mac: zsh, tmux, Neovim, Ghostty, the `~/.local/bin` scripts
(screensaver, status animation, agent notifications, session launcher), and the
Claude Code / Codex setup. Managed with [GNU Stow](https://www.gnu.org/software/stow/).

Status: every package below is moved in and stowed on the current Mac. No
`bootstrap.sh` or Brewfile yet; see the plan in Obsidian at
`Personal/Plans/2026-08-13-Dotfiles-Repo-Setup.md`.

| Package | What it links |
|---|---|
| `zsh` | `.zshrc`, `.zprofile`, `.bashrc`, `.profile`, `.bash-preexec.sh`, atuin config |
| `git` | `.gitconfig`, `.huskyrc`, `~/.config/git/` (global ignore, secret-scan hooks) |
| `tmux` | `.tmux.conf` |
| `nvim` | `~/.config/nvim/` |
| `ghostty` | `~/.config/ghostty/config` |
| `term` | cava, btop and fastfetch configs |
| `aerospace` | `.aerospace.toml` |
| `bin` | `~/.local/bin` scripts (tmux screensaver, status animation, agent notify, ...) |
| `claude` | `~/.claude` config: CLAUDE.md, settings, statusline, hooks, own skills |
| `codex` | `~/.codex` config: config.toml, hooks.json, AGENTS.md |
| `memory` | Claude memory folders and `~/.codex/user-memory` (see below) |
| `misc` | jj config, `.yarnrc`, PhpStorm code style |

## Layout

Each top-level folder is a Stow package whose contents mirror their path under `~`:
`nvim/.config/nvim/` is linked to `~/.config/nvim/`.

## Using it

```sh
git clone <this repo> ~/dotfiles
cd ~/dotfiles
git config core.hooksPath hooks   # secret scan on every commit
stow --no-folding nvim            # link one package into ~
```

Always pass `--no-folding`. Without it, Stow links a whole folder (say
`~/.local/bin` or `~/.claude`) into the repo when that folder doesn't exist yet,
and anything a tool later writes there lands inside the repo.

The one exception is `memory`, stowed with plain `stow memory`: each memory folder
is linked whole, so memories Claude and Codex write later land in the repo. Create
`~/.claude/projects/<project>/` for each project and `~/.codex/` first, or Stow
links a folder one level higher and session transcripts end up in the repo.

Stow skips `.gitignore` files, so `nvim`'s own `.gitignore` stays in the repo only.

## Safety

- `.gitignore` ignores everything at the top level by default. Adding a package
  means adding its `!/<package>/` line, which is the moment to check what's in it.
- The same file also blocks known secret files everywhere (Claude/Codex/gh/ngrok
  credentials, `.ssh/`, the atuin key, Raycast), after the package lines so they win.
- `hooks/pre-commit` runs gitleaks on staged changes and refuses the commit if it
  finds a secret, or if gitleaks isn't installed.
