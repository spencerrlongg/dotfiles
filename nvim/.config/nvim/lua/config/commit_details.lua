-- Commit details pane and steady scrolling for diffview's file-history panel
-- (<leader>gU, <leader>gR, and <leader>gH for a single file).
--
-- The panel is a short split along the bottom of the tab. Drawing an expanded
-- commit's message inside it let a long body fill the whole panel, and <tab> left
-- every commit it passed through expanded, so the file rows moved by a different
-- amount on each step. Here the panel holds only commit and file rows, and the full
-- message of the commit under the cursor goes in a pane split off the panel's right
-- side, the way PhpStorm's Log tab keeps Commit Details next to Changed Files. The
-- diff windows above keep their full width and height.
--
-- When <tab>/<s-tab> or selecting a file moves into another commit, every other
-- commit folds and the new one is scrolled to the top of the panel (accordion), so
-- each step moves the list the same way.
--
-- The pane is opened right after the panel window and closed right before it.
-- diffview closes and reopens the panel whenever it rebuilds the diff layout, and a
-- pane left open then would take the panel's place across the bottom of the tab.
-- `i` in the panel hides or shows it.
--
-- Like review_marks.lua, this wraps FileHistoryPanel methods and reads the line
-- ranges the renderer records on each component (render.lua); diffview.nvim is
-- pinned in lazy-lock.json, so those internals only move when the lock file does.

local M = {}

local NS = vim.api.nvim_create_namespace("commit_details")

-- Share of the panel's width the pane takes, kept within these column bounds.
local WIDTH_RATIO = 0.45
local MIN_WIDTH, MAX_WIDTH = 40, 100

-- commit hash -> message body (may be ""). Hashes are immutable, so an entry is good
-- for the rest of the session.
local bodies = {}

---@class CommitDetailsState
---@field win? integer   the details pane
---@field buf? integer
---@field hash? string   the commit the pane shows
---@field hidden? boolean turned off with `i`; stays off for this panel
---@field active? table  the LogEntry the accordion last opened

-- FileHistoryPanel -> state. Weak keys, so a closed view's panel can be collected.
---@type table<table, CommitDetailsState>
local panels = setmetatable({}, { __mode = "k" })

local function pstate(panel)
  local s = panels[panel]
  if not s then
    s = {}
    panels[panel] = s
  end
  return s
end

local function win_ok(win)
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function set_hl()
  vim.api.nvim_set_hl(0, "CommitDetailsSubject", { link = "DiffviewFilePanelTitle", default = true })
  vim.api.nvim_set_hl(0, "CommitDetailsMeta", { link = "DiffviewNonText", default = true })
  vim.api.nvim_set_hl(0, "CommitDetailsHash", { link = "DiffviewHash", default = true })
  vim.api.nvim_set_hl(0, "CommitDetailsRef", { link = "DiffviewReference", default = true })
end

---Fetch the bodies of every commit in `hashes` that isn't cached yet, in one git call.
---@param toplevel string
---@param hashes string[]
local function fetch_bodies(toplevel, hashes)
  local missing = {}
  for _, hash in ipairs(hashes) do
    if bodies[hash] == nil then
      table.insert(missing, hash)
    end
  end
  if #missing == 0 then
    return
  end

  -- \30 ends each commit, \31 separates the hash from its body. vim.system keeps the
  -- raw bytes (vim.fn.system would rewrite control characters).
  local cmd = { "git", "-C", toplevel, "show", "-s", "--format=%H%x1f%b%x1e" }
  vim.list_extend(cmd, missing)
  local result = vim.system(cmd, { text = true }):wait()

  if result.code == 0 then
    for record in (result.stdout or ""):gmatch("([^\30]+)\30") do
      local hash, body = record:match("^%s*(%x+)\31(.*)$")
      if hash then
        bodies[hash] = vim.trim(body)
      end
    end
  end

  -- A hash git couldn't show still gets an entry, so it isn't retried on every redraw.
  for _, hash in ipairs(missing) do
    if bodies[hash] == nil then
      bodies[hash] = ""
    end
  end
end

---Winbar values are statusline format strings, where `%` starts an item.
local function esc(text)
  return (text:gsub("%%", "%%%%"))
end

