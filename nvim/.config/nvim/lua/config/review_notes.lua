-- Review notes: comments on lines of a diff in diffview (<leader>gU, <leader>gR,
-- <leader>gH, <leader>gD), kept outside the code for Claude to work through with the
-- /review-notes skill (~/.claude/skills/review-notes).
--
-- A note anchors to one side of a diff: the revision that side shows (a commit hash,
-- or WORKING / STAGED), the file path and a line range. It keeps a copy of the
-- commented lines, so it still makes sense after a rebase moves or rewrites them, and
-- a thread of messages from you and from Claude. `status` says whose turn it is:
-- open (Claude's), replied (yours: Claude answered or asked something), resolved.
--
-- Notes live in <git common dir>/review-notes.json: per repo, shared by its
-- worktrees, never committed. Claude edits the same file, so it's re-read whenever
-- its mtime changes (focus, entering a diff window, CursorHold) and written
-- atomically (temp file + rename) as indented JSON with a fixed key order, which
-- keeps Claude's edits small. A file that doesn't parse is left alone: no writes
-- until it's fixed.
--
-- Diff windows are aligned line for line. Virtual lines under a commented line would
-- push that side out of step with the other, so a note shows as signs down its range
-- plus the latest message after its last line; <leader>rv opens the whole thread.
--
-- Keymaps are set in keymaps.lua and work without diffview loaded. setup() runs from
-- diffview's config and hooks its buffer events and the file-history panel (a count
-- on each file row), the same way review_marks.lua does.

local M = {}

local api = vim.api

local NS = api.nvim_create_namespace("review_notes")
local NS_PANEL = api.nvim_create_namespace("review_notes_panel")
local FILE_NAME = "review-notes.json"
local MAX_EXCERPT = 60

-- Nerd Font codicons, as bytes so editors that strip private-use characters can't
-- blank them: comment (U+EA6B), comment-discussion (U+EAC7), check (U+EAB2).
local ICONS = { open = "\238\169\171", replied = "\238\171\135", resolved = "\238\170\178" }
local HL = { open = "ReviewNoteOpen", replied = "ReviewNoteReplied", resolved = "ReviewNoteResolved" }
-- The file-history panel keeps a comment icon for resolved notes (green, from HL),
-- since its rows already carry review_marks.lua's reviewed checkmarks.
local PANEL_ICONS = { open = ICONS.open, replied = ICONS.replied, resolved = ICONS.open }

---An attribute (fg/bg) of a highlight group after following links, or nil.
local function hl_attr(name, attr)
  local ok, hl = pcall(api.nvim_get_hl, 0, { name = name, link = false })
  return ok and hl[attr] or nil
end

---`alpha` of color `a` over color `b`, both 0xRRGGBB.
local function blend(a, b, alpha)
  local out = 0
  for _, shift in ipairs({ 16, 8, 0 }) do
    local ca = bit.band(bit.rshift(a, shift), 0xff)
    local cb = bit.band(bit.rshift(b, shift), 0xff)
    out = out + bit.lshift(math.floor(ca * alpha + cb * (1 - alpha) + 0.5), shift)
  end
  return out
end

local function set_hl()
  api.nvim_set_hl(0, "ReviewNoteOpen", { link = "DiagnosticInfo", default = true })
  api.nvim_set_hl(0, "ReviewNoteReplied", { link = "DiagnosticWarn", default = true })
  api.nvim_set_hl(0, "ReviewNoteResolved", { link = "DiagnosticOk", default = true })
  api.nvim_set_hl(0, "ReviewNoteText", { link = "Comment", default = true })

  -- Message headers in a thread: the speaker's name in their accent color over a
  -- band of that color mixed into the float's background. Recomputed on every
  -- ColorScheme, since the mix depends on the theme.
  local bg = hl_attr("SnacksNormal", "bg") or hl_attr("NormalFloat", "bg") or hl_attr("Normal", "bg")
  for who, sources in pairs({ You = { "DiagnosticInfo" }, Claude = { "Constant", "DiagnosticWarn" } }) do
    local accent
    for _, source in ipairs(sources) do
      accent = accent or hl_attr(source, "fg")
    end
    if accent and bg then
      api.nvim_set_hl(0, "ReviewNote" .. who, { fg = accent, bold = true })
      api.nvim_set_hl(0, "ReviewNote" .. who .. "Band", { bg = blend(accent, bg, 0.24) })
    else
      api.nvim_set_hl(0, "ReviewNote" .. who, { link = sources[1] })
      api.nvim_set_hl(0, "ReviewNote" .. who .. "Band", { link = "CursorLine" })
    end
  end
  api.nvim_set_hl(0, "ReviewNoteTime", { link = "Comment", default = true })
end

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Review notes" })
end

---------------------------------------------------------------------------
-- Storage
---------------------------------------------------------------------------

---@class ReviewNoteMessage
---@field from "you"|"claude"
---@field body string
---@field at string ISO 8601, UTC

---@class ReviewNote
---@field id integer
---@field status "open"|"replied"|"resolved"
---@field path string repo-relative
---@field start integer 1-based, inclusive
---@field end integer
---@field side "old"|"new"
---@field rev string commit hash, "WORKING" or "STAGED": what that side of the diff shows
---@field commit? string the commit under review (file-history views)
---@field subject? string that commit's subject
---@field excerpt string[]
---@field thread ReviewNoteMessage[]

