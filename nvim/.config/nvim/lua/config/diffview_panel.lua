-- Shared helpers for the commit panels built on diffview's file history:
-- <leader>gU (unpushed commits, keymaps.lua) and <leader>gR (branch review,
-- branch_review.lua). Labels the panel window, animates a spinner while it reloads,
-- and swaps in a new commit range without closing the tab.
--
-- reload_in_place uses diffview internals; diffview.nvim is pinned in
-- lazy-lock.json, so those only move when the lock file does (same as
-- review_marks.lua). diffview modules are required inside the functions, so
-- requiring this file doesn't load diffview.

local M = {}

---@alias PanelTitle string|fun():string  a plain title, or a function returning the whole winbar

---@param title PanelTitle
local function winbar_text(title)
  if type(title) == "function" then
    return title()
  end
  return "  " .. title
end
M.winbar_text = winbar_text

-- Diffview's file-history panel is deliberately an unlisted buffer (so it doesn't
-- clutter bufferline), which means it never shows up as a tab there. Label the panel
-- window itself with a winbar instead, so gt/gT back into this tab is unambiguous.
-- `keys` are mapped in the panel buffer, as { lhs = { fn, desc } }. `on_found` gets
-- the panel's buffer and window once they exist.
---@param title PanelTitle
---@param keys? table<string, { [1]: function, [2]: string }>
---@param on_found? fun(buf: integer, win: integer)
function M.label(title, keys, on_found)
  vim.schedule(function()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "DiffviewFileHistory" then
        vim.wo[win].winbar = winbar_text(title)
        for lhs, spec in pairs(keys or {}) do
          vim.keymap.set("n", lhs, spec[1], { buffer = buf, desc = spec[2] })
        end
        if on_found then
          on_found(buf, win)
        end
      end
    end
  end)
end

local SPINNER = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

-- Animates a spinner after the panel's winbar title while a refresh runs. Returns a
-- function that stops it and puts the plain title back.
---@param title PanelTitle
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
      vim.wo[winid].winbar = winbar_text(title)
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
      vim.wo[winid].winbar = winbar_text(title) .. ("  %%#DiagnosticInfo#%s Refreshing…%%*"):format(SPINNER[frame])
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
-- screen (with a spinner in the panel winbar) until then.
-- `opts.title` is the panel's title (see PanelTitle). `opts.filter(entry)`, when
-- given, drops the commits it returns false for.
-- `on_done(err)` is not called if the tab is closed while git log runs.
---@param opts { title: PanelTitle, filter?: fun(entry: table): boolean }
function M.reload_in_place(view, rev_range, on_done, opts)
  local async = require("diffview.async")
  local JobStatus = require("diffview.vcs.utils").JobStatus
  local panel = view.panel

  panel.log_options.single_file.rev_range = rev_range
  panel.log_options.multi_file.rev_range = rev_range

  local stop = start_spinner(panel.winid, opts.title)

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

    if opts.filter then
      local kept = {}
      for _, entry in ipairs(entries) do
        if opts.filter(entry) then
          kept[#kept + 1] = entry
        else
          entry:destroy()
        end
      end
      entries = kept
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

return M
