# Nvim Cheat Sheet (LazyVim + snacks.nvim)

Press `<leader>?` any time to reopen this. `q` or `<Esc>` closes the popup.

## Fuzzy Find (snacks.picker)

| Key | Action |
|---|---|
| `<leader><space>` | Find files (smart: git files if in a repo) |
| `<leader>ff` | Find files |
| `<leader>fg` | Find git files |
| `<leader>fr` | Recent files |
| `<leader>/` or `<leader>sg` | Live grep (fuzzy search text in project) |
| `<leader>sw` | Search word under cursor |
| `<leader>,` | Switch buffers (fuzzy) |
| `<leader>sk` | Search keymaps |
| `<leader>cs` | Symbols outline (custom: auto-focuses input) |

Inside a picker: type to filter, `<C-j>`/`<C-k>` or arrows to move, `<Enter>` to open,
`<C-x>`/`<C-v>` to open in split.

## Go To Source (LSP)

| Key | Action |
|---|---|
| `gd` | Go to definition — where the thing is defined |
| `gr` | References — every place it's used |
| `gy` | Go to t[y]pe definition — the type of the thing, not the thing |
| `gI` | Go to implementation — concrete impls of an interface/abstract |
| `gD` | Go to declaration (PHP) / go to *source* definition (JS/TS) — see note |
| `K` | Hover docs for the symbol under the cursor |
| `gK` | Signature help (parameters of the call you're inside) |
| `gai` / `gao` | Call hierarchy — c[a]lls [i]ncoming / [o]utgoing |
| `gR` | File references — JS/TS only |

Getting back after a jump:

| Key | Action |
|---|---|
| `<C-o>` | Jump back (where you came from) |
| `<C-i>` | Jump forward again |

`<C-o>` is the one to remember — `gd` then `<C-o>` is the round trip.

When a jump has exactly one result you land on it directly. More than one and
snacks.picker opens a list instead.

These are buffer-local and only exist while a language server is attached to the
file — press them in a buffer with no LSP and nothing happens. `:LspInfo` shows
what's attached.

`gD` differs by language, because the TypeScript server overrides it:

- **PHP** (intelephense) — Goto Declaration. For most PHP code this lands in the
  same place as `gd`.
- **JS/TS/JSX** (vtsls) — Goto *Source* Definition. Skips past the `.d.ts` type
  stub and finds the real implementation. Use this when `gd` drops you in a type
  declaration file instead of actual code.


## Buffers vs Tabpages vs Windows

Three different, independent concepts that often get confused:

- **Buffer** — a file loaded into memory. Every file you've opened is a buffer,
  whether visible or not. The pill row at the top (bufferline) lists your open buffers.
- **Window** — a viewport (split) showing one buffer. A tabpage can have several.
- **Tabpage** — a whole screen layout of windows. Diffview opens its own tabpage.
  The small numbers on the *far right* of the top bar are tabpages, not buffers.

| Key | Action |
|---|---|
| `<C-Tab>` / `]b` / `<S-l>` | Next buffer (three aliases for the same action) |
| `<C-S-Tab>` / `[b` / `<S-h>` | Prev buffer (three aliases for the same action) |
| `<leader>,` | Fuzzy-switch buffers (see Fuzzy Find above) |
| `<C-w>q` | Close current buffer |
| `gt` / `gT` | Next / prev tabpage |
| `<leader><tab>d` or `:tabclose` | Close current tabpage (its buffers stay open) |
| `<leader><tab>o` or `:tabonly` | Close all other tabpages |
| `<leader><tab><tab>` | New tabpage |

Closing a tabpage only closes its windows — the buffers stay loaded and remain in the
bufferline. `:tabclose` refuses on the last tabpage. For a Diffview tab, use
`<leader>gX` instead so Diffview cleans up its own state.

## Git / Diff (Diffview, custom mappings)

| Key | Action |
|---|---|
| `<leader>gD` | Open diff view (all changes) |
| `<leader>gH` | File history for current file |
| `<leader>gU` | Unpushed commits (vs upstream, or trunk if none) + their diffs |
| `<leader>gX` | Close diff view |
| `gf` | Open the actual file (not the diff) from the file panel, in the previous tab |
| `<C-w><C-f>` | Open the actual file in a new split |
| `<C-w>gf` | Open the actual file in a new tab |
| `m` | (in the unpushed panel) Mark the file under the cursor reviewed — on a commit row, all of its files |
| `r` | (in the unpushed panel) Refresh — reloads the commit list in place after a commit, amend, rebase or push; the current diff stays open while it loads |
| `:ReviewMarksClear` | Drop every review mark for the current repo |

Diffview opens in its own tabpage — after `gf`, use `gt`/`gT` (see Buffers vs Tabpages
vs Windows above) to get back to it.

Expanding a commit in the panel shows its full message (body, plus the whole subject
when diffview cut it at 72 characters) between the commit row and its files.

Review marks: `○` unreviewed, `✓` reviewed, with a `2/5` count on the commit row.
Once every file in every commit is marked, a big green checkmark shows in the panel
header and the title reads `✓ all reviewed`.
They persist across restarts and are keyed to file *content*, so amending or rebasing
an unpushed commit keeps them — a mark only clears when the file itself changes.

## Gutter Signs (the column right of the line numbers)

That column holds **one** sign per line, and two unrelated things draw the *same*
right-pointing arrow:

| Sign | Color | Meaning |
|---|---|---|
| `` | gray | Closed fold — lines are hidden here |
| `` | red | Git: line(s) were **deleted** here |
| `` | red | Git: deletion at the very top of the file |
| `▎` | green | Git: line added |
| `▎` | orange | Git: line changed |

Fold beats git when both apply to a line — snacks.statuscolumn's right column is a
priority list, `{ "fold", "git" }`, and only the winner is drawn. Open folds draw
nothing at all (`folds.open = false`).

Telling the two arrows apart without squinting at the color: a **fold** arrow has a
jump in the line numbers right after it (`11` then `31`); a **delete** arrow doesn't,
because nothing is hidden — those lines are gone from the file and only exist in git.

So: `zo` / `za` opens a fold (see Folding below), but a red delete arrow has nothing to
open. Use the gitsigns keys instead.

## Gitsigns — seeing and acting on the red arrows

| Key | Action |
|---|---|
| `]h` / `[h` | Next / prev git hunk |
| `]H` / `[H` | Last / first hunk in the file |
| `<leader>ghp` | **Preview hunk inline** — expands the deleted lines under the cursor |
| `<leader>ghd` | Diff this file against the index (split) |
| `<leader>ghD` | Diff this file against `HEAD~` |
| `<leader>ghr` / `<leader>ghR` | Reset hunk / whole buffer — puts deleted lines back |
| `<leader>ghs` / `<leader>ghS` | Stage hunk / whole buffer |
| `<leader>ghu` | Undo stage hunk |
| `<leader>ghb` / `<leader>ghB` | Blame line (full) / blame whole buffer |
| `ih` | Hunk text object — `vih` selects it, `dih` deletes it |
| `<leader>uG` | Toggle git signs off / on |

`<leader>ghp` is the one to reach for: park the cursor on a red arrow, press it, and the
removed lines appear inline in place. Any cursor movement dismisses them.

For all hunks in all files at once, `<leader>gD` (diff view) is the better tool.

## Statusline — the counts on the bottom right

Reading right to left:

| Item | Meaning |
|---|---|
| `08:27` | Clock |
| `48:94` | Cursor line : column |
| `67%` | Scroll position through the file |
| red `20` | Git: lines **removed** in this buffer |
| orange `4` | Git: lines **modified** |
| green `n` | Git: lines **added** — the whole count is hidden when zero |
| `10` | Pending **plugin updates** — *not* git. `:Lazy`, then `U` to update |

The three git counts are the same gitsigns data as the gutter, totalled for the buffer
against the index. Walk them with `]h`, or open the whole thing with `<leader>gD`.
Nothing is clickable — there is no "open" on the statusline, the counts are a readout.

## Folding (expanding collapsed lines)

| Key | Action |
|---|---|
| `zo` / `zc` | Open / close the fold under the cursor |
| `za` | Toggle the fold under the cursor |
| `zO` / `zC` / `zA` | Same three, recursive — every nested level |
| `zR` / `zM` | Open every fold in the file / close them all |
| `zv` | Open just enough to reveal the cursor line |
| `zj` / `zk` | Jump to the next / previous fold |
| `[z` / `]z` | Jump to the start / end of the current fold |

`zR` is the one to reach for when a file opens more collapsed than expected. Folds come
from treesitter (LazyVim default) — no nvim-ufo installed, so these are the built-in
commands.

In the Diffview panels the same keys are diffview's *own* fold actions, not vim folds,
and there are two extras: `<CR>` / `o` / `l` on a commit row toggles it open, `h` closes
it. On a file row those keys open the diff instead. A collapsed commit draws no `○`/`✓`
review marks, but its row still shows the `2/5` count.

## Window Splits (resizing)

| Key | Action |
|---|---|
| `<C-Up>` / `<C-Down>` | Increase / decrease height by 2 |
| `<C-Left>` / `<C-Right>` | Decrease / increase width by 2 |
| `<C-w>=` | Equalize all split sizes |
| `<C-w>_` | Maximize height of current split |
| `<C-w>\|` | Maximize width of current split |
| `<C-w>o` | Close all other splits (keep only current) |

## Save

| Key | Action |
|---|---|
| `<C-s>` | Save file |
| `<C-S-s>` | Save file without formatting |

## General

| Key | Action |
|---|---|
| `<leader>` (wait) | which-key popup — full live list of every mapping |
| `<leader>?` | This cheat sheet |
