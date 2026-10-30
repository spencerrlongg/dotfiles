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
-- Commits on the current branch that aren't merged into its upstream/trunk yet.
-- `@{u}` is a "Bad revision" on branches that were never pushed, so fall back to
-- origin/develop|main|master (whichever exists) — the branch this one will actually
-- be merged into. Deliberately NOT `--not --remotes`: that excludes anything reachable
-- from *any* remote branch, so commits inherited from other stacked/interleaved local
-- branches get miscounted as "unpushed" here too.
local function find_base(dir)
  vim.fn.system({ "git", "-C", dir, "rev-parse", "--verify", "--quiet", "@{u}" })
  if vim.v.shell_error == 0 then
    return "@{u}"
  end
  for _, name in ipairs({ "develop", "main", "master" }) do
    local ref = "origin/" .. name
    vim.fn.system({ "git", "-C", dir, "rev-parse", "--verify", "--quiet", ref })
    if vim.v.shell_error == 0 then
      return ref
    end
  end
  return nil
end

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

local function unpushed_revs(dir)
  local base = find_base(dir)
  if base == nil then
    return nil, nil
  end
  local revs = vim.fn.systemlist({ "git", "-C", dir, "rev-list", base .. "..HEAD" })
  if vim.v.shell_error ~= 0 then
    return nil, nil
  end
  return revs, base
end

local panel_ui = require("config.diffview_panel")

local PANEL_TITLE = "Local Commit Diffs"

local function count_label(revs, base)
  return ("%d unpushed commit%s (vs %s)"):format(#revs, #revs == 1 and "" or "s", base)
end

-- The `--range` for the panel, or nil when the oldest unpushed commit is a root
-- commit: it has no parent to build `base..HEAD` from, so the panel shows full history.
local function history_range(dir, revs)
  local oldest = revs[#revs]
  vim.fn.system({ "git", "-C", dir, "rev-parse", "--verify", "--quiet", oldest .. "^" })
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return oldest .. "^..HEAD"
end

-- The --range is fixed when the panel opens, so a new commit, amend, rebase or push
-- leaves it stale. `r` recomputes it from the repo dir the panel was opened for (the
-- diffview buffers aren't real paths, so current_dir() would land on cwd) and reloads
-- the panel in place. When the commit list hasn't changed, the panel is left as is.
-- `state` is { dir, revs, base, busy } for one panel.
local function refresh_unpushed(state)
  if state.busy then
    return
  end

  local revs, base = unpushed_revs(state.dir)
  if revs == nil then
    vim.notify("Not a git repo (or no trunk/upstream found) in: " .. state.dir, vim.log.levels.ERROR)
    return
  end
  if vim.deep_equal(revs, state.revs) then
    vim.notify("No new commits — " .. count_label(revs, base), vim.log.levels.INFO)
    return
  end
  if #revs == 0 then
    vim.cmd("DiffviewClose")
    vim.notify("Updated — Nothing unpushed — current branch matches " .. base, vim.log.levels.INFO)
    return
  end

  local view = require("diffview.lib").get_current_view()
  local panel = view and view.panel
  if not (panel and panel.log_options) or panel.updating then
    return
  end

  local seen = {}
  for _, rev in ipairs(state.revs) do
    seen[rev] = true
  end
  local new = 0
  for _, rev in ipairs(revs) do
    if not seen[rev] then
      new = new + 1
    end
  end
  local msg = "Updated — " .. (new > 0 and ("%d new, "):format(new) or "") .. count_label(revs, base)

  local range = history_range(state.dir, revs)
  state.busy = true
  panel_ui.reload_in_place(view, range, function(err)
    state.busy = false
    if err then
      vim.notify("Refresh failed: " .. err, vim.log.levels.ERROR)
      return
    end
    state.revs, state.base = revs, base
    if range then
      vim.notify(msg, vim.log.levels.INFO)
    else
      vim.notify(msg .. " (from root commit) — showing full history", vim.log.levels.WARN)
    end
  end, { title = PANEL_TITLE })
end

local function open_unpushed(dir)
  local revs, base = unpushed_revs(dir)
  if revs == nil then
    vim.notify("Not a git repo (or no trunk/upstream found) in: " .. dir, vim.log.levels.ERROR)
    return
  end
  if #revs == 0 then
    vim.notify("Nothing unpushed — current branch matches " .. base, vim.log.levels.INFO)
    return
  end

  local state = { dir = dir, revs = revs, base = base }
  local msg = count_label(revs, base)
  local range = history_range(dir, revs)

  if range then
    vim.notify(msg, vim.log.levels.INFO)
    vim.cmd("DiffviewFileHistory --range=" .. range)
  else
    vim.notify(msg .. " (from root commit) — showing full history", vim.log.levels.WARN)
    vim.cmd("DiffviewFileHistory")
  end

  panel_ui.label(PANEL_TITLE, {
    r = {
      function()
        refresh_unpushed(state)
      end,
      "Refresh unpushed commits",
    },
  })
end

map("n", "<leader>gU", function()
  open_unpushed(current_dir())
end, { desc = "Unpushed Commits" })
-- Review a branch commit by commit, like a PR before there is one (branch_review.lua).
map("n", "<leader>gR", function()
  require("config.branch_review").pick(current_dir())
end, { desc = "Branch Review" })
map("n", "<leader>gX", "<cmd>DiffviewClose<cr>", { desc = "Close Diff View" })

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
