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

local PANEL_TITLE = "Local Commit Diffs"

-- Diffview's file-history panel is deliberately an unlisted buffer (so it doesn't
-- clutter bufferline), which means it never shows up as a tab there. Label the panel
-- window itself with a winbar instead, so gt/gT back into this tab is unambiguous.
-- `on_refresh`, when given, is mapped to `r` in the panel.
local function label_diffview_history_tab(title, on_refresh)
  vim.schedule(function()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "DiffviewFileHistory" then
        vim.wo[win].winbar = "  " .. title
        if on_refresh then
          vim.keymap.set("n", "r", on_refresh, { buffer = buf, desc = "Refresh unpushed commits" })
        end
      end
    end
  end)
end

local SPINNER = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

-- Animates a spinner after the panel's winbar title while a refresh runs. Returns a
-- function that stops it and puts the plain title back.
local function start_spinner(winid, title)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return function() end
  end

  local timer = vim.uv.new_timer()
  local frame = 0

  local function stop()
    if timer then
      timer:stop()
      timer:close()
      timer = nil
    end
    if vim.api.nvim_win_is_valid(winid) then
      vim.wo[winid].winbar = "  " .. title
    end
  end

  timer:start(
    0,
    80,
    vim.schedule_wrap(function()
      if not timer then
        return
      end
      if not vim.api.nvim_win_is_valid(winid) then
        stop()
        return
      end
      frame = frame % #SPINNER + 1
      vim.wo[winid].winbar = ("  %s  %%#DiagnosticInfo#%s Refreshing…%%*"):format(title, SPINNER[frame])
    end)
  )

  return stop
end

-- The file to show once the new entries are in: the same commit + path if that
-- commit survived (a new commit on top leaves older hashes alone), else the newest
-- commit touching the same path (an amend or rebase rewrote the hash), else the
-- first file in the list.
local function pick_file(entries, hash, path)
  local by_path
  for _, entry in ipairs(entries) do
    for _, file in ipairs(entry.files) do
      if file.path == path then
        if entry.commit.hash == hash then
          return file
        end
        by_path = by_path or file
      end
    end
  end
  return by_path or (entries[1] and entries[1].files[1])
end

-- Rebuilds the panel's commit list for `rev_range` without closing the tab.
-- Diffview's own refresh (`panel:update_entries`) empties the panel and jumps to the
-- first file before the new log streams in. This collects the new entries separately
-- and swaps them in only after git log finishes, so the old panel and diff stay on
-- screen (with a spinner in the panel winbar) until then. Uses diffview internals,
-- which only change when lazy-lock.json does (same as review_marks.lua).
-- `on_done(err)` is not called if the tab is closed while git log runs.
local function reload_in_place(view, rev_range, on_done)
  local async = require("diffview.async")
  local JobStatus = require("diffview.vcs.utils").JobStatus
  local panel = view.panel

  panel.log_options.single_file.rev_range = rev_range
  panel.log_options.multi_file.rev_range = rev_range

  local stop = start_spinner(panel.winid, PANEL_TITLE)

  async.void(function()
    local stream = panel.adapter:file_history({
      log_opt = panel.log_options,
      layout_opt = { default_layout = view.get_default_layout() },
    })

    local entries, err = {}, nil
    for _, item in stream:iter() do
      local status, entry, msg = unpack(item, 1, 3)
      if status == JobStatus.ERROR then
        err = msg or "git log failed"
        break
      elseif status == JobStatus.PROGRESS then
        entries[#entries + 1] = entry
      end
    end

    async.await(async.scheduler())
    stop()

    if err or view.closing:check() or panel.shutdown:check() then
      for _, entry in ipairs(entries) do
        entry:destroy()
      end
      if err then
        on_done(err)
      end
      return
    end

    local old = panel.entries
    local cur_entry, cur_file = panel.cur_item[1], panel.cur_item[2]

    -- Commits that were expanded before the refresh stay expanded.
    local expanded = {}
    for _, entry in ipairs(old) do
      if not entry.folded then
        expanded[entry.commit.hash] = true
      end
    end
    for _, entry in ipairs(entries) do
      if expanded[entry.commit.hash] then
        entry.folded = false
      end
    end

    panel.entries = entries
    panel.single_file = entries[1] and entries[1].single_file
    require("diffview.scene.views.file_history.render").clear_cache(panel)
    panel.cur_item = {}
    panel:update_components()

    local target = pick_file(entries, cur_entry and cur_entry.commit.hash, cur_file and cur_file.path)
    if target then
      async.await(view:set_file(target))
    else
      view:file_safeguard()
    end

    -- A diff that's still on screen reuses the old File's buffer (diffview looks
    -- buffers up by name), and destroying the old File would delete the keymaps the
    -- new one relies on. Unhook those buffers from the old Files before releasing them.
    local live = {}
    for _, file in ipairs(view.cur_entry and view.cur_entry.layout:files() or {}) do
      if file.bufnr then
        live[file.bufnr] = true
      end
    end
    for _, entry in ipairs(old) do
      for _, file_entry in ipairs(entry.files) do
        for _, file in ipairs(file_entry.layout:files()) do
          if file.bufnr and live[file.bufnr] then
            file.bufnr = nil
          end
        end
      end
      entry:destroy()
    end

    panel:sync()
    on_done(nil)
  end)()
end

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
  reload_in_place(view, range, function(err)
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
  end)
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

  label_diffview_history_tab(PANEL_TITLE, function()
    refresh_unpushed(state)
  end)
end

map("n", "<leader>gU", function()
  open_unpushed(current_dir())
end, { desc = "Unpushed Commits" })
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
