-- Syncs review marks (review_marks.lua) with the "Viewed" checkboxes on the branch's
-- GitHub pull request, for the <leader>gU review panel (branch_review.lua). Only
-- branches with an open PR sync; without one, marks stay local.
--
-- GitHub keeps one Viewed state per file per PR, for the file's latest version, and
-- turns it into DISMISSED when the file changes after it was viewed. Marks here are
-- per file version (blob:path), so a file counts as viewed when its newest version on
-- the branch is marked, the same thing GitHub shows.
--
-- Opening the panel and `r` pull first (a file Viewed on GitHub gets its newest
-- version marked here), then push (marked here but not Viewed there: mark it; Viewed
-- there but unmarked here after the pull: only possible when unmarked by hand, so
-- unmark it there). Marking or unmarking a file pushes right away.
--
-- gh 2.105 has no command for this, so it goes through `gh api graphql`:
-- markFileAsViewed / unmarkFileAsViewed and PullRequestChangedFile.viewerViewedState.
-- Files that only exist in local commits aren't in the PR yet, and are skipped until
-- they're pushed. Uncommitted changes never sync.
local M = {}

local review_marks = require("config.review_marks")

local FILES_QUERY = [[
query($id: ID!, $after: String) {
  node(id: $id) {
    ... on PullRequest {
      files(first: 100, after: $after) {
        nodes { path viewerViewedState }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}]]

local MARK = [[mutation($id: ID!, $path: String!) {
  markFileAsViewed(input: { pullRequestId: $id, path: $path }) { clientMutationId }
}]]

local UNMARK = [[mutation($id: ID!, $path: String!) {
  unmarkFileAsViewed(input: { pullRequestId: $id, path: $path }) { clientMutationId }
}]]

---Runs gh in `cwd`; `cb(stdout|nil, stderr)` on the main loop.
local function gh(cwd, args, cb)
  local cmd = { "gh" }
  vim.list_extend(cmd, args)
  local ok = pcall(vim.system, cmd, { text = true, cwd = cwd }, function(r)
    vim.schedule(function()
      cb(r.code == 0 and r.stdout or nil, r.stderr)
    end)
  end)
  if not ok then
    cb(nil, "gh not found")
  end
end

local function graphql(cwd, query, vars, cb)
  local args = { "api", "graphql", "-f", "query=" .. query }
  -- -f, not -F: -F turns values that look like numbers or booleans into those types,
  -- and a path like "404" must stay a string.
  for k, v in pairs(vars) do
    args[#args + 1] = "-f"
    args[#args + 1] = k .. "=" .. v
  end
  gh(cwd, args, function(out, err)
    local ok, data = pcall(vim.json.decode, out or "")
    if ok and type(data) == "table" and not data.errors then
      cb(data.data)
    else
      cb(nil, (ok and data and data.errors and data.errors[1] and data.errors[1].message) or err)
    end
  end)
end

---The newest review-mark key of every file the branch's commits touch.
---`commits` is newest first, as git log lists them.
---@return table<string, string> path -> key
local function tip_keys(commits)
  local tips = {}
  for _, c in ipairs(commits) do
    for _, key in ipairs(c.keys or {}) do
      local path = key:match("^[^:]+:(.+)$")
      if path and not tips[path] then
        tips[path] = key
      end
    end
  end
  return tips
end

---Every changed file's Viewed state, following pages.
local function fetch_files(cwd, pr_id, cb, acc, after)
  acc = acc or {}
  local vars = { id = pr_id }
  if after then
    vars.after = after
  end
  graphql(cwd, FILES_QUERY, vars, function(data, err)
    local files = data and data.node and data.node.files
    if not files then
      cb(nil, err or "no files in PR")
      return
    end
    for _, f in ipairs(files.nodes or {}) do
      acc[f.path] = f.viewerViewedState
    end
    if files.pageInfo and files.pageInfo.hasNextPage then
      fetch_files(cwd, pr_id, cb, acc, files.pageInfo.endCursor)
    else
      cb(acc)
    end
  end)
end

---Winbar text for the sync state of review `s`, or "" when there's no PR.
---@param s BranchReview
function M.label(s)
  local g = s.gh
  if not (g and g.pr) then
    return ""
  end
  local text = ("PR #%d"):format(g.pr.number)
  if g.busy then
    return "%#Comment#" .. text .. " syncing…%*"
  elseif g.error then
    return "%#DiagnosticError#" .. text .. " sync failed%*"
  end
  return "%#DiagnosticOk#" .. text .. " ⇅%*"
end

---Pushes local marks to the PR's Viewed state, from the last known GitHub state.
---@param s BranchReview
---@param on_update fun()
local function push(s, on_update)
  local g = s.gh
  if not (g and g.pr and g.viewed) then
    return
  end
  local marks = review_marks.marks(s.toplevel)
  local jobs = {}
  for path, key in pairs(tip_keys(s.commits)) do
    local state = g.viewed[path]
    if state then -- in the PR
      local want = marks[key] ~= nil
      if want and state ~= "VIEWED" then
        jobs[#jobs + 1] = { path = path, query = MARK, state = "VIEWED" }
      elseif not want and state == "VIEWED" then
        jobs[#jobs + 1] = { path = path, query = UNMARK, state = "UNVIEWED" }
      end
    end
  end
  if #jobs == 0 then
    return
  end
  local left = #jobs
  g.busy = true
  on_update()
  for _, job in ipairs(jobs) do
    -- Optimistic, so a second toggle before the reply doesn't queue the same change.
    g.viewed[job.path] = job.state
    graphql(s.toplevel, job.query, { id = g.pr.id, path = job.path }, function(_, err)
      if err then
        g.error = err
        g.viewed[job.path] = nil -- unknown now; the next pull settles it
        vim.notify(("GitHub Viewed sync failed for %s: %s"):format(job.path, err), vim.log.levels.WARN)
      end
      left = left - 1
      if left == 0 then
        g.busy = false
        on_update()
      end
    end)
  end
end

---Looks up the branch's PR, pulls GitHub's Viewed state into the marks, then pushes
---local marks out. For opening the panel and `r`.
---@param s BranchReview
---@param on_update fun() redraws the winbar and the panel's markers
function M.sync(s, on_update)
  s.gh = s.gh or {}
  local g = s.gh
  if g.busy then
    return
  end
  g.busy, g.error = true, nil
  gh(s.toplevel, { "pr", "view", s.name, "--json", "id,number,url,state" }, function(out)
    local ok, pr = pcall(vim.json.decode, out or "")
    if not (ok and type(pr) == "table" and pr.id and pr.state == "OPEN") then
      s.gh = {} -- no open PR: marks stay local
      on_update()
      return
    end
    g.pr = pr
    on_update()
    fetch_files(s.toplevel, pr.id, function(viewed, err)
      g.busy = false
      if not viewed then
        g.error = err
        on_update()
        return
      end
      g.viewed = viewed
      local marks = review_marks.marks(s.toplevel)
      local pull = {}
      for path, key in pairs(tip_keys(s.commits)) do
        if viewed[path] == "VIEWED" and not marks[key] then
          pull[#pull + 1] = key
        end
      end
      review_marks.set(s.toplevel, pull)
      on_update()
      push(s, on_update)
    end)
  end)
end

---After a mark changed by hand: push it, if the branch has a PR that's been synced.
---@param s BranchReview
---@param on_update fun()
function M.after_mark(s, on_update)
  if s.gh and s.gh.pr and s.gh.viewed and not s.gh.busy then
    push(s, on_update)
  end
end

return M
