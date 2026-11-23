-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua

local map = vim.keymap.set

-- Save with Ctrl+S (IDE-style)
map({ "i", "x", "n", "s" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save File" })

-- Save without formatting (Ctrl+Shift+S)
map({ "i", "x", "n", "s" }, "<C-S-s>", "<cmd>noautocmd w<cr><esc>", { desc = "Save File (no format)" })

-- Diffview: open/close git diff panel (like Local Changes in PHPStorm)
map("n", "<leader>gD", "<cmd>DiffviewOpen<cr>", { desc = "Diff View (all changes)" })
map("n", "<leader>gH", "<cmd>DiffviewFileHistory %<cr>", { desc = "File History" })
-- Review the checked-out branch against the branch it came off (usually develop),
-- commit by commit, pushed or not (branch_review.lua). Uncommitted changes are the
-- top row, and commits that aren't pushed yet are marked. `B` in the panel reviews
-- another branch. Feature branches push themselves after each commit
-- (~/.config/git/auto-push), so this no longer compares against the upstream.
local function current_dir()
  local dir = vim.fn.expand("%:p:h")
  -- Virtual buffers (diffview://, fugitive://, term://, oil://, ...) don't resolve to a
  -- real filesystem path, so `git -C` on them fails for every candidate ref, surfacing a
  -- misleading "no trunk/upstream found" error. Fall back to cwd whenever that happens.
  if dir == "" or vim.fn.isdirectory(dir) == 0 then
    dir = vim.fn.getcwd()
  end
  return dir
end

map("n", "<leader>gU", function()
  require("config.branch_review").open_current(current_dir())
end, { desc = "Review Branch" })
map("n", "<leader>gX", "<cmd>DiffviewClose<cr>", { desc = "Close Diff View" })

-- Review notes: comments on diff lines for Claude's /review-notes skill
-- (review_notes.lua). They work in any diffview diff window.
local function notes(fn, ...)
  local args = { ... }
  return function()
    require("config.review_notes")[fn](unpack(args))
  end
end
pcall(function()
  require("which-key").add({ { "<leader>r", group = "review notes" } })
end)
map("n", "<leader>rc", notes("comment", false), { desc = "Comment on line (reply if noted)" })
map("x", "<leader>rc", notes("comment", true), { desc = "Comment on selection" })
map("n", "<leader>rv", notes("view"), { desc = "View note thread" })
map("n", "<leader>re", notes("edit"), { desc = "Edit my last message" })
map("n", "<leader>rr", notes("toggle_resolved"), { desc = "Resolve / reopen note" })
map("n", "<leader>rd", notes("delete"), { desc = "Delete note" })
map("n", "<leader>rl", notes("list"), { desc = "List review notes" })
map("n", "<leader>rs", notes("send_to_claude"), { desc = "Send notes to Claude (/review-notes)" })

-- Navigate buffers with Ctrl+Tab / Ctrl+Shift+Tab (IDE-style tab switching)
map("n", "<C-Tab>", "<cmd>bnext<cr>", { desc = "Next Buffer" })
map("n", "<C-S-Tab>", "<cmd>bprevious<cr>", { desc = "Prev Buffer" })

-- Close buffer with Ctrl+W (like closing a tab in IDEs)
map("n", "<C-w>q", "<cmd>bd<cr>", { desc = "Close Buffer" })

-- Symbols outline: override to auto-focus the picker input
map("n", "<leader>cs", function()
  Snacks.picker.lsp_symbols({ focus = "input" })
end, { desc = "Symbols" })

-- Cheat sheet: floating popup with custom + common keymaps
map("n", "<leader>?", function()
  local win = Snacks.win({
    file = vim.fn.stdpath("config") .. "/CHEATSHEET.md",
    width = 0.6,
    height = 0.7,
    border = "rounded",
    title = " Cheat Sheet ",
    title_pos = "center",
    ft = "markdown",
    wo = { wrap = false, number = false, relativenumber = false },
    keys = {
      q = "close",
      ["<Esc>"] = "close",
    },
  })
  -- markdownlint flags the table formatting; hide diagnostics for this buffer only
  vim.diagnostic.enable(false, { bufnr = win.buf })
end, { desc = "Cheat Sheet" })
