-- The "Uncommitted changes" row at the top of the <leader>gU review panel
-- (branch_review.lua). Diffview's file history only lists commits, so this builds a
-- LogEntry by hand whose files diff HEAD against the working tree (untracked files
-- included) and puts it first in the panel. The diff's right side is the real file,
-- so it can be edited from the review.
--
-- The entry's commit hash is git's null OID. Code that runs git with a commit hash
-- checks for it with M.is(): review_marks.lua keys these files by the working-tree
-- blob (so a mark carries over to the commit that later records the same content),
-- and commit_details.lua shows the file list instead of a commit message.
--
-- Builds on diffview internals (LogEntry, FileEntry.with_layout, GitRev, the file
-- history renderer). diffview.nvim is pinned in lazy-lock.json.
local M = {}

M.NULL = string.rep("0", 40)

---@return boolean
function M.is(entry_or_commit)
  local commit = entry_or_commit and (entry_or_commit.commit or entry_or_commit)
  return commit ~= nil and commit.hash == M.NULL
end

local function git(toplevel, args)
  local cmd = { "git", "-C", toplevel, "-c", "core.quotePath=false" }
  vim.list_extend(cmd, args)
  local r = vim.system(cmd, { text = true }):wait()
  if r.code ~= 0 then
    return nil
  end
  return r.stdout or ""
end

---Every file that differs from HEAD, staged or not, plus untracked files.
---@return { path: string, oldpath?: string, status: string, stats?: { additions: integer, deletions: integer } }[]
function M.changes(toplevel)
  local status = git(toplevel, { "diff", "HEAD", "-M", "--name-status", "-z" })
  if not status then
    return {}
  end
  local files, by_path = {}, {}
  local fields = vim.split(status, "\0", { plain = true })
  local i = 1
  while i <= #fields and fields[i] ~= "" do
    local code = fields[i]
    local kind = code:sub(1, 1)
    local file
    if kind == "R" or kind == "C" then
      file = { oldpath = fields[i + 1], path = fields[i + 2], status = kind }
      i = i + 3
    else
      file = { path = fields[i + 1], status = kind }
      i = i + 2
    end
    files[#files + 1] = file
    by_path[file.path] = file
  end

  for line in (git(toplevel, { "diff", "HEAD", "-M", "--numstat" }) or ""):gmatch("[^\n]+") do
    local add, del, path = line:match("^(%d+)\t(%d+)\t(.+)$")
    -- A rename prints "old => new" or "dir/{old => new}"; the diff above has the new path.
    if path and path:find(" => ", 1, true) then
      path = path:gsub("{[^}]* => ([^}]*)}", "%1"):gsub("^.* => ", ""):gsub("//", "/")
    end
    if path and by_path[path] then
      by_path[path].stats = { additions = tonumber(add), deletions = tonumber(del) }
    end
  end

  local untracked = git(toplevel, { "ls-files", "--others", "--exclude-standard", "-z" }) or ""
  for _, path in ipairs(vim.split(untracked, "\0", { plain = true, trimempty = true })) do
    local lines = 0
    local fd = io.open(toplevel .. "/" .. path, "rb")
    if fd then
      local data = fd:read("*a") or ""
      fd:close()
      if not data:find("\0", 1, true) then
        _, lines = data:gsub("\n", "")
      end
    end
    files[#files + 1] = { path = path, status = "?", stats = { additions = lines, deletions = 0 } }
  end

  table.sort(files, function(a, b)
    return a.path < b.path
  end)
  return files
end

---The review-mark blob of each changed file: what's on disk now, or "d" + HEAD's blob
---for a deleted file. Matches the key a commit of the same content gets.
---@return table<string, string|false> path -> blob
function M.blobs(toplevel, files)
  local result, present, deleted = {}, {}, {}
  for _, f in ipairs(files) do
    if f.status == "D" then
      deleted[#deleted + 1] = f.path
    else
      present[#present + 1] = f.path
    end
  end
  if #present > 0 then
    local args = { "hash-object", "--" }
    vim.list_extend(args, present)
    local out = git(toplevel, args)
    local hashes = out and vim.split(vim.trim(out), "\n", { plain = true }) or {}
    for i, path in ipairs(present) do
      result[path] = hashes[i] or false
    end
  end
  if #deleted > 0 then
    local args = { "ls-tree", "-z", "HEAD", "--" }
    vim.list_extend(args, deleted)
    for line in (git(toplevel, args) or ""):gmatch("[^%z]+") do
      local sha, path = line:match("^%d+ %w+ (%x+)\t(.+)$")
      if sha then
        result[path] = "d" .. sha
      end
    end
  end
  return result
end

---A LogEntry for the uncommitted changes in the view's repo, or nil when there are none.
function M.entry(view)
  local panel = view.panel
  local adapter = panel.adapter
  local toplevel = adapter.ctx.toplevel
  local files = M.changes(toplevel)
  if #files == 0 then
    return nil
  end
  local head = vim.trim(git(toplevel, { "rev-parse", "HEAD" }) or "")
  if head == "" then
    return nil
  end

  local GitRev = require("diffview.vcs.adapters.git.rev").GitRev
  local RevType = require("diffview.vcs.rev").RevType
  local GitCommit = require("diffview.vcs.adapters.git.commit").GitCommit
  local FileEntry = require("diffview.scene.file_entry").FileEntry
  local LogEntry = require("diffview.vcs.log_entry").LogEntry

  local lines = {}
  for _, f in ipairs(files) do
    lines[#lines + 1] = ("%s  %s"):format(f.status, f.oldpath and (f.oldpath .. " → " .. f.path) or f.path)
  end
  local commit = GitCommit({
    hash = M.NULL,
    author = "you",
    time = os.time(),
    rel_date = "not committed",
    ref_names = "working tree",
    subject = ("Uncommitted changes (%d file%s)"):format(#files, #files == 1 and "" or "s"),
    body = table.concat(lines, "\n"),
  })

  local layout = view.get_default_layout()
  local entries = {}
  for _, f in ipairs(files) do
    entries[#entries + 1] = FileEntry.with_layout(layout, {
      adapter = adapter,
      path = f.path,
      oldpath = f.oldpath,
      status = f.status == "?" and "A" or f.status,
      stats = f.stats,
      kind = "working",
      commit = commit,
      revs = {
        a = f.status == "?" and GitRev.new_null_tree() or GitRev(RevType.COMMIT, head),
        b = GitRev(RevType.LOCAL),
      },
    })
  end
  return LogEntry({ path_args = {}, commit = commit, files = entries, single_file = false })
end

---For diffview_panel.reload_in_place's `extra`: `entries` with a fresh
---uncommitted-changes row on top (none when the tree is clean).
function M.prepend(view, entries)
  local wt = M.entry(view)
  if not wt then
    return entries
  end
  wt.folded = false
  local out = { wt }
  vim.list_extend(out, entries)
  return out
end

---Adds the uncommitted-changes row to a panel diffview has just loaded, and redraws.
---Reloads replace it through diffview_panel.reload_in_place's `extra` option, which
---also takes care of releasing the old row's buffers.
function M.inject(view)
  local panel = view.panel
  for _, entry in ipairs(panel.entries or {}) do
    if M.is(entry) then
      return entry
    end
  end
  local kept = M.prepend(view, panel.entries or {})
  local wt = kept[1] ~= (panel.entries or {})[1] and kept[1] or nil
  panel.entries = kept
  require("diffview.scene.views.file_history.render").clear_cache(panel)
  panel:update_components()
  panel:render()
  panel:redraw()
  return wt
end

return M