local function winbar(commit)
  local sep = " %#CommitDetailsMeta#·%* "
  local bar = "  %#CommitDetailsHash#" .. commit.hash:sub(1, 8) .. "%*"
  if commit.author and commit.author ~= "" then
    bar = bar .. sep .. esc(commit.author)
  end
  if commit.rel_date and commit.rel_date ~= "" then
    bar = bar .. sep .. "%#CommitDetailsMeta#" .. esc(commit.rel_date) .. "%*"
  end
  if commit.ref_names then
    bar = bar .. "  %#CommitDetailsRef#(" .. esc(commit.ref_names) .. ")%*"
  end
  return bar
end

---The commit to show: the one under the panel's cursor, so moving over commit rows
---with j/k previews their messages, else the commit of the file in the diff.
local function shown_commit(panel)
  local ok, entry = pcall(panel.get_log_entry_at_cursor, panel)
  if not (ok and entry) then
    entry = panel.cur_item and panel.cur_item[1]
  end
  return entry and entry.commit
end

---@param panel table FileHistoryPanel
local function update(panel)
  local s = panels[panel]
  if not (s and win_ok(s.win)) then
    return
  end

  local commit = shown_commit(panel)
  if not commit or commit.hash == s.hash then
    return
  end
  s.hash = commit.hash

  local toplevel = panel.adapter and panel.adapter.ctx and panel.adapter.ctx.toplevel
  if toplevel then
    fetch_bodies(toplevel, { commit.hash })
  end

  local lines = { commit.subject or "" }
  local body = bodies[commit.hash] or ""
  if body ~= "" then
    table.insert(lines, "")
    vim.list_extend(lines, vim.split(body, "\n", { plain = true }))
  end

  local buf = s.buf
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  vim.api.nvim_buf_set_extmark(buf, NS, 0, 0, { end_col = #lines[1], hl_group = "CommitDetailsSubject" })

  vim.wo[s.win].winbar = winbar(commit)
  -- A new commit starts at its subject, not wherever the last message was scrolled to.
  vim.api.nvim_win_set_cursor(s.win, { 1, 0 })
end

local function set_local(win, opts)
  for name, value in pairs(opts) do
    vim.api.nvim_set_option_value(name, value, { win = win, scope = "local" })
  end
end

---@param total integer columns shared by the panel and the pane
local function pane_width(total)
  return math.max(MIN_WIDTH, math.min(MAX_WIDTH, math.floor(total * WIDTH_RATIO)))
end

---@param panel table FileHistoryPanel
local function open_pane(panel)
  local s = pstate(panel)
  -- Only beside a panel laid out as a row (bottom or top). A sidebar panel has no
  -- width to give away.
  if s.hidden or win_ok(s.win) or not win_ok(panel.winid) or panel.state.form ~= "row" then
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "DiffviewCommitDetails"

  local win = vim.api.nvim_open_win(buf, false, {
    split = "right",
    win = panel.winid,
    width = pane_width(vim.api.nvim_win_get_width(panel.winid)),
  })

  -- The split copies the panel's window options; keep its colors, drop the rest.
  set_local(win, {
    winhl = vim.wo[panel.winid].winhl,
    wrap = true,
    linebreak = true,
    breakindent = true,
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    statuscolumn = "",
    cursorline = false,
    list = false,
    spell = false,
    colorcolumn = "",
    winfixwidth = true,
    winfixheight = true,
  })

  vim.keymap.set("n", "i", M.toggle, { buffer = buf, desc = "Hide commit details" })

  s.win, s.buf, s.hash = win, buf, nil
  update(panel)
end

---@param panel table FileHistoryPanel
local function close_pane(panel)
  local s = panels[panel]
  if s and win_ok(s.win) then
    pcall(vim.api.nvim_win_close, s.win, true)
  end
  if s then
    s.win, s.buf, s.hash = nil, nil, nil
  end
end

---Fold every commit but the one `item` belongs to when the selection moves into a
---different commit. Returns that commit's LogEntry, or nil for a single-file
---history (no folds) or a commit row.
---@param panel table FileHistoryPanel
local function accordion(panel, item)
  -- A LogEntry carries `files`; a FileEntry doesn't.
  if panel.single_file or not item or item.files then
    return nil
  end
  local entry = panel:find_entry(item)
  if not entry then
    return nil
  end

  local s = pstate(panel)
  if s.active ~= entry then
    s.active = entry
    local changed = entry.folded
    for _, other in ipairs(panel.entries) do
      if other ~= entry and not other.folded then
        other.folded = true
        changed = true
      end
    end
    entry.folded = false
    if changed then
      panel:render()
      panel:redraw()
    end
  end
  return entry
end

---Scroll so `entry`'s commit row is the first line in the panel, even near the end of
---the list where that leaves empty rows below it: the current commit and its files
---then sit in the same place on every step.
---@param panel table FileHistoryPanel
local function pin(panel, entry)
  local win = panel.winid
  local entries = panel.components and panel.components.log and panel.components.log.entries
  if not win_ok(win) or not entries then
    return
  end

  for _, struct in ipairs(entries) do
    if struct.comp.context == entry then
      local height = vim.api.nvim_win_get_height(win)
      local cursor = vim.api.nvim_win_get_cursor(win)[1]
      local topline = struct.commit.comp.lstart + 1
      -- A commit with more files than the panel has rows: keep the cursor in view.
      if cursor >= topline + height then
        topline = cursor - height + 1
      end
      vim.api.nvim_win_call(win, function()
        vim.fn.winrestview({ topline = topline })
      end)
      return
    end
  end
end

local function current_panel()
  local ok, lib = pcall(require, "diffview.lib")
  local view = ok and lib.get_current_view()
  local panel = view and view.panel
  if panel and panel.get_log_entry_at_cursor then
    return panel
  end
end

---Hide or show the details pane for the current view's panel.
function M.toggle()
  local panel = current_panel()
  if not panel then
    return
  end
  local s = pstate(panel)
  s.hidden = not s.hidden
  if s.hidden then
    close_pane(panel)
  else
    open_pane(panel)
  end
end

local installed = false

function M.setup()
  if installed then
    return
  end
  installed = true

  set_hl()
  vim.api.nvim_create_autocmd("ColorScheme", { callback = set_hl })

  local ok, mod = pcall(require, "diffview.scene.views.file_history.file_history_panel")
  if not ok then
    return
  end

  local FileHistoryPanel = mod.FileHistoryPanel
  -- These resolve to the Panel base class through the class metatable.
  local open, close, redraw = FileHistoryPanel.open, FileHistoryPanel.close, FileHistoryPanel.redraw
  local highlight_item = FileHistoryPanel.highlight_item

  FileHistoryPanel.open = function(self, ...)
    open(self, ...)
    if win_ok(self.winid) then
      -- pin() puts the commit row on the first line with the cursor one row below
      -- it; any scrolloff would scroll it back down.
      vim.wo[self.winid].scrolloff = 0
    end
    pcall(open_pane, self)
    -- A reopened panel (<leader>b, or diffview rebuilding the layout) starts at the
    -- top of the list.
    local s = panels[self]
    if s and s.active and not self.single_file then
      pcall(pin, self, s.active)
    end
  end

  FileHistoryPanel.close = function(self, ...)
    pcall(close_pane, self)
    return close(self, ...)
  end

  FileHistoryPanel.redraw = function(self, ...)
    redraw(self, ...)
    pcall(update, self)
  end

  -- Called with the file <tab>/<s-tab> or a selection moves to, before diffview
  -- loads its diff.
  FileHistoryPanel.highlight_item = function(self, item, ...)
    local ok_fold, entry = pcall(accordion, self, item)
    highlight_item(self, item, ...)
    if ok_fold and entry then
      pcall(pin, self, entry)
    end
    pcall(update, self)
  end

  vim.api.nvim_create_autocmd("FileType", {
    pattern = "DiffviewFileHistory",
    callback = function(ev)
      vim.keymap.set("n", "i", M.toggle, { buffer = ev.buf, desc = "Toggle commit details" })
      vim.api.nvim_create_autocmd("CursorMoved", {
        buffer = ev.buf,
        callback = function()
          local panel = current_panel()
          if panel and panel.bufid == ev.buf then
            pcall(update, panel)
          end
        end,
      })
    end,
  })

  vim.api.nvim_create_autocmd("VimResized", {
    callback = function()
      for panel, s in pairs(panels) do
        if win_ok(s.win) and win_ok(panel.winid) then
          -- +1 for the separator column between them.
          local total = vim.api.nvim_win_get_width(panel.winid) + vim.api.nvim_win_get_width(s.win) + 1
          vim.api.nvim_win_set_width(s.win, pane_width(total))
        end
      end
    end,
  })
end

return M
