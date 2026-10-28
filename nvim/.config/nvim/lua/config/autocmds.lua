-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Ghostty now runs with background-opacity < 1, so any highlight group with an
-- explicit solid bg (floats, popups, sign column) reads as a blocky opaque
-- rectangle against the transparent terminal. Clearing bg on those groups lets
-- the terminal's own transparency show through instead, so floats blend in.
local transparent_groups = {
  "Normal",
  "NormalFloat",
  "FloatBorder",
  "FloatTitle",
  "SignColumn",
  "Pmenu",
  "NeoTreeNormal",
  "NeoTreeNormalNC",
  "NeoTreeEndOfBuffer",
  "SnacksNormal",
  "SnacksNormalNC",
  "SnacksWinBar",
  "TelescopeNormal",
  "TelescopeBorder",
}

local function make_transparent()
  for _, group in ipairs(transparent_groups) do
    vim.api.nvim_set_hl(0, group, { bg = "none" })
  end

  -- Kanagawa Dragon's default border (#54546D) is too close to the background to read
  -- against a transparent float — give it Dragon's crystalBlue accent so the rounded
  -- border set via 'winborder' actually shows up.
  vim.api.nvim_set_hl(0, "FloatBorder", { fg = "#7E9CD8", bg = "none" })
  vim.api.nvim_set_hl(0, "FloatTitle", { fg = "#7E9CD8", bg = "none", bold = true })

  -- Focused-window cues. The usual approach (kanagawa's dimInactive) darkens the
  -- background of inactive windows, but every bg here is cleared for terminal
  -- transparency, so it would have no effect. Dim the text instead: unfocused
  -- windows drop from dragonWhite to dragonGray3, focused stays full strength.
  vim.api.nvim_set_hl(0, "NormalNC", { fg = "#7a8382", bg = "none" })

  -- Split borders: Dragon sets WinSeparator to dragonBlack0 (#0d0c0c), darker than
  -- the #181616 background, so split edges are invisible. dragonBlack6 reads clearly.
  vim.api.nvim_set_hl(0, "WinSeparator", { fg = "#625e5a", bg = "none" })
end

vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("transparent_bg", { clear = true }),
  callback = make_transparent,
})

make_transparent()

-- Cursorline follows focus. Neovim draws 'cursorline' in every window that sets it,
-- including unfocused ones, so with splits open several rows are highlighted at once
-- and none of them mark where typing will land. Restrict it to the focused window.
-- Floating windows are skipped — pickers and popups manage their own cursorline.
local function set_cursorline(on)
  return function()
    if vim.api.nvim_win_get_config(0).relative ~= "" then
      return
    end
    vim.wo.cursorline = on
  end
end

local focus_group = vim.api.nvim_create_augroup("focused_window_cues", { clear = true })

vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter" }, {
  group = focus_group,
  callback = set_cursorline(true),
})

vim.api.nvim_create_autocmd("WinLeave", {
  group = focus_group,
  callback = set_cursorline(false),
})

-- On diff-highlighted lines the DiffAdd/DiffChange bg wins over CursorLine's bg, so
-- Neovim marks the cursor line with an underline instead. Diff windows highlight only
-- the line number; everywhere else keeps the full CursorLine band.
local function sync_cursorlineopt()
  vim.wo.cursorlineopt = vim.wo.diff and "number" or "both"
end

vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter" }, {
  group = focus_group,
  callback = sync_cursorlineopt,
})

vim.api.nvim_create_autocmd("OptionSet", {
  group = focus_group,
  pattern = "diff",
  callback = sync_cursorlineopt,
})

-- Close every diffview tab before persistence.nvim writes the session. Diffview's
-- buffers are diffview:// URIs backed by in-memory state, so a session that captures
-- them restores tabs full of empty windows. Views are closed the same way
-- :DiffviewClose does it; diffview.lib is only checked if diffview already loaded,
-- so quitting without having opened it does not load the plugin.
vim.api.nvim_create_autocmd("User", {
  pattern = "PersistenceSavePre",
  group = vim.api.nvim_create_augroup("diffview_session_close", { clear = true }),
  callback = function()
    local lib = package.loaded["diffview.lib"]
    if not lib then
      return
    end
    for _, view in ipairs(vim.list_slice(lib.views)) do
      pcall(view.close, view)
      lib.dispose_view(view)
    end
  end,
})
