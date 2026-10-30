-- Branch review (<leader>gR): review a branch commit by commit, like a PR before
-- there is one.
--
-- <leader>gU shows what isn't pushed yet, so pushing changes what it shows. This
-- measures a branch against trunk instead, pushed or not, so a feature can be pushed
-- part-way through review and still be reviewed as a whole. The branch doesn't have
-- to be checked out.
--
-- Stacked branches: when another local branch's tip is in this branch's history
-- (feature/b was started from feature/a), that branch is the base and the review
-- covers only this branch's own commits. `S` in the panel switches to everything
-- since trunk. Branches under backup/ never count as a base.
--
-- The panel is diffview's file history, so review marks (`m`, review_marks.lua) and
-- commit bodies (commit_details.lua) work as in <leader>gU. Marks are keyed by file
-- content, so ones set from either panel show up in both.
--
-- Panel keys, on top of diffview's own:
--   m  mark the file (or the commit's files) reviewed
--   r  refresh: new commits, a rebase, or a base branch that has since merged
--   S  this branch's own commits <-> everything since trunk
--   H  hide / show commits whose files are all reviewed
--   B  switch to another branch, in the same tab
--   D  the whole branch as one diff against its base (read-only, like a PR's
--      "Files changed"); <leader>gX closes it

local M = {}

local panel_ui = require("config.diffview_panel")
local review_marks = require("config.review_marks")

-- The branch this repo's PRs merge into, in order of preference. develop comes first
-- because repos that have one (Snipe-IT) merge features there, not into main.
local TRUNKS = { "origin/develop", "origin/main", "origin/master", "develop", "main", "master" }

-- Branches that are never treated as another branch's base: a backup sitting in the
-- middle of a feature would otherwise hide every commit below it.
local NOT_A_BASE = { "^backup/" }

-- Panel buffer -> review state, for updating the winbar when marks change.
---@type table<integer, BranchReview>
local reviews = {}

---@class BranchReview
---@field toplevel string
---@field trunk string
---@field ref string         refs/heads/<name>
---@field name string
---@field base_ref? string   the stacked-on branch, nil when the base is trunk
---@field base_name? string
---@field stack boolean      true: measure against trunk even when there is a base branch
---@field hide boolean       true: leave fully reviewed commits out of the panel
---@field commits ReviewCommit[]
---@field buf? integer
---@field win? integer
---@field busy? boolean

---@class ReviewCommit
---@field hash string
---@field short string
---@field subject string
---@field age string
---@field keys string[]  review-mark keys of the commit's files
---@field done? integer  how many of `keys` are marked

---@return string|nil
local function git(dir, args)
  local cmd = { "git", "-C", dir }
  vim.list_extend(cmd, args)
  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end
  return result.stdout or ""
end

local function find_trunk(toplevel)
  for _, ref in ipairs(TRUNKS) do
    if git(toplevel, { "rev-parse", "--verify", "--quiet", ref }) then
      return ref
    end
  end
end

local function can_be_base(name)
  for _, pat in ipairs(NOT_A_BASE) do
    if name:match(pat) then
      return false
    end
  end
  return true
end

---Every local branch with commits that aren't in trunk, with its stacked-on base.
---One rev-list per branch, run in parallel.
---@return table[] { ref, name, current, age, date, commits = string[] (newest first), base_ref?, base_name? }
local function list_branches(toplevel, trunk)
  local out = git(toplevel, {
    "for-each-ref",
    "--format=%(refname)%09%(HEAD)%09%(committerdate:unix)%09%(committerdate:relative)",
    "refs/heads",
  }) or ""

  local all = {}
  for line in out:gmatch("[^\n]+") do
    local ref, head, date, age = line:match("^(%S+)\t(.)\t(%d+)\t(.*)$")
    if ref then
      all[#all + 1] = {
        ref = ref,
        name = ref:gsub("^refs/heads/", ""),
        current = head == "*",
        date = tonumber(date),
        age = age,
      }
    end
  end

  local jobs = {}
  for i, b in ipairs(all) do
    jobs[i] = vim.system({ "git", "-C", toplevel, "rev-list", trunk .. ".." .. b.ref }, { text = true })
  end
  local branches = {}
  for i, job in ipairs(jobs) do
    local result = job:wait()
    if result.code == 0 then
      all[i].commits = vim.split(vim.trim(result.stdout or ""), "\n", { trimempty = true })
      if #all[i].commits > 0 then
        branches[#branches + 1] = all[i]
      end
    end
  end

  -- tip hash -> branches ending there
  local tips = {}
  for _, b in ipairs(branches) do
    if can_be_base(b.name) then
      tips[b.commits[1]] = tips[b.commits[1]] or {}
      table.insert(tips[b.commits[1]], b)
    end
  end

  -- The base is the branch whose tip comes first walking down from this branch's tip.
  -- Index 1 is the tip itself, so a branch pointing at the same commit isn't a base.
  for _, b in ipairs(branches) do
    for i = 2, #b.commits do
      local at = tips[b.commits[i]]
      if at then
        b.base_ref, b.base_name = at[1].ref, at[1].name
        break
      end
    end
  end

  table.sort(branches, function(x, y)
    if x.current ~= y.current then
      return x.current
    end
    return x.date > y.date
  end)
  return branches
end

---Starts `git log` for a range in the shape the counts need: one record per commit,
---with the blob of every file it touched. Same flags as diffview's file history, so
---the files match the panel's rows.
local function start_log(toplevel, range)
  return vim.system({
    "git",
    "-C",
    toplevel,
    "-c",
    "core.quotePath=false",
    "log",
    "--raw",
    "--no-abbrev",
    "--diff-merges=first-parent",
    "--format=%x1e%H%x1f%h%x1f%s%x1f%cr",
    range,
  }, { text = true })
end

---Parses start_log() output. Keys follow review_marks' mark_key(): the file's blob
---after the commit, or "d" + the blob before it when the commit deleted the file.
---@return ReviewCommit[]|nil
local function parse_log(result)
  if result.code ~= 0 then
    return nil
  end
  local commits = {}
  for record in (result.stdout or ""):gmatch("\30([^\30]*)") do
    local header, rest = record:match("^([^\n]*)\n?(.*)$")
    local hash, short, subject, age = unpack(vim.split(header, "\31", { plain = true }))
    local keys = {}
    for line in rest:gmatch("[^\n]+") do
      local old, new, paths = line:match("^:%d+ %d+ (%x+) (%x+) %u%d*\t(.+)$")
      if old then
        -- A rename or copy lists "old<TAB>new"; the panel shows the new path.
        local path = paths:match("\t(.+)$") or paths
        local blob = new:match("^0+$") and ("d" .. old) or new
        keys[#keys + 1] = blob .. ":" .. path
      end
    end
    commits[#commits + 1] = { hash = hash, short = short, subject = subject or "", age = age or "", keys = keys }
  end
  return commits
end

---Counts marked files per commit (sets commit.done) and in total.
---@param commits ReviewCommit[]
---@return integer done, integer total
local function count_reviewed(toplevel, commits)
  local marks = review_marks.marks(toplevel)
  local done, total = 0, 0
  for _, c in ipairs(commits) do
    c.done = 0
    for _, key in ipairs(c.keys) do
      if marks[key] then
        c.done = c.done + 1
      end
    end
    done, total = done + c.done, total + #c.keys
  end
  return done, total
end

---@param s BranchReview
local function base_of(s)
  if s.stack or not s.base_ref then
    return s.trunk, s.trunk
  end
  return s.base_ref, s.base_name
end

---@param s BranchReview
local function range_of(s)
  return base_of(s) .. ".." .. s.ref
end

local function winbar_escape(text)
  return (text:gsub("%%", "%%%%"))
end

---@param s BranchReview
local function winbar(s)
  local done, total = count_reviewed(s.toplevel, s.commits)
  local _, base_name = base_of(s)
  local n = #s.commits
  local parts = {
    "  %#Title#Review%*  ",
    "%#Directory#" .. winbar_escape(s.name) .. "%*",
    " %#Comment#← " .. winbar_escape(base_name),
    (s.stack and s.base_ref) and " (whole stack)" or "",
    ("  ·  %d commit%s  ·  %%*"):format(n, n == 1 and "" or "s"),
  }
  if total > 0 and done == total then
    parts[#parts + 1] = "%#DiagnosticOk#✓ all reviewed%*"
  else
    parts[#parts + 1] = ("%%#%s#%d/%d files reviewed%%*"):format(done > 0 and "DiagnosticWarn" or "Comment", done, total)
  end
  if s.hide then
    parts[#parts + 1] = "  %#Comment#(reviewed commits hidden)%*"
  end
  return table.concat(parts)
end

---@param s BranchReview
local function update_winbar(s)
  if s.win and vim.api.nvim_win_is_valid(s.win) and vim.api.nvim_win_get_buf(s.win) == s.buf and not s.busy then
    vim.wo[s.win].winbar = winbar(s)
  end
end

---Re-reads the branch (its tip and base may have moved) and its commits.
---@param s BranchReview
---@return boolean ok, string? err
local function load(s)
  local branch
  for _, b in ipairs(list_branches(s.toplevel, s.trunk)) do
    if b.ref == s.ref then
      branch = b
    end
  end
  if not branch then
    return false, ("%s has no commits that aren't in %s (merged, or deleted)"):format(s.name, s.trunk)
  end
  s.base_ref, s.base_name = branch.base_ref, branch.base_name
  local commits = parse_log(start_log(s.toplevel, range_of(s)):wait())
  if not commits then
    return false, "git log failed for " .. range_of(s)
  end
  s.commits = commits
  return true
end

---Keeps a commit in the panel unless hiding is on and all its files are marked.
---@param s BranchReview
local function panel_filter(s)
  if not s.hide then
    return nil
  end
  count_reviewed(s.toplevel, s.commits)
  local reviewed = {}
  for _, c in ipairs(s.commits) do
    reviewed[c.hash] = #c.keys > 0 and c.done == #c.keys
  end
  return function(entry)
    return not reviewed[entry.commit.hash]
  end
end

---Reloads the panel showing `s` in place, after load() has updated it.
---@param s BranchReview
---@param msg? string  notified when the reload finishes
local function reload(s, msg)
  local view = require("diffview.lib").get_current_view()
  local panel = view and view.panel
  if not (panel and panel.log_options) or panel.updating or panel.bufid ~= s.buf then
    return
  end
  s.busy = true
  panel_ui.reload_in_place(view, range_of(s), function(err)
    s.busy = false
    if err then
      vim.notify("Branch review: " .. err, vim.log.levels.ERROR)
      return
    end
    update_winbar(s)
    if msg then
      vim.notify(msg, vim.log.levels.INFO)
    end
  end, {
    title = function()
      return winbar(s)
    end,
    filter = panel_filter(s),
  })
end

---@param s BranchReview
local function summary(s)
  local _, base_name = base_of(s)
  local n = #s.commits
  return ("%s: %d commit%s since %s"):format(s.name, n, n == 1 and "" or "s", base_name)
end

local open_panel

---@param s BranchReview
local function panel_keys(s)
  return {
    r = {
      function()
        if s.busy then
          return
        end
        local before = vim.tbl_map(function(c)
          return c.hash
        end, s.commits)
        local base_before = s.base_ref
        local ok, err = load(s)
        if not ok then
          vim.notify(err, vim.log.levels.WARN)
          return
        end
        local after = vim.tbl_map(function(c)
          return c.hash
        end, s.commits)
        if vim.deep_equal(before, after) and base_before == s.base_ref then
          update_winbar(s)
          vim.notify("No new commits — " .. summary(s), vim.log.levels.INFO)
          return
        end
        reload(s, "Updated — " .. summary(s))
      end,
      "Refresh branch review",
    },
    S = {
      function()
        if s.busy then
          return
        end
        if not s.base_ref then
          vim.notify(s.name .. " isn't stacked on another branch; already showing everything since " .. s.trunk)
          return
        end
        s.stack = not s.stack
        local ok, err = load(s)
        if not ok then
          vim.notify(err, vim.log.levels.WARN)
          return
        end
        reload(s, summary(s))
      end,
      "Toggle own commits / whole stack",
    },
    H = {
      function()
        if s.busy then
          return
        end
        s.hide = not s.hide
        reload(s, s.hide and "Hiding fully reviewed commits" or "Showing all commits")
      end,
      "Hide / show reviewed commits",
    },
    B = {
      function()
        if s.busy then
          return
        end
        M.pick(s.toplevel, function(picked)
          s.ref, s.name, s.stack = picked.ref, picked.name, false
          local ok, err = load(s)
          if not ok then
            vim.notify(err, vim.log.levels.WARN)
            return
          end
          reload(s, summary(s))
        end)
      end,
      "Review another branch",
    },
    D = {
      function()
        local base = base_of(s)
        require("diffview").open({ "-C" .. s.toplevel, base .. "..." .. s.ref })
      end,
      "Whole branch as one diff",
    },
  }
end

---@param s BranchReview
open_panel = function(s)
  require("diffview").file_history(nil, { "-C" .. s.toplevel, "--range=" .. range_of(s) })
  panel_ui.label(function()
    return winbar(s)
  end, panel_keys(s), function(buf, win)
    s.buf, s.win = buf, win
    reviews[buf] = s
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = buf,
      once = true,
      callback = function()
        reviews[buf] = nil
      end,
    })
  end)
  vim.notify(summary(s), vim.log.levels.INFO)
end

review_marks.on_change(function()
  for buf, s in pairs(reviews) do
    if vim.api.nvim_buf_is_valid(buf) then
      update_winbar(s)
    else
      reviews[buf] = nil
    end
  end
end)

---Picker line: current-branch dot, name, base, commit count, progress, age.
local function format_item(item)
  local a = Snacks.picker.util.align
  local ret = {}
  ret[#ret + 1] = { item.current and "● " or "  ", "SnacksPickerGitBranchCurrent" }
  ret[#ret + 1] = { a(item.name, 32, { truncate = true }), "SnacksPickerGitBranch" }
  ret[#ret + 1] = { " " }
  ret[#ret + 1] = { a("← " .. item.base_name, 28, { truncate = true }), "Comment" }
  ret[#ret + 1] = { " " }
  ret[#ret + 1] = { a(("%d commit%s"):format(item.count, item.count == 1 and "" or "s"), 11), "Number" }
  ret[#ret + 1] = { " " }
  local all = item.total > 0 and item.done == item.total
  ret[#ret + 1] = {
    a(all and "✓ reviewed" or ("%d/%d files"):format(item.done, item.total), 14),
    all and "DiagnosticOk" or (item.done > 0 and "DiagnosticWarn" or "Comment"),
  }
  ret[#ret + 1] = { " " }
  ret[#ret + 1] = { item.age, "Comment" }
  return ret
end

---Preview: the branch's commits with per-commit progress, newest first.
---@param commits ReviewCommit[]
local function preview_of(b, commits)
  local lines = {
    ("%s  ←  %s"):format(b.name, b.base_name),
    b.base_ref and ("stacked on %s · %d commits since %s"):format(b.base_name, #b.commits, b.trunk_name)
      or ("%d commits since %s"):format(#b.commits, b.trunk_name),
    "",
  }
  local extmarks = {
    { row = 1, col = 0, end_col = #b.name, hl_group = "Title" },
    { row = 2, col = 0, end_col = #lines[2], hl_group = "Comment" },
  }
  for _, c in ipairs(commits) do
    local all = #c.keys > 0 and c.done == #c.keys
    local mark = all and "✓" or (c.done > 0 and ("%d/%d"):format(c.done, #c.keys) or "○")
    local line = ("%-6s %s  %s  · %s"):format(mark, c.short, c.subject, c.age)
    lines[#lines + 1] = line
    local row = #lines
    extmarks[#extmarks + 1] = {
      row = row,
      col = 0,
      end_col = #mark,
      hl_group = all and "DiagnosticOk" or (c.done > 0 and "DiagnosticWarn" or "Comment"),
    }
    local hash_col = #("%-6s "):format(mark)
    extmarks[#extmarks + 1] = { row = row, col = hash_col, end_col = hash_col + #c.short, hl_group = "Number" }
    local age_col = #line - #c.age
    extmarks[#extmarks + 1] = { row = row, col = age_col, end_col = #line, hl_group = "Comment" }
  end
  return { text = table.concat(lines, "\n"), extmarks = extmarks, loc = false }
end

---Lists branches to review and opens the chosen one. `on_choose`, when given,
---receives the branch instead (the panel's `B` uses it to switch in place).
---@param dir string
---@param on_choose? fun(branch: { ref: string, name: string })
function M.pick(dir, on_choose)
  local toplevel = git(dir, { "rev-parse", "--show-toplevel" })
  if not toplevel then
    vim.notify("Not a git repo: " .. dir, vim.log.levels.ERROR)
    return
  end
  toplevel = vim.trim(toplevel)

  local trunk = find_trunk(toplevel)
  if not trunk then
    vim.notify("No trunk branch (" .. table.concat(TRUNKS, ", ") .. ") in " .. toplevel, vim.log.levels.ERROR)
    return
  end

  local branches = list_branches(toplevel, trunk)
  if #branches == 0 then
    vim.notify("Every local branch is merged into " .. trunk, vim.log.levels.INFO)
    return
  end

  -- Each branch's own commits (since its base), for the counts and the preview.
  local jobs = {}
  for i, b in ipairs(branches) do
    jobs[i] = start_log(toplevel, (b.base_ref or trunk) .. ".." .. b.ref)
  end

  local items = {}
  for i, b in ipairs(branches) do
    local commits = parse_log(jobs[i]:wait()) or {}
    local done, total = count_reviewed(toplevel, commits)
    b.base_name = b.base_name or trunk
    b.trunk_name = trunk
    items[#items + 1] = {
      text = b.name,
      ref = b.ref,
      name = b.name,
      base_name = b.base_name,
      current = b.current,
      count = #commits,
      done = done,
      total = total,
      age = b.age,
      preview = preview_of(b, commits),
    }
  end

  Snacks.picker({
    title = "Branch Review (vs " .. trunk .. ")",
    items = items,
    format = format_item,
    preview = "preview",
    -- Keep the current branch first, then most recently committed.
    sort = { fields = { "score:desc", "idx" } },
    confirm = function(picker, item)
      picker:close()
      if not item then
        return
      end
      if on_choose then
        on_choose(item)
        return
      end
      ---@type BranchReview
      local s = {
        toplevel = toplevel,
        trunk = trunk,
        ref = item.ref,
        name = item.name,
        stack = false,
        hide = false,
        commits = {},
      }
      local ok, err = load(s)
      if not ok then
        vim.notify(err, vim.log.levels.WARN)
        return
      end
      open_panel(s)
    end,
  })
end

return M