---@class ReviewNoteStore
---@field path string
---@field mtime? integer
---@field data? { version: integer, notes: ReviewNote[] }
---@field broken? boolean the file exists but didn't parse

---@type table<string, ReviewNoteStore> toplevel -> store
local stores = {}

local function now()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function mtime(path)
  local st = vim.uv.fs_stat(path)
  return st and (st.mtime.sec * 1000000000 + st.mtime.nsec) or nil
end

---@return ReviewNoteStore|nil store, boolean changed true when the notes were (re)read
local function load(toplevel)
  local s = stores[toplevel]
  if not s then
    local out = vim.fn.systemlist({ "git", "-C", toplevel, "rev-parse", "--path-format=absolute", "--git-common-dir" })
    if vim.v.shell_error ~= 0 or not out[1] then
      return nil, false
    end
    s = { path = out[1] .. "/" .. FILE_NAME }
    stores[toplevel] = s
  end

  local m = mtime(s.path)
  if s.data and m == s.mtime then
    return s, false
  end

  local data, broken = { version = 1, notes = {} }, false
  if m then
    local ok, lines = pcall(vim.fn.readfile, s.path)
    local decoded_ok, decoded = false, nil
    if ok then
      decoded_ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
    end
    if decoded_ok and type(decoded) == "table" and type(decoded.notes) == "table" then
      data = decoded
    else
      broken = true
    end
  end

  if broken and not s.broken then
    notify(s.path .. " doesn't parse; notes are read-only until it's fixed", vim.log.levels.ERROR)
  end
  s.data, s.mtime, s.broken = data, m, broken
  return s, true
end

-- Keys in this order first, the rest alphabetically after them.
local KEY_ORDER = {}
for i, key in ipairs({
  "version",
  "notes",
  "id",
  "status",
  "path",
  "start",
  "end",
  "side",
  "rev",
  "commit",
  "subject",
  "excerpt",
  "thread",
  "from",
  "body",
  "at",
}) do
  KEY_ORDER[key] = i
end

local function key_less(a, b)
  local ia, ib = KEY_ORDER[a] or math.huge, KEY_ORDER[b] or math.huge
  if ia ~= ib then
    return ia < ib
  end
  return a < b
end

---JSON with 2-space indents. vim.json.encode writes "/" as "\/", which is valid but
---noisy in paths; every "\/" in its output is that escape, so it's undone here.
local function encode(value, indent)
  indent = indent or ""
  if type(value) ~= "table" then
    return (vim.json.encode(value):gsub("\\/", "/"))
  end
  local inner = indent .. "  "
  local parts = {}
  -- An empty table can only be `notes` or `thread` here, both lists.
  if vim.islist(value) or next(value) == nil then
    if #value == 0 then
      return "[]"
    end
    for _, item in ipairs(value) do
      table.insert(parts, inner .. encode(item, inner))
    end
    return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
  end
  local keys = vim.tbl_keys(value)
  table.sort(keys, key_less)
  for _, key in ipairs(keys) do
    table.insert(parts, inner .. encode(key) .. ": " .. encode(value[key], inner))
  end
  return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

local refresh_all

