-- Commit message bodies and separators for diffview's file-history panel (<leader>gU).
--
-- Diffview only reads each commit's subject from git log (and truncates it to 72
-- bytes), so an expanded commit shows nothing of its body. This draws the full
-- message as virtual lines between an expanded commit row and its file rows, and a
-- faint rule above every commit after the first so neighbouring commits read as
-- separate blocks.
--
-- Virtual lines don't change the buffer's real lines, so diffview's cursor-to-item
-- lookup and the review marks (review_marks.lua) keep working untouched. Like
-- review_marks.lua, this wraps the panel's redraw and reads the line ranges the
-- renderer records on each component; diffview.nvim is pinned in lazy-lock.json, so
-- those internals only move when the lock file does.

local M = {}

local NS = vim.api.nvim_create_namespace("commit_details")

-- diffview's render.lua cuts subjects longer than this many bytes.
local SUBJECT_MAX = 72

-- File rows are prefixed with this tree guide (render.lua), so the body lines reuse
-- it to stay inside the same tree.
local GUIDE = "│   "

-- commit hash -> message body (may be ""). Hashes are immutable, so an entry is good
-- for the rest of the session.
local bodies = {}

local function set_hl()
  vim.api.nvim_set_hl(0, "CommitDetailsBody", { link = "DiffviewFilePanelFileName", default = true })
  vim.api.nvim_set_hl(0, "CommitDetailsGuide", { link = "DiffviewNonText", default = true })
  vim.api.nvim_set_hl(0, "CommitDetailsSeparator", { link = "DiffviewNonText", default = true })
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

---Word-wrap one line to `width` display cells. Words longer than the width (URLs)
---are left whole; Neovim cuts the virtual line at the window edge.
---@return string[]
local function wrap(line, width)
  if vim.fn.strdisplaywidth(line) <= width then
    return { line }
  end

  local out, cur = {}, ""
  for word in line:gmatch("%S+") do
    if cur == "" then
      cur = word
    elseif vim.fn.strdisplaywidth(cur .. " " .. word) <= width then
      cur = cur .. " " .. word
    else
      table.insert(out, cur)
      cur = word
    end
  end
  if cur ~= "" then
    table.insert(out, cur)
  end
  return out
end

---The virtual lines for an expanded commit: the full subject when diffview cut it
---short, then the body, then an empty guide row before the file rows.
---@return table[]|nil
local function message_lines(commit, width)
  local text = {}
  local body = bodies[commit.hash] or ""
  if #(commit.subject or "") > SUBJECT_MAX then
    table.insert(text, commit.subject)
    if body ~= "" then
      table.insert(text, "")
    end
  end
  if body ~= "" then
    vim.list_extend(text, vim.split(body, "\n", { plain = true }))
  end
  if #text == 0 then
    return nil
  end

  local blank = { { vim.trim(GUIDE), "CommitDetailsGuide" } }
  local text_width = math.max(width - vim.fn.strdisplaywidth(GUIDE), 20)
  local lines = {}
  for _, line in ipairs(text) do
    if vim.trim(line) == "" then
      table.insert(lines, blank)
    else
      for _, piece in ipairs(wrap(line, text_width)) do
        table.insert(lines, { { GUIDE, "CommitDetailsGuide" }, { piece, "CommitDetailsBody" } })
      end
    end
  end
  table.insert(lines, blank)
  return lines
end

---@param panel table FileHistoryPanel
local function decorate(panel)
  local buf, win = panel.bufid, panel.winid
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)

  local toplevel = panel.adapter and panel.adapter.ctx and panel.adapter.ctx.toplevel
  local entries = panel.components and panel.components.log and panel.components.log.entries
  if not toplevel or not entries or not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  local info = vim.fn.getwininfo(win)[1]
  local width = vim.api.nvim_win_get_width(win) - (info and info.textoff or 0)
  local separator = { { { string.rep("─", width), "CommitDetailsSeparator" } } }

  -- Collect the expanded commits first so their bodies come from one git call.
  local expanded = {}
  for _, struct in ipairs(entries) do
    local entry = struct.comp.context
    if entry and entry.commit and not entry.single_file and not entry.folded then
      table.insert(expanded, entry.commit.hash)
    end
  end
  fetch_bodies(toplevel, expanded)

  local line_count = vim.api.nvim_buf_line_count(buf)
  local first = true
  for _, struct in ipairs(entries) do
    local entry = struct.comp.context
    local row = struct.commit.comp.lstart
    -- The panel caps how many entries it renders while the log is still streaming in;
    -- the rest have no rows yet.
    if entry and entry.commit and row >= 0 and row < line_count then
      if not first then
        vim.api.nvim_buf_set_extmark(buf, NS, row, 0, {
          virt_lines = separator,
          virt_lines_above = true,
        })
      end
      first = false

      if not entry.single_file and not entry.folded then
        local lines = message_lines(entry.commit, width)
        if lines then
          vim.api.nvim_buf_set_extmark(buf, NS, row, 0, { virt_lines = lines })
        end
      end
    end
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
  local redraw = FileHistoryPanel.redraw

  FileHistoryPanel.redraw = function(self, ...)
    redraw(self, ...)
    pcall(decorate, self)
  end

  -- The separators and wrapped bodies are sized to the panel's width, which diffview
  -- doesn't redraw for.
  vim.api.nvim_create_autocmd("WinResized", {
    callback = function()
      for _, win in ipairs(vim.v.event.windows or {}) do
        local buf = vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win)
        if buf and vim.bo[buf].filetype == "DiffviewFileHistory" then
          local view = require("diffview.lib").get_current_view()
          if view and view.panel and view.panel.bufid == buf then
            pcall(decorate, view.panel)
          end
        end
      end
    end,
  })
end

return M
