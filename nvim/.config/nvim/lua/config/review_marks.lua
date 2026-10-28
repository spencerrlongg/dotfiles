-- Review tracking for the unpushed-commits panel (<leader>gU).
--
-- Draws a marker on every file row in diffview's file-history panel and remembers
-- which files have been reviewed across restarts. Marks are set by hand (`m` in the
-- panel) rather than by opening a diff: opening a file is not the same as having
-- reviewed it, and auto-marking would check off files that were only glanced at.
--
-- Diffview has no API for decorating panel rows, so this wraps the panel's redraw
-- and places extmarks using the line ranges its renderer records on each component
-- (`renderer.lua`: RenderComponent.lstart/lend). diffview.nvim is pinned in
-- lazy-lock.json, so those internals only move when the lock file does.

local M = {}

local NS = vim.api.nvim_create_namespace("review_marks")
local STATE_FILE = vim.fn.stdpath("state") .. "/diffview-review-marks.json"

-- Marks that haven't been seen in this long are dropped when the state file is
-- read, so it doesn't accumulate entries from branches that were pushed and deleted.
local MARK_TTL = 90 * 24 * 60 * 60

local SIGN_DONE = "✓"
local SIGN_TODO = "○"

-- Drawn right-aligned over the panel header once every file in every commit is
-- marked. Rows are padded to the same width so right-aligning keeps the shape.
local ALL_DONE_ART = {
  "            ▄██▀",
  "         ▄██▀   ",
  " ▀██▄▄▄██▀      ",
  "   ▀██▀         ",
}

-- toplevel -> mark key -> unix time the mark was set. Read lazily, kept in memory
-- for the session, written back on every toggle.
---@type table<string, table<string, integer>>|nil
local state = nil

-- "<commit>:<path>" -> blob hash, or false when git couldn't resolve one. Commit
-- hashes are immutable, so a resolved entry is good for the rest of the session.
local blobs = {}

local function read_state()
  if state then
    return state
  end
  state = {}

  local ok, lines = pcall(vim.fn.readfile, STATE_FILE)
  if not ok then
    return state
  end

  local decoded_ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not decoded_ok or type(decoded) ~= "table" then
    return state
  end

  local cutoff = os.time() - MARK_TTL
  for toplevel, marks in pairs(decoded) do
    if type(marks) == "table" then
      local kept = {}
      for key, ts in pairs(marks) do
        if type(ts) == "number" and ts >= cutoff then
          kept[key] = ts
        end
      end
      if next(kept) then
        state[toplevel] = kept
      end
    end
  end

  return state
end

local function write_state()
  -- vim.json.encode turns an empty table into an array, which then fails to decode
  -- back into the toplevel -> marks shape. Write the empty object literally instead.
  local payload = next(state or {}) and vim.json.encode(state) or "{}"
  pcall(vim.fn.writefile, { payload }, STATE_FILE)
end

local function git(toplevel, args)
  local cmd = { "git", "-C", toplevel }
  vim.list_extend(cmd, args)
  local out = vim.trim(vim.fn.system(cmd))
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return out
end

---Resolve the blob hash of every file in a log entry, one `ls-tree` per commit.
---Files deleted by the commit have no post-image, so they fall back to the blob
---from the parent commit, tagged "d" so a delete can't collide with an add of the
---same content.
---@param toplevel string
---@param entry table LogEntry
local function resolve_blobs(toplevel, entry)
  local hash = entry.commit and entry.commit.hash
  if not hash then
    return
  end

  local pending = {}
  for _, file in ipairs(entry.files) do
    if blobs[hash .. ":" .. file.path] == nil then
      table.insert(pending, file.path)
    end
  end
  if #pending == 0 then
    return
  end

  -- `-z` leaves paths unquoted; systemlist() turns the NUL separators into entries.
  local cmd = { "git", "-C", toplevel, "ls-tree", "-z", hash, "--" }
  vim.list_extend(cmd, pending)
  local out = vim.fn.systemlist(cmd)
  if vim.v.shell_error == 0 then
    for _, line in ipairs(out) do
      local sha, path = line:match("^%d+ %w+ (%x+)\t(.+)$")
      if sha then
        blobs[hash .. ":" .. path] = sha
      end
    end
  end

  for _, path in ipairs(pending) do
    local key = hash .. ":" .. path
    if blobs[key] == nil then
      local sha = git(toplevel, { "rev-parse", "--verify", "--quiet", hash .. ":" .. path })
      if sha and sha ~= "" then
        blobs[key] = sha
      else
        sha = git(toplevel, { "rev-parse", "--verify", "--quiet", hash .. "^:" .. path })
        blobs[key] = (sha and sha ~= "") and ("d" .. sha) or false
      end
    end
  end
