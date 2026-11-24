-- Finds references to code in text (review-note replies, mostly) and opens them in a
-- new nvim tab, from the local clone rather than a browser.
--
-- Understands, wherever they sit in a line (backticks and Markdown links included):
--   app/Models/Foo.php:42            repo-relative, from the repo the text belongs to
--   app/Models/Foo.php:42-50         a range
--   app/Models/Foo.php#L42-L50       GitHub-style lines
--   ~/dev/snipe-it/app/Foo.php:42    another local clone (absolute or ~)
--   ... @ 2ec387df                   after any of those: that commit's version
--   file:///Users/spencer/...        file URLs (%-encoded), with :N or #LN
--   https://github.com/<owner>/<repo>/blob/<ref>/<path>#L42-L50
--                                    mapped to the clone in ~/dev whose remote is
--                                    owner/repo (or, failing that, named repo)
--
-- A pinned commit (`@ sha`, or a GitHub permalink's sha) opens that commit's version
-- as a read-only buffer, unless the working-tree file is the same, in which case the
-- real file opens (with LSP and everything). The referenced lines are highlighted.
local M = {}

local api = vim.api
local NS = api.nvim_create_namespace("code_refs")

local function exists(path)
  local st = path and vim.uv.fs_stat(path)
  return st and st.type == "file"
end

local function git(dir, args)
  local out = vim.fn.systemlist(vim.list_extend({ "git", "-C", dir }, args))
  return vim.v.shell_error == 0 and out or nil
end

local function url_decode(s)
  return (s:gsub("%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end))
end

-- GitHub owner/repo -> local clone, from the remotes of every repo in ~/dev.
local clones
local function clone_for(owner, repo)
  if not clones then
    clones = { by_full = {}, by_name = {} }
    for _, dir in ipairs(vim.fn.glob(vim.fn.expand("~/dev") .. "/*/.git", false, true)) do
      local root = vim.fs.dirname(dir)
      for _, line in ipairs(git(root, { "remote", "-v" }) or {}) do
        local o, r = line:match("github%.com[:/]([^/%s]+)/([^/%s]-)%.git")
        if not o then
          o, r = line:match("github%.com[:/]([^/%s]+)/([^/%s]+)")
        end
        if o then
          r = r:gsub("/$", "")
          clones.by_full[(o .. "/" .. r):lower()] = clones.by_full[(o .. "/" .. r):lower()] or root
          clones.by_name[r:lower()] = clones.by_name[r:lower()] or root
        end
      end
      local name = vim.fs.basename(root):lower()
      clones.by_name[name] = clones.by_name[name] or root
    end
  end
  return clones.by_full[(owner .. "/" .. repo):lower()] or clones.by_name[repo:lower()]
end

---Splits "path:12-20", "path#L12-L20" or "path" into path, first line, last line.
local function split_lines(s)
  local p, a, b = s:match("^(.-)#L(%d+)%-?L?(%d*)$")
  if not p then
    p, a, b = s:match("^(.-):(%d+)%-?(%d*)$")
  end
  if not p then
    return s
  end
  return p, tonumber(a), tonumber(b)
end

---The git toplevel holding `path`, or nil.
local function toplevel_of(path)
  local out = git(vim.fs.dirname(path), { "rev-parse", "--show-toplevel" })
  return out and out[1]
end

---Resolves one reference string to a location, or nil if it isn't code we have.
---@param text string
---@param toplevel? string repo that relative paths belong to
---@return {path:string, lnum?:integer, last?:integer, rev?:string, root?:string}|nil
function M.resolve(text, toplevel)
  local rev
  local body, sha = text:match("^(.-)%s*@%s*(%x%x%x%x%x%x%x+)$")
  if body then
    text, rev = body, sha
  end

  -- GitHub blob permalink
  local owner, repo, rest = text:match("^https?://github%.com/([^/]+)/([^/]+)/blob/(.+)$")
  if owner then
    local root = clone_for(owner, repo)
    if not root then
      return nil
    end
    rest = url_decode(rest)
    local p, a, b = split_lines(rest)
    -- <ref>/<path>, where the ref itself may contain slashes: drop leading segments
    -- until the rest is a file in the clone.
    local segs = vim.split(p, "/", { plain = true })
    for i = 1, #segs - 1 do
      local rel = table.concat(segs, "/", i + 1)
      local ref = table.concat(segs, "/", 1, i)
      if exists(root .. "/" .. rel) or git(root, { "cat-file", "-e", ref .. ":" .. rel }) then
        local pinned = ref:match("^%x+$") and #ref >= 7 and ref or nil
        return { path = root .. "/" .. rel, lnum = a, last = b, rev = rev or pinned, root = root, rel = rel }
      end
    end
    return nil
  end

  -- file:// URL
  local fpath = text:match("^file://[^/]*(/.+)$")
  if fpath then
    text = url_decode(fpath)
  end

  local p, a, b = split_lines(text)
  p = p:gsub("^~", vim.env.HOME)
  local full
  if p:sub(1, 1) == "/" then
    full = p
  elseif toplevel then
    full = toplevel .. "/" .. p
  end
  if not full or not exists(full) then
    return nil
  end
  full = vim.fs.normalize(full)
  local root = (toplevel and full:sub(1, #toplevel + 1) == toplevel .. "/") and toplevel or toplevel_of(full)
  local rel = root and full:sub(#root + 2)
  return { path = full, lnum = a, last = b, rev = rev, root = root, rel = rel }
end

---Every code reference in `line`, as { s, e (1-based byte columns), loc }.
---@param line string
---@param toplevel? string
function M.find(line, toplevel)
  local refs, taken = {}, {}
  local function free(s, e)
    for _, r in ipairs(taken) do
      if s <= r[2] and e >= r[1] then
        return false
      end
    end
    return true
  end
  local function add(s, e, target)
    if not free(s, e) then
      return
    end
    -- A trailing " @ <sha>" belongs to the reference.
    local tail = line:sub(e + 1):match("^%s*@%s*%x%x%x%x%x%x%x+")
    if tail then
      target = target .. tail
      e = e + #tail
    end
    local loc = M.resolve(target, toplevel)
    if loc then
      table.insert(refs, { s = s, e = e, loc = loc })
      table.insert(taken, { s, e })
    end
  end

  -- [text](target): the whole link opens the target.
  for s, target, e in line:gmatch("()%[[^%]]*%]%(([^%)%s]+)%)()") do
    add(s, e - 1, target)
  end
  -- Bare URLs (stop at characters that close Markdown or prose around them).
  for s, url, e in line:gmatch("()(%a[%w+.-]*://[^%s%)>%]`\"']+)()") do
    add(s, e - 1, (url:gsub("[.,;:]+$", "")))
  end
  -- Paths: runs of anything but whitespace, quotes and backticks, with trailing
  -- punctuation dropped. Paths may contain ( ) [ ] , (Expo Router routes do).
  for s, tok in line:gmatch("()([^%s`\"'<>]+)") do
    if tok:find("/") or tok:find("%.%w+:%d") or tok:find("%.%w+#L%d") then
      -- Try the token as is, then without the prose around it: a leading "(" and
      -- trailing ")" or punctuation. The first variant that resolves wins.
      local done = false
      for _, lead in ipairs({ 0, 1 }) do
        if not done and (lead == 0 or tok:sub(1, 1) == "(") then
          local t = tok:sub(lead + 1)
          for _, cut in ipairs({ "", "[.,;:!?]+$", "[.,;:!?%)]+$" }) do
            local v = cut == "" and t or t:gsub(cut, "")
            if not done and v ~= "" and free(s + lead, s + lead + #v - 1) then
              local before = #refs
              add(s + lead, s + lead + #v - 1, v)
              done = #refs > before
            end
          end
        end
      end
    end
  end
  table.sort(refs, function(x, y)
    return x.s < y.s
  end)
  return refs
end

---Opens a resolved location in a new tab.
function M.open(loc)
  local use_file = true
  if loc.rev and loc.root and loc.rel then
    -- The pinned version, unless the working tree still matches it.
    if not git(loc.root, { "diff", "--quiet", loc.rev, "--", loc.rel }) then
      local content = git(loc.root, { "show", loc.rev .. ":" .. loc.rel })
      if content then
        use_file = false
        vim.cmd.tabnew()
        local buf = api.nvim_get_current_buf()
        local name = ("%s@%s/%s"):format(vim.fs.basename(loc.root), loc.rev:sub(1, 8), loc.rel)
        pcall(api.nvim_buf_set_name, buf, name)
        api.nvim_buf_set_lines(buf, 0, -1, false, content)
        vim.bo[buf].buftype = "nofile"
        vim.bo[buf].bufhidden = "wipe"
        vim.bo[buf].modifiable = false
        vim.bo[buf].filetype = vim.filetype.match({ filename = loc.path }) or ""
      end
    end
  end
  if use_file then
    vim.cmd.tabedit(vim.fn.fnameescape(loc.path))
  end
  local buf = api.nvim_get_current_buf()
  if loc.lnum then
    local last = math.max(loc.last or loc.lnum, loc.lnum)
    local count = api.nvim_buf_line_count(buf)
    pcall(api.nvim_win_set_cursor, 0, { math.min(loc.lnum, count), 0 })
    api.nvim_buf_clear_namespace(buf, NS, 0, -1)
    for l = loc.lnum, math.min(last, count) do
      api.nvim_buf_set_extmark(buf, NS, l - 1, 0, { line_hl_group = "Visual", priority = 10 })
    end
    vim.cmd("normal! zz")
    -- The highlight is for finding the lines; clear it on the first edit.
    api.nvim_create_autocmd({ "TextChanged", "InsertEnter" }, {
      buffer = buf,
      once = true,
      callback = function()
        pcall(api.nvim_buf_clear_namespace, buf, NS, 0, -1)
      end,
    })
  end
end

---The reference under (or else after) the cursor on the current line.
---@param toplevel? string
function M.at_cursor(toplevel)
  local line = api.nvim_get_current_line()
  local col = api.nvim_win_get_cursor(0)[2] + 1
  local refs = M.find(line, toplevel)
  for _, r in ipairs(refs) do
    if col >= r.s and col <= r.e then
      return r.loc
    end
  end
  for _, r in ipairs(refs) do
    if r.s > col then
      return r.loc
    end
  end
  return refs[#refs] and refs[#refs].loc
end

---Underlines every reference in `buf` and returns their positions (0-based rows),
---for <Tab> to step through.
---@param buf integer
---@param toplevel? string
---@param from? integer first 0-based row to scan
function M.mark(buf, toplevel, from)
  local all = {}
  for i, line in ipairs(api.nvim_buf_get_lines(buf, from or 0, -1, false)) do
    local row = (from or 0) + i - 1
    for _, r in ipairs(M.find(line, toplevel)) do
      api.nvim_buf_set_extmark(buf, NS, row, r.s - 1, { end_col = r.e, hl_group = "Underlined" })
      table.insert(all, { row = row, col = r.s - 1 })
    end
  end
  return all
end

return M
