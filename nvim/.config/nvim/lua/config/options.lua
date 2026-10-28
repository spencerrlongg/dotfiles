-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua

-- Use intelephense as the PHP LSP (LazyVim defaults to phpactor otherwise)
vim.g.lazyvim_php_lsp = "intelephense"

-- Disable format on save
vim.g.autoformat = false

-- Line numbers: absolute (more IDE-like than relative)
vim.opt.relativenumber = false
vim.opt.number = true

-- Indentation: 4 spaces (PHP/web standard)
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true

-- Scrolling: keep context visible
vim.opt.scrolloff = 4
vim.opt.sidescrolloff = 8

-- No line wrap (IDE default)
vim.opt.wrap = false

-- Show trailing whitespace
vim.opt.list = true
vim.opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }

-- Split directions: open right/below like most IDEs
vim.opt.splitright = true
vim.opt.splitbelow = true

-- No swap files (undo history is more reliable; swap files cause E325 errors in diffview)
vim.opt.swapfile = false

-- Always show the tabline, even with a single buffer open
vim.opt.showtabline = 2

-- Always sync yanks to the system clipboard via pbcopy/pbpaste. LazyVim disables this
-- when $SSH_CONNECTION is set, but tmux's global environment here has a stale
-- SSH_CONNECTION baked in from a past remote session, so every pane inherits it even
-- when working locally — silently breaking yy without any error.
vim.opt.clipboard = "unnamedplus"

-- Rounded border on every floating window by default (LSP hover/signature, :checkhealth,
-- :Lazy, blink.cmp menu, which-key, snacks pickers/notifier) — nvim 0.11+ applies this
-- to any float that doesn't hardcode its own border shape, no per-plugin config needed.
vim.o.winborder = "rounded"

-- Spell check (on for markdown/gitcommit/text via LazyVim): check each part of a
-- camelCase word separately, so identifiers like useMemo or useCallback aren't flagged
vim.opt.spelloptions = "camel"