end

---Content-keyed so the mark survives an amend or a rebase: those rewrite every
---commit hash in the unpushed range, but leave the blobs of untouched files alone.
---Falls back to the commit hash when git couldn't resolve a blob, which keeps the
---toggle working at the cost of resetting that one file on the next rewrite.
---@return string
local function mark_key(entry, file)
  local hash = entry.commit and entry.commit.hash or "?"
  local blob = blobs[hash .. ":" .. file.path]
  if not blob then
    return "c" .. hash .. ":" .. file.path
  end
  return blob .. ":" .. file.path
end

local function set_hl()
  vim.api.nvim_set_hl(0, "ReviewMarkDone", { link = "DiffviewFilePanelInsertions", default = true })
  vim.api.nvim_set_hl(0, "ReviewMarkTodo", { link = "DiffviewNonText", default = true })
  vim.api.nvim_set_hl(0, "ReviewMarkCount", { link = "DiffviewFilePanelCounter", default = true })
end

---File rows are rendered as a tree prefix ("│   " / "└   ") before the git status,
---so the marker overlays the middle of those three spaces: byte 0-2 are the box
---drawing character, bytes 3-5 the padding.
local function overlay_mark(buf, lines, row, done)
  local line = lines[row + 1]
  if not line or #line < 5 then
    return
  end
  vim.api.nvim_buf_set_extmark(buf, NS, row, 4, {
    virt_text = { { done and SIGN_DONE or SIGN_TODO, done and "ReviewMarkDone" or "ReviewMarkTodo" } },
    virt_text_pos = "overlay",
    hl_mode = "combine",
    priority = 100,
  })
end

---Neovim draws "eol" virtual text one cell past the last character, which is
---already the gap between the row and the mark, so text needs no leading space.
local function eol_mark(buf, lines, row, text, hl)
  if not lines[row + 1] then
    return
  end
  vim.api.nvim_buf_set_extmark(buf, NS, row, 0, {
    virt_text = { { text, hl } },
    virt_text_pos = "eol",
    -- Without combine the mark paints its own (empty) background, which punches a
    -- hole in the CursorLine band on the selected commit row.
    hl_mode = "combine",
    priority = 100,
  })
end

---True when every file of every commit in the panel is marked. Reads
---panel.entries rather than the rendered components, which stop at 128 entries
---while the log is still streaming in, and waits for that stream to finish.
local function all_reviewed(panel, toplevel, marks)
  if panel.updating or not panel.entries or #panel.entries == 0 then
    return false
  end
  for _, entry in ipairs(panel.entries) do
    resolve_blobs(toplevel, entry)
    for _, file in ipairs(entry.files) do
      if not marks[mark_key(entry, file)] then
        return false
      end
    end
  end
  return true
end

---The checkmark goes on the header rows above the "File History" title, and an
---"all reviewed" label after the title itself. The header is shorter than the art
---when diffview's help hints are turned off; the label still shows then.
local function draw_all_done(panel, buf, lines)
  local title = panel.components.log.title and panel.components.log.title.comp
  if not title or title.lend <= 0 then
    return
  end
  -- The title component is an empty line followed by the title text.
  local title_row = title.lend - 1

  if title_row >= #ALL_DONE_ART then
    for i, art in ipairs(ALL_DONE_ART) do
      vim.api.nvim_buf_set_extmark(buf, NS, i - 1, 0, {
        virt_text = { { art, "ReviewMarkDone" } },
        virt_text_pos = "right_align",
        hl_mode = "combine",
        priority = 100,
      })
    end
  end

  eol_mark(buf, lines, title_row, SIGN_DONE .. " all reviewed", "ReviewMarkDone")
end

