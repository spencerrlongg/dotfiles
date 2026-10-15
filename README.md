# dotfiles

Config for Spencer's Mac: zsh, tmux, Neovim, Ghostty, the `~/.local/bin` scripts
(screensaver, status animation, agent notifications, session launcher), and the
Claude Code / Codex setup. Managed with [GNU Stow](https://www.gnu.org/software/stow/).

Status: empty skeleton. Packages move in one at a time; see the plan in Obsidian at
`Personal/Plans/2026-08-13-Dotfiles-Repo-Setup.md`.

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

## Safety

- `.gitignore` ignores everything at the top level by default. Adding a package
  means adding its `!/<package>/` line, which is the moment to check what's in it.
- The same file also blocks known secret files everywhere (Claude/Codex/gh/ngrok
  credentials, `.ssh/`, the atuin key, Raycast), after the package lines so they win.
- `hooks/pre-commit` runs gitleaks on staged changes and refuses the commit if it
  finds a secret, or if gitleaks isn't installed.