---Apply `fn` to the freshest copy of the notes and write them back.
---@param fn fun(data: { notes: ReviewNote[] }): boolean? return false to skip the write
local function mutate(toplevel, fn)
  local s = load(toplevel)
  if not s then
    notify("Not in a git repo: " .. toplevel, vim.log.levels.ERROR)
    return false
  end
  if s.broken then
    notify(s.path .. " doesn't parse; fix or delete it first", vim.log.levels.ERROR)
    return false
  end
  if fn(s.data) == false then
    return false
  end

  local tmp = s.path .. ".tmp"
  local fd = io.open(tmp, "w")
  if not fd then
    notify("Can't write " .. tmp, vim.log.levels.ERROR)
    return false
  end
  fd:write(encode(s.data), "\n")
  fd:close()
  local ok, err = os.rename(tmp, s.path)
  if not ok then
    notify("Can't write " .. s.path .. ": " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  s.mtime = mtime(s.path)
  refresh_all()
  return true
end

---------------------------------------------------------------------------
-- Diff windows
---------------------------------------------------------------------------

local function current_view()
  if not package.loaded["diffview"] then
    return nil
  end
  local ok, lib = pcall(require, "diffview.lib")
  return ok and lib.get_current_view() or nil
end

local function view_toplevel(view)
  return view and view.adapter and view.adapter.ctx and view.adapter.ctx.toplevel
end

---What a diff side shows, as stored in a note's `rev`.
local function rev_id(file)
  local rev = file and file.rev
  if not rev or file.nulled then
    return nil
  end
  local RevType = require("diffview.vcs.rev").RevType
  if rev.type == RevType.COMMIT then
    return rev.commit
  elseif rev.type == RevType.LOCAL then
    return "WORKING"
  elseif rev.type == RevType.STAGE then
    return "STAGED"
  end
end

---@class ReviewTarget
---@field view table
---@field file table diffview File
---@field toplevel string
---@field rev string
---@field side "old"|"new"
---@field commit? string
---@field subject? string

---The diff side in the current window, or nil when the cursor isn't in one.
---@return ReviewTarget|nil
local function target(win)
  local view = current_view()
  local layout = view and view.cur_layout
  if not layout then
    return nil
  end
  win = win or api.nvim_get_current_win()
  for _, w in ipairs(layout.windows) do
    if w.id == win and w.file then
      local rev = rev_id(w.file)
      local toplevel = view_toplevel(view)
      if not rev or not toplevel then
        return nil
      end
      local entry = view.panel and view.panel.cur_item and view.panel.cur_item[1]
      local commit = entry and entry.commit
      return {
        view = view,
        file = w.file,
        toplevel = toplevel,
        rev = rev,
        side = w.file.symbol == "a" and "old" or "new",
        commit = commit and commit.hash or nil,
        subject = commit and commit.subject or nil,
      }
    end
  end
end

---@return ReviewNote[]
local function notes_on(toplevel, path, rev)
  local s = load(toplevel)
  local out = {}
  for _, note in ipairs(s and s.data.notes or {}) do
    if note.path == path and note.rev == rev then
      table.insert(out, note)
    end
  end
  return out
end

---The note whose range covers `line` (the narrowest, when they overlap).
---@param t ReviewTarget
---@return ReviewNote|nil
local function note_at(t, line)
  local best
  for _, note in ipairs(notes_on(t.toplevel, t.file.path, t.rev)) do
    if note.start <= line and line <= note["end"] then
      if not best or (note["end"] - note.start) < (best["end"] - best.start) then
        best = note
      end
    end
  end
  return best
end

local function first_line(text)
  return (text or ""):match("^[^\n]*") or ""
end

local function truncate(text, width)
  if vim.fn.strdisplaywidth(text) <= width then
    return text
  end
  return vim.fn.strcharpart(text, 0, width - 1) .. "…"
end

local function latest(note)
  local thread = note.thread or {}
  return thread[#thread]
end

---Signs down each note's range and its latest message after the last line.
local function decorate_buf(bufnr, toplevel, path, rev)
  if not api.nvim_buf_is_valid(bufnr) then
    return
  end
  api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  local count = api.nvim_buf_line_count(bufnr)

  for _, note in ipairs(notes_on(toplevel, path, rev)) do
    local status = HL[note.status] and note.status or "open"
    local hl = HL[status]
    -- A working-tree file can have shrunk since the note was made.
    local first = math.min(note.start, count)
    local last = math.max(first, math.min(note["end"], count))
    for line = first, last do
      local sign = line == first and ICONS[status] or (line == last and "╰" or "│")
      api.nvim_buf_set_extmark(bufnr, NS, line - 1, 0, { sign_text = sign, sign_hl_group = hl, priority = 20 })
    end

    local msg = latest(note)
    local text = msg and first_line(msg.body) or ""
    if msg and msg.from == "claude" then
      text = "Claude: " .. text
    end
    local chunks = { { "  #" .. note.id .. " ", hl } }
    table.insert(chunks, { truncate(text, 80), "ReviewNoteText" })
    if #(note.thread or {}) > 1 then
      table.insert(chunks, { (" (%d)"):format(#note.thread), "ReviewNoteText" })
    end
    api.nvim_buf_set_extmark(bufnr, NS, last - 1, 0, {
      virt_text = chunks,
      virt_text_pos = "eol",
      hl_mode = "combine",
      priority = 20,
    })
  end
end

local function decorate_view(view)
  local layout = view and view.cur_layout
  local toplevel = view_toplevel(view)
  if not layout or not toplevel then
    return
  end
  for _, w in ipairs(layout.windows) do
    local rev = rev_id(w.file)
    if rev and w.file.bufnr then
      pcall(decorate_buf, w.file.bufnr, toplevel, w.file.path, rev)
    end
  end
end

---------------------------------------------------------------------------
-- File-history panel
---------------------------------------------------------------------------

-- Which status a file row shows when its notes differ: the one that needs you first.
local STATUS_RANK = { replied = 1, open = 2, resolved = 3 }

---Number of notes on each file of each commit: "<commit>:<path>" -> { n, status }.
local function panel_counts(toplevel)
  local s = load(toplevel)
  local counts = {}
  for _, note in ipairs(s and s.data.notes or {}) do
    local key = (note.commit or note.rev) .. ":" .. note.path
    local c = counts[key] or { n = 0 }
    c.n = c.n + 1
    if not c.status or (STATUS_RANK[note.status] or 9) < (STATUS_RANK[c.status] or 9) then
      c.status = note.status
    end
    counts[key] = c
  end
  return counts
end

local function decorate_panel(panel)
  local buf = panel.bufid
  if not buf or not api.nvim_buf_is_valid(buf) then
    return
  end
  api.nvim_buf_clear_namespace(buf, NS_PANEL, 0, -1)

  local toplevel = panel.adapter and panel.adapter.ctx and panel.adapter.ctx.toplevel
  local entries = panel.components and panel.components.log and panel.components.log.entries
  if not toplevel or not entries then
    return
  end

  local counts = panel_counts(toplevel)
  if next(counts) == nil then
    return
  end
  local line_count = api.nvim_buf_line_count(buf)

  local function mark(row, c)
    if row >= 0 and row < line_count then
      local status = HL[c.status] and c.status or "open"
      api.nvim_buf_set_extmark(buf, NS_PANEL, row, 0, {
        virt_text = { { PANEL_ICONS[status] .. " " .. c.n, HL[status] } },
        virt_text_pos = "eol",
        hl_mode = "combine",
        priority = 90,
      })
    end
  end

  for _, struct in ipairs(entries) do
    local entry = struct.comp.context
    local hash = entry and entry.commit and entry.commit.hash
    if hash then
      if entry.single_file then
        local c = entry.files[1] and counts[hash .. ":" .. entry.files[1].path]
        if c then
          mark(struct.commit.comp.lstart, c)
        end
      else
        local files = struct.files.comp
        for i, file in ipairs(entry.files) do
          local c = counts[hash .. ":" .. file.path]
          local row = files.lstart + i - 1
          if c and files.lstart >= 0 and row < files.lend then
            mark(row, c)
          end
        end
      end
    end
  end
end

---Redraw every open diffview's notes. Called after each write and whenever the
---file changed underneath (Claude replied).
refresh_all = function()
  if not package.loaded["diffview"] then
    return
  end
  local ok, lib = pcall(require, "diffview.lib")
  if not ok then
    return
  end
  for _, view in ipairs(lib.views or {}) do
    decorate_view(view)
    if view.panel and view.panel.components and view.panel.components.log then
      pcall(decorate_panel, view.panel)
    end
  end
end

---Pick up edits Claude made to the notes file.
local function check_for_changes()
  local toplevel = view_toplevel(current_view())
  if toplevel then
    local _, changed = load(toplevel)
    if changed then
      refresh_all()
    end
  end
end

---------------------------------------------------------------------------
-- Editing
---------------------------------------------------------------------------

---A small markdown float for writing a message. <C-s> saves, <C-g> saves and sends
---the repo's open notes to Claude (M.send_to_claude), q cancels.
---@param toplevel string the repo the note belongs to
---@param on_save fun(text: string)
---@param after? fun() runs once the float has closed, saved or not
local function editor(title, lines, toplevel, on_save, after)
  local empty = #lines == 0 or (#lines == 1 and lines[1] == "")
  local function save(self, send)
    local text = vim.trim(table.concat(api.nvim_buf_get_lines(self.buf, 0, -1, false), "\n"))
    vim.cmd.stopinsert()
    self:close()
    if text ~= "" then
      on_save(text)
      if send then
        M.send_to_claude(toplevel)
      end
    end
  end
  Snacks.win({
    title = " " .. title .. " ",
    footer = " <C-s> save · <C-g> save & send to Claude · q cancel ",
    width = 0.5,
    min_width = 60,
    height = 0.3,
    min_height = 8,
    border = "rounded",
    enter = true,
    ft = "markdown",
    text = empty and { "" } or lines,
    bo = { buftype = "nofile", bufhidden = "wipe", swapfile = false },
    wo = { wrap = true, linebreak = true, spell = true },
    on_close = function()
      if after then
        vim.schedule(after)
      end
    end,
    keys = {
      q = "close",
      ["<C-s>"] = { save, mode = { "n", "i" }, desc = "Save" },
      ["<C-g>"] = {
        function(self)
          save(self, true)
        end,
        mode = { "n", "i" },
        desc = "Save and send to Claude",
      },
    },
  })
  if empty then
    vim.cmd.startinsert()
  end
end

local function range_label(note)
  local range = note.start == note["end"] and tostring(note.start) or (note.start .. "-" .. note["end"])
  return note.path .. ":" .. range
end

---The cursor line, or the lines of the visual selection that was just made.
local function selected_lines(visual)
  if visual then
    -- `'<`/`'>` are only set once visual mode is left.
    vim.cmd([[execute "normal! \<Esc>"]])
    local a, b = vim.fn.line("'<"), vim.fn.line("'>")
    return math.min(a, b), math.max(a, b)
  end
  local line = vim.fn.line(".")
  return line, line
end

local function not_in_diff()
  notify("Put the cursor in a diffview diff (<leader>gU, gR, gH or gD) first", vim.log.levels.WARN)
end

---New note on the cursor line or selection; a reply when a note already covers the
---cursor line (normal mode).
---@param visual? boolean
function M.comment(visual)
  local t = target()
  if not t then
    return not_in_diff()
  end
  local first, last = selected_lines(visual)

  local existing = not visual and note_at(t, first)
  if existing then
    return M.reply(existing, t)
  end

  local excerpt = api.nvim_buf_get_lines(0, first - 1, math.min(last, first + MAX_EXCERPT - 1), false)
  local label = range_label({ path = t.file.path, start = first, ["end"] = last })
  editor("Comment · " .. label, {}, t.toplevel, function(text)
    mutate(t.toplevel, function(data)
      local id = 0
      for _, note in ipairs(data.notes) do
        id = math.max(id, note.id or 0)
      end
      table.insert(data.notes, {
        id = id + 1,
        status = "open",
        path = t.file.path,
        start = first,
        ["end"] = last,
        side = t.side,
        rev = t.rev,
        commit = t.commit,
        subject = t.subject,
        excerpt = excerpt,
        thread = { { from = "you", body = text, at = now() } },
      })
    end)
  end)
end

---Find a note by id in freshly loaded data.
local function find(data, id)
  for i, note in ipairs(data.notes) do
    if note.id == id then
      return note, i
    end
  end
end

---@param note ReviewNote
---@param t ReviewTarget|{toplevel: string}
---@param after? fun() runs once the editor has closed, saved or not
function M.reply(note, t, after)
  editor(("Reply · #%d %s"):format(note.id, range_label(note)), {}, t.toplevel, function(text)
    mutate(t.toplevel, function(data)
      local fresh = find(data, note.id)
      if not fresh then
        notify("Note #" .. note.id .. " is gone", vim.log.levels.WARN)
        return false
      end
      fresh.thread = fresh.thread or {}
      table.insert(fresh.thread, { from = "you", body = text, at = now() })
      fresh.status = "open"
    end)
  end, after)
end

---@return ReviewTarget|nil, ReviewNote|nil
local function cursor_note()
  local t = target()
  if not t then
    not_in_diff()
    return nil, nil
  end
  local note = note_at(t, vim.fn.line("."))
  if not note then
    notify("No note on this line")
  end
  return t, note
end

---Edit your latest message in the note under the cursor.
function M.edit()
  local t, note = cursor_note()
  if not (t and note) then
    return
  end
  local index
  for i = #(note.thread or {}), 1, -1 do
    if note.thread[i].from == "you" then
      index = i
      break
    end
  end
  if not index then
    return notify("Nothing of yours to edit in #" .. note.id)
  end
  local lines = vim.split(note.thread[index].body, "\n", { plain = true })
  editor(("Edit · #%d %s"):format(note.id, range_label(note)), lines, t.toplevel, function(text)
    mutate(t.toplevel, function(data)
      local fresh = find(data, note.id)
      if not (fresh and fresh.thread and fresh.thread[index]) then
        return false
      end
      fresh.thread[index].body = text
      fresh.thread[index].at = now()
      -- Editing the last word puts the note back in Claude's court.
      if index == #fresh.thread then
        fresh.status = "open"
      end
    end)
  end)
end

---Resolve `note`, or reopen it when it's resolved.
---@param toplevel string
---@param note ReviewNote
local function set_resolved(toplevel, note)
  mutate(toplevel, function(data)
    local fresh = find(data, note.id)
    if not fresh then
      return false
    end
    fresh.status = fresh.status == "resolved" and "open" or "resolved"
    notify(("#%d %s"):format(fresh.id, fresh.status == "resolved" and "resolved" or "reopened"))
  end)
end

---Resolve the note under the cursor, or reopen it when it's resolved.
function M.toggle_resolved()
  local t, note = cursor_note()
  if t and note then
    set_resolved(t.toplevel, note)
  end
end

function M.delete()
  local t, note = cursor_note()
  if not (t and note) then
    return
  end
  local msg = latest(note)
  local prompt = ("Delete #%d (%s)?"):format(note.id, truncate(first_line(msg and msg.body), 50))
  if vim.fn.confirm(prompt, "&Yes\n&No", 2) ~= 1 then
    return
  end
  mutate(t.toplevel, function(data)
    local _, index = find(data, note.id)
    if not index then
      return false
    end
    table.remove(data.notes, index)
  end)
end

---"2026-11-23T00:38:39Z" (UTC) as local time, "2026-11-22 18:38".
local function local_time(iso)
  local y, mo, d, h, mi, sec = (iso or ""):match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)Z$")
  if not y then
    return iso or ""
  end
  -- os.time reads the table as local time; shift by the UTC offset to read it as UTC.
  local stamp = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = sec })
  local now = os.time()
  local offset = os.difftime(now, os.time(os.date("!*t", now)))
  return os.date("%Y-%m-%d %H:%M", stamp + offset)
end

---The thread as markdown, for the float and the picker preview, plus extmarks
---(Snacks preview format: 1-based `row`) that style each message's header line.
---@param note ReviewNote
---@return string[] lines, table[] marks
local function thread_markdown(note)
  local lines = {
    ("# #%d %s · %s"):format(note.id, range_label(note), note.status),
    "",
  }
  if note.subject then
    table.insert(lines, ("_%s side of %s: %s_"):format(note.side, (note.commit or note.rev):sub(1, 8), note.subject))
  else
    table.insert(lines, ("_%s side (%s)_"):format(note.side, note.rev:sub(1, 8)))
  end
  table.insert(lines, "")
  table.insert(lines, "```" .. (vim.filetype.match({ filename = note.path }) or ""))
  vim.list_extend(lines, note.excerpt or {})
  table.insert(lines, "```")
  local marks = {}
  for _, msg in ipairs(note.thread or {}) do
    local who = msg.from == "claude" and "Claude" or "You"
    local name = "▌ " .. who
    table.insert(lines, "")
    table.insert(lines, name .. "  ·  " .. local_time(msg.at))
    local row = #lines
    table.insert(marks, { row = row, col = 0, line_hl_group = "ReviewNote" .. who .. "Band" })
    table.insert(marks, { row = row, col = 0, end_col = #name, hl_group = "ReviewNote" .. who })
    table.insert(marks, { row = row, col = #name, end_col = #lines[row], hl_group = "ReviewNoteTime" })
    table.insert(lines, "")
    vim.list_extend(lines, vim.split(msg.body or "", "\n", { plain = true }))
  end
  return lines, marks
end

---------------------------------------------------------------------------
-- List
---------------------------------------------------------------------------

---Open the note's diff in the current view and put the cursor on it. Working-tree
---notes open the file itself; notes on commits outside this view only say where
---they are.
---@param note ReviewNote
local function jump(note, toplevel)
  if note.rev == "WORKING" then
    vim.cmd.edit(vim.fn.fnameescape(toplevel .. "/" .. note.path))
    pcall(api.nvim_win_set_cursor, 0, { note.start, 0 })
    return
  end

  local view = current_view()
  local panel = view and view.panel
  local commit = note.commit or note.rev
  local file
  for _, entry in ipairs(panel and panel.entries or {}) do
    if entry.commit and entry.commit.hash == commit then
      for _, f in ipairs(entry.files) do
        if f.path == note.path then
          file = f
        end
      end
    end
  end
  if not file then
    notify(("#%d is on %s in %s, which isn't in this view"):format(note.id, note.path, commit:sub(1, 8)))
    return
  end

  local async = require("diffview.async")
  async.void(function()
    async.await(view:set_file(file))
    async.await(async.scheduler())
    local symbol = note.side == "old" and "a" or "b"
    for _, w in ipairs(view.cur_layout.windows) do
      if w.file and w.file.symbol == symbol and api.nvim_win_is_valid(w.id) then
        api.nvim_set_current_win(w.id)
        pcall(api.nvim_win_set_cursor, w.id, { note.start, 0 })
        vim.cmd("normal! zz")
      end
    end
  end)()
end

---Show a note's whole thread in a float.
---  o  go to the code (closes the float)
---  r  reply; the thread reopens afterwards with your message in it
---  x  resolve / reopen
---  q  close, or back to the list when the thread was opened from it (`back`)
---@param note ReviewNote
---@param toplevel string
---@param back? fun() reopens the list
local function open_thread(note, toplevel, back)
  local resolve_label = note.status == "resolved" and "reopen" or "resolve"
  local lines, marks = thread_markdown(note)

  -- What runs once the float has closed; each key sets it, then closes.
  local next_step = back
  local function close_then(fn, desc)
    return {
      function(self)
        next_step = fn
        self:close()
      end,
      desc = desc,
    }
  end
  local function reopen()
    local s = load(toplevel)
    local fresh = s and find(s.data, note.id)
    if fresh then
      open_thread(fresh, toplevel, back)
    end
  end

  local keys = {
    q = close_then(back, back and "Back to the list" or "Close"),
    o = close_then(function()
      jump(note, toplevel)
    end, "Go to the code"),
    r = close_then(function()
      M.reply(note, { toplevel = toplevel }, reopen)
    end, "Reply"),
    x = close_then(function()
      set_resolved(toplevel, note)
      if back then
        back()
      end
    end, resolve_label == "reopen" and "Reopen" or "Resolve"),
  }
  if back then
    keys["<Esc>"] = close_then(nil, "Close")
  end

  local footer = back and " o code · r reply · x %s · q list · <Esc> close "
    or " o code · r reply · x %s · q close "
  local win = Snacks.win({
    title = (" Note #%d "):format(note.id),
    footer = footer:format(resolve_label),
    width = 0.6,
    min_width = 70,
    height = 0.6,
    border = "rounded",
    enter = true,
    ft = "markdown",
    text = lines,
    bo = { buftype = "nofile", bufhidden = "wipe", modifiable = false },
    wo = { wrap = true, linebreak = true, conceallevel = 2 },
    on_close = function()
      if next_step then
        vim.schedule(next_step)
      end
    end,
    keys = keys,
  })
  for _, mark in ipairs(marks) do
    local opts = vim.deepcopy(mark)
    opts.row, opts.col = nil, nil
    api.nvim_buf_set_extmark(win.buf, NS, mark.row - 1, mark.col, opts)
  end
end

---Show the whole thread of the note under the cursor.
function M.view()
  local t, note = cursor_note()
  if t and note then
    open_thread(note, t.toplevel)
  end
end

---Pick from every note in the repo; replied ones (waiting on you) first.
---<CR> opens the thread; `q` in the thread comes back here.
---@param focus_id? integer note to put the cursor on
function M.list(focus_id)
  local toplevel = view_toplevel(current_view())
  if not toplevel then
    local out = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })
    toplevel = vim.v.shell_error == 0 and out[1] or nil
  end
  if not toplevel then
    return notify("Not in a git repo", vim.log.levels.WARN)
  end
  local s = load(toplevel)
  local notes = s and s.data.notes or {}
  if #notes == 0 then
    return notify("No review notes in " .. toplevel)
  end

  local items = {}
  for _, note in ipairs(notes) do
    local msg = latest(note)
    table.insert(items, {
      note = note,
      text = ("#%d %s %s %s"):format(note.id, note.status, range_label(note), msg and msg.body or ""),
      preview = (function()
        local lines, marks = thread_markdown(note)
        return { text = table.concat(lines, "\n"), ft = "markdown", loc = false, extmarks = marks }
      end)(),
    })
  end
  table.sort(items, function(a, b)
    local ra, rb = STATUS_RANK[a.note.status] or 9, STATUS_RANK[b.note.status] or 9
    if ra ~= rb then
      return ra < rb
    end
    return a.note.id < b.note.id
  end)

  local picker = Snacks.picker.pick({
    title = "Review notes",
    items = items,
    preview = "preview",
    format = function(item)
      local note = item.note
      local status = HL[note.status] and note.status or "open"
      local msg = latest(note)
      return {
        { ICONS[status] .. " ", HL[status] },
        { ("#%-3d "):format(note.id), HL[status] },
        { range_label(note) .. "  ", "SnacksPickerFile" },
        { first_line(msg and msg.body), "ReviewNoteText" },
      }
    end,
    confirm = function(p, item)
      p:close()
      if item then
        local id = item.note.id
        vim.schedule(function()
          open_thread(item.note, toplevel, function()
            M.list(id)
          end)
        end)
      end
    end,
  })

  -- Coming back from a thread: put the cursor on that note again (same approach
  -- as Snacks.picker.resume).
  if focus_id and picker then
    picker.matcher.task:on(
      "done",
      vim.schedule_wrap(function()
        if picker.closed then
          return
        end
        for item, idx in picker:iter() do
          if item.note.id == focus_id then
            picker.list:view(idx)
            return
          end
        end
      end)
    )
  end
end

---------------------------------------------------------------------------
-- Sending to Claude
---------------------------------------------------------------------------

-- Typed into Claude Code's prompt. The skill's name is the top autocomplete match,
-- so one Enter runs it; if Claude is mid-turn, it queues.
local COMMAND = "/review-notes"

-- toplevel -> the pane picked last time there was more than one candidate.
local chosen = {}

---@class ClaudePane
---@field id string Rex block ID or tmux pane ID
---@field cwd string
---@field title string Claude sets the terminal title to the conversation's title
---@field session? string Rex session ID
---@field where? string Rex session label, or tmux session:window

---Run `jobs` (each takes a callback) in parallel; `done` runs once all have called back.
---@param jobs fun(next: fun())[]
local function parallel(jobs, done)
  local left = #jobs
  if left == 0 then
    return done()
  end
  for _, job in ipairs(jobs) do
    job(function()
      left = left - 1
      if left == 0 then
        done()
      end
    end)
  end
end

local function run(cmd, on_out)
  vim.system(cmd, { text = true }, function(res)
    on_out(res.code == 0 and res.stdout or "")
  end)
end

local function decode(text)
  local ok, value = pcall(vim.json.decode, text)
  return ok and type(value) == "table" and value or {}
end

---Claude Code panes in this Rex server, across every session. Rex resolves a block
---ID only within the current session unless the call names one, so each call
---carries `-s`. Everything runs in parallel: one `process` call per block, then a
---`title` call per Claude block.
---@param cb fun(panes: ClaudePane[])
local function rex_panes(cb)
  local found = {}
  run({ "rex", "ls", "--json" }, function(out)
    local jobs = {}
    for _, session in ipairs(decode(out).sessions or {}) do
      local sid = session.session_id
      table.insert(jobs, function(next_session)
        run({ "rex", "block", "ls", "-s", sid, "-q", "--short=false" }, function(ids)
          local block_jobs = {}
          for _, id in ipairs(vim.split(vim.trim(ids), "\n", { trimempty = true })) do
            table.insert(block_jobs, function(next_block)
              run({ "rex", "block", "call", "-s", sid, "-b", id, "process" }, function(proc)
                local fg = decode(proc).foreground
                local argv0 = type(fg) == "table" and fg.argv0 or ""
                if (argv0 == "claude" or argv0:match("/claude$")) and fg.cwd then
                  table.insert(found, { id = id, session = sid, where = session.label, cwd = fg.cwd, title = "" })
                end
                next_block()
              end)
            end)
          end
          parallel(block_jobs, next_session)
        end)
      end)
    end

    parallel(jobs, function()
      local title_jobs = {}
      for _, pane in ipairs(found) do
        table.insert(title_jobs, function(next_title)
          run({ "rex", "block", "call", "-s", pane.session, "-b", pane.id, "title" }, function(t)
            pane.title = decode(t).title or ""
            next_title()
          end)
        end)
      end
      parallel(title_jobs, function()
        cb(found)
      end)
    end)
  end)
end

---Claude Code panes in this tmux server: panes with a `claude` process on their tty.
---Two quick commands, so this runs synchronously.
---@param cb fun(panes: ClaudePane[])
local function tmux_panes(cb)
  local claude_ttys = {}
  local ps = vim.system({ "ps", "-axo", "tty=,args=" }, { text = true }):wait()
  for _, line in ipairs(vim.split(ps.stdout or "", "\n", { trimempty = true })) do
    local tty, argv0, arg1 = line:match("^%s*(%S+)%s+(%S+)%s*(%S*)")
    -- Claude Code's background helpers (`claude daemon`, `claude bg-spare`, ...) can
    -- sit on a tty too; only an interactive session takes typed input.
    local helper = arg1 == "daemon" or arg1:match("^bg%-")
    if tty and (argv0 == "claude" or argv0:match("/claude$")) and not helper then
      claude_ttys[tty] = true
    end
  end

  local fmt = "#{pane_id}\t#{pane_tty}\t#{pane_current_path}\t#{pane_title}\t#{session_name}:#{window_index}"
  local res = vim.system({ "tmux", "list-panes", "-a", "-F", fmt }, { text = true }):wait()
  local found = {}
  for _, line in ipairs(vim.split(res.stdout or "", "\n", { trimempty = true })) do
    local id, tty, cwd, title, where = unpack(vim.split(line, "\t", { plain = true }))
    -- ps prints ttys without /dev/: "ttys003" for /dev/ttys003.
    if tty and claude_ttys[(tty:gsub("^/dev/", ""))] then
      table.insert(found, { id = id, cwd = cwd, title = title or "", where = where })
    end
  end
  cb(found)
end

local function send_keys(mux, pane)
  if mux == "rex" then
    vim.system({ "rex", "block", "send", "-s", pane.session, "-b", pane.id, COMMAND }):wait()
    -- Let the autocomplete list open before Enter picks from it.
    vim.defer_fn(function()
      vim.system({ "rex", "block", "send-key", "-s", pane.session, "-b", pane.id, "enter" })
    end, 150)
  else
    vim.system({ "tmux", "send-keys", "-t", pane.id, "-l", COMMAND }):wait()
    vim.defer_fn(function()
      vim.system({ "tmux", "send-keys", "-t", pane.id, "Enter" })
    end, 150)
  end
  local label = pane.title ~= "" and pane.title or pane.cwd
  notify(("Sent %s to Claude: %s"):format(COMMAND, label))
end

local function inside(path, dir)
  return path == dir or path:sub(1, #dir + 1) == dir .. "/"
end

---Type /review-notes into the Claude Code session working in this repo, so its
---open notes get handled without leaving Neovim. With one Claude in the repo it goes
---there; otherwise pick one (remembered for this repo until that pane is gone).
---@param toplevel? string the repo; defaults to the current view's, then cwd's
function M.send_to_claude(toplevel)
  toplevel = toplevel or view_toplevel(current_view())
  if not toplevel then
    local out = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })
    toplevel = vim.v.shell_error == 0 and out[1] or nil
  end
  if not toplevel then
    return notify("Not in a git repo", vim.log.levels.WARN)
  end

  local s = load(toplevel)
  local open = 0
  for _, note in ipairs(s and s.data.notes or {}) do
    if note.status == "open" then
      open = open + 1
    end
  end
  if open == 0 then
    return notify("No open notes for Claude in " .. vim.fn.fnamemodify(toplevel, ":t"))
  end

  local mux = vim.env.REX_BLOCK and "rex" or (vim.env.TMUX and "tmux") or nil
  if not mux then
    return notify("Not inside Rex or tmux; run " .. COMMAND .. " in Claude yourself", vim.log.levels.WARN)
  end

  local finder = mux == "rex" and rex_panes or tmux_panes
  finder(vim.schedule_wrap(function(panes)
    if #panes == 0 then
      return notify("No Claude Code session found in " .. mux, vim.log.levels.WARN)
    end

    for _, pane in ipairs(panes) do
      if pane.id == chosen[toplevel] then
        return send_keys(mux, pane)
      end
    end

    local here = vim.tbl_filter(function(pane)
      return inside(pane.cwd, toplevel)
    end, panes)
    if #here == 1 then
      return send_keys(mux, here[1])
    end

    -- None in the repo (Claude started from a parent dir) or several: ask.
    local options = #here > 1 and here or panes
    vim.ui.select(options, {
      prompt = ("Send %s (%d open) to which Claude?"):format(COMMAND, open),
      format_item = function(pane)
        local parts = {}
        for _, part in ipairs({ pane.title, pane.where or "", vim.fn.fnamemodify(pane.cwd, ":~") }) do
          if part ~= "" then
            table.insert(parts, part)
          end
        end
        return table.concat(parts, "  ·  ")
      end,
    }, function(pane)
      if pane then
        chosen[toplevel] = pane.id
        send_keys(mux, pane)
      end
    end)
  end))
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

local installed = false

function M.setup()
  if installed then
    return
  end
  installed = true

  set_hl()
  local group = api.nvim_create_augroup("review_notes", { clear = true })
  api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_hl })
  api.nvim_create_autocmd({ "FocusGained", "CursorHold" }, { group = group, callback = check_for_changes })

  -- Fires each time diffview shows a file in one of its diff windows.
  DiffviewGlobal.emitter:on("diff_buf_win_enter", function(_, _, winid)
    local t = target(winid)
    if t then
      check_for_changes()
      pcall(decorate_buf, t.file.bufnr, t.toplevel, t.file.path, t.rev)
    end
  end)

  local ok, mod = pcall(require, "diffview.scene.views.file_history.file_history_panel")
  if ok then
    local FileHistoryPanel = mod.FileHistoryPanel
    local redraw = FileHistoryPanel.redraw
    FileHistoryPanel.redraw = function(self, ...)
      redraw(self, ...)
      pcall(decorate_panel, self)
    end
  end
end

return M