---@param panel table FileHistoryPanel
local function decorate(panel)
  local buf = panel.bufid
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)

  local toplevel = panel.adapter and panel.adapter.ctx and panel.adapter.ctx.toplevel
  local entries = panel.components and panel.components.log and panel.components.log.entries
  if not toplevel or not entries then
    return
  end

  local marks = read_state()[toplevel] or {}
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  for _, struct in ipairs(entries) do
    local entry = struct.comp.context
    if entry and entry.files and #entry.files > 0 then
      resolve_blobs(toplevel, entry)

      local done = 0
      for _, file in ipairs(entry.files) do
        if marks[mark_key(entry, file)] then
          done = done + 1
        end
      end

      if entry.single_file then
        -- History of a single file renders one row per commit and no nested file
        -- rows, so the commit row is the file row.
        eol_mark(
          buf,
          lines,
          struct.commit.comp.lstart,
          done > 0 and SIGN_DONE or SIGN_TODO,
          done > 0 and "ReviewMarkDone" or "ReviewMarkTodo"
        )
      else
        local files = struct.files.comp
        for i, file in ipairs(entry.files) do
          local row = files.lstart + i - 1
          -- A folded entry renders no file rows at all, and the panel caps how many
          -- entries it builds while the log is still streaming in.
          if files.lstart >= 0 and row < files.lend then
            overlay_mark(buf, lines, row, marks[mark_key(entry, file)] ~= nil)
          end
        end

        if done > 0 then
          local total = #entry.files
          local text = done == total and SIGN_DONE or ("%d/%d"):format(done, total)
          eol_mark(buf, lines, struct.commit.comp.lstart, text, done == total and "ReviewMarkDone" or "ReviewMarkCount")
        end
      end
    end
  end

  if all_reviewed(panel, toplevel, marks) then
    draw_all_done(panel, buf, lines)
  end
end

local function current_panel()
  local ok, lib = pcall(require, "diffview.lib")
  if not ok then
    return nil
  end
  local view = lib.get_current_view()
  local panel = view and view.panel
  if panel and panel.get_item_at_cursor and panel.find_entry then
    return panel
  end
end

---Toggle the file under the cursor. On a commit row, toggles every file in that
---commit at once — all off if they were all on, otherwise all on.
function M.toggle()
  local panel = current_panel()
  if not panel then
    return
  end

  local toplevel = panel.adapter and panel.adapter.ctx and panel.adapter.ctx.toplevel
  local item = panel:get_item_at_cursor()
  if not toplevel or not item then
    return
  end

  -- A LogEntry carries the files of its commit; a FileEntry doesn't have the field.
  local entry, files
  if item.files then
    entry, files = item, item.files
  else
    entry, files = panel:find_entry(item), { item }
  end
  if not entry or #files == 0 then
    return
  end

  local marks = read_state()[toplevel]
  if not marks then
    marks = {}
    state[toplevel] = marks
  end

  resolve_blobs(toplevel, entry)

  local all_marked = true
  for _, file in ipairs(files) do
    if not marks[mark_key(entry, file)] then
      all_marked = false
      break
    end
  end

  local now = os.time()
  for _, file in ipairs(files) do
    marks[mark_key(entry, file)] = (not all_marked) and now or nil
  end

  if not next(marks) then
    state[toplevel] = nil
  end

  write_state()
  decorate(panel)
end

---Drop every mark for a repo. Content keying makes stale marks harmless (they only
---match if the same content shows up again), so this is an escape hatch rather than
---part of the normal loop.
function M.clear()
  local panel = current_panel()
  local toplevel = panel and panel.adapter and panel.adapter.ctx and panel.adapter.ctx.toplevel
    or git(vim.fn.getcwd(), { "rev-parse", "--show-toplevel" })

  if not toplevel then
    vim.notify("Not in a git repo", vim.log.levels.ERROR)
    return
  end

  local marks = read_state()[toplevel]
  local count = 0
  for _ in pairs(marks or {}) do
    count = count + 1
  end

  state[toplevel] = nil
  write_state()

  if panel then
    decorate(panel)
  end
  vim.notify(("Cleared %d review mark%s in %s"):format(count, count == 1 and "" or "s", toplevel))
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
  -- Resolves to Panel:redraw through the class metatable; the panel renders its
  -- buffer there, so the marks go on right after.
  local redraw = FileHistoryPanel.redraw

  FileHistoryPanel.redraw = function(self, ...)
    redraw(self, ...)
    pcall(decorate, self)
  end

  vim.api.nvim_create_autocmd("FileType", {
    pattern = "DiffviewFileHistory",
    callback = function(ev)
      vim.keymap.set("n", "m", M.toggle, { buffer = ev.buf, desc = "Toggle reviewed" })
    end,
  })

  vim.api.nvim_create_user_command("ReviewMarksClear", M.clear, {
    desc = "Clear all review marks for the current repo",
  })
end

return M
