-- Rex config. Keys follow ~/.tmux.conf (prefix ctrl+a) so the same fingers work in
-- both; when a tmux binding changes, change it here too. tmux windows are Rex tabs,
-- tmux panes are Rex panes (blocks).

local P = "ctrl+a>"

-- ctrl+a twice sends ctrl+a to the program (tmux: bind C-a send-prefix)
rex.bind(P .. "ctrl+a", "pane.send_key", { key = "ctrl+a" })

-- --- Actions ---------------------------------------------------------------------

-- Show a session by label, optionally on a tab by label. R W A V below use it, like
-- tmux's switch-client -t home and switch-client -t home:garden.
rex.action{
  name = "goto_session",
  title = "Go to Session by Name",
  description = "Show the session with this label, and the named tab when one is given.",
  args = {
    type = "object",
    properties = { label = { type = "string" }, tab = { type = "string" } },
    required = { "label" },
  },
  run = function(ctx, args)
    for _, s in ipairs(rex.call("session.list").sessions) do
      if s.label == args.label then
        local select = { session_id = s.session_id }
        if args.tab then
          local att = rex.call("session.attach", { session_id = s.session_id })
          for _, w in ipairs(att and att.view and att.view.windows or {}) do
            if w.label == args.tab then select.window_id = w.window_id end
          end
        end
        rex.client.queue("session.select", select)
        return
      end
    end
    error("no session named " .. args.label .. " (rex-start creates it)")
  end,
}

-- --- Floating layers that follow you ------------------------------------------------
-- Rex floating layers belong to one tab. The server panes stay running in a minimized
-- floating layer, and ctrl+a f brings that layer to whichever tab you're on (the
-- programs keep running through the move).

local function leaves(node, out)
  out = out or {}
  if node.block_id then out[#out + 1] = node.block_id end
  if node.split then leaves(node.split.before, out); leaves(node.split.after, out) end
  return out
end

-- Finds the floating layer holding a pane whose label passes match(label), and the
-- tab you're on (the one with ctx.block_id). Returns view info for both.
local function find_layer(ctx, match)
  local sid = ctx.session_id
  local view = rex.call("session.attach", { session_id = sid }).view
  local labels = {}
  for _, b in ipairs(rex.call("session.list_blocks", { session_id = sid }).blocks or {}) do
    labels[b.block_id] = b.label or ""
  end
  local found = {}
  for _, w in ipairs(view.windows or {}) do
    for _, layer in ipairs(w.layers or {}) do
      for _, id in ipairs(leaves(layer.layout)) do
        if id == ctx.block_id then found.cur_win = w end
        if layer.kind == "floating" and match(labels[id] or "") then
          found.layer, found.win, found.block = layer, w, found.block or id
        end
      end
    end
  end
  found.cur_win = found.cur_win or found.win
  return found
end

-- Moves a floating layer's panes to another tab: the first pane goes beside the tab's
-- tiled pane and floats with the same bounds, then the splits are rebuilt around it.
-- Returns the new layer's id.
local function move_layer(sid, layer, win)
  local anchor
  for _, l in ipairs(win.layers or {}) do
    if l.kind == "tiled" then anchor = leaves(l.layout)[1] end
  end
  local first = leaves(layer.layout)[1]
  rex.call("session.move_block", { session_id = sid, block_id = first, anchor_block_id = anchor })
  rex.call("session.float_block", { session_id = sid, block_id = first, bounds = layer.bounds })
  local function rebuild(node)
    if not node.split then return end
    rebuild(node.split.before)
    rex.call("session.move_block", {
      session_id = sid, block_id = leaves(node.split.after)[1],
      anchor_block_id = leaves(node.split.before)[1],
      direction = node.split.direction, ratio = node.split.ratio,
    })
    rebuild(node.split.after)
  end
  rebuild(layer.layout)
  for _, w in ipairs(rex.call("session.view", { session_id = sid }).windows or {}) do
    for _, l in ipairs(w.layers or {}) do
      if l.kind == "floating" then
        for _, id in ipairs(leaves(l.layout)) do
          if id == first then return l.layer_id end
        end
      end
    end
  end
end

local function show_layer(sid, layer_id)
  rex.call("session.set_layer_state", { session_id = sid, layer_id = layer_id, state = "normal", focus = true })
end

-- Server toggle: each project session keeps its dev servers (expo, ngrok, ...) in one
-- floating layer whose panes are labeled "server: NAME". On the layer's own tab the
-- key minimizes or restores it; on another tab it moves the panes over and shows them.
local SERVER_PREFIX = "server:"

rex.action{
  name = "servers_toggle",
  title = "Toggle Servers",
  description = "Show this session's floating server panes over the current tab, or hide them.",
  run = function(ctx)
    local sid = ctx.session_id
    local s = find_layer(ctx, function(label) return label:sub(1, #SERVER_PREFIX) == SERVER_PREFIX end)
    if not s.layer then error("No server panes in this session (labels starting with \"" .. SERVER_PREFIX .. "\")") end
    if s.win.window_id ~= s.cur_win.window_id then
      show_layer(sid, move_layer(sid, s.layer, s.cur_win))
    elseif s.layer.state == "minimized" then
      show_layer(sid, s.layer.layer_id)
    else
      rex.call("session.set_layer_state", { session_id = sid, layer_id = s.layer.layer_id, state = "minimized" })
    end
  end,
}

-- Close Tab, keeping the floats: before closing a tab, move its server layers to the tab before it (or after it, for the first tab) and minimize
-- them. Without this, closing the tab they happen to sit on kills them or turns them
-- into tiled panes that servers_toggle can't find. Closes the tab by ID rather than
-- via client.tab.close, because moving a focused pane makes its new tab active.
local function keeps_floating(label)
  return label:sub(1, #SERVER_PREFIX) == SERVER_PREFIX
end

rex.action{
  name = "tab_close_keep_floats",
  title = "Close Tab (Keep Floating Panes)",
  description = "Close the current tab after moving its server panes to a neighbouring tab.",
  run = function(ctx)
    local sid = ctx.session_id
    if not ctx.block_id then error("No focused pane, so the current tab is unknown") end
    local view = rex.call("session.attach", { session_id = sid }).view
    local labels = {}
    for _, b in ipairs(rex.call("session.list_blocks", { session_id = sid }).blocks or {}) do
      labels[b.block_id] = b.label or ""
    end

    local windows = view.windows or {}
    local cur, idx
    for i, w in ipairs(windows) do
      for _, layer in ipairs(w.layers or {}) do
        for _, id in ipairs(leaves(layer.layout)) do
          if id == ctx.block_id then cur, idx = w, i end
        end
      end
    end
    if not cur then error("Couldn't find the tab holding the focused pane") end

    local target = windows[idx - 1] or windows[idx + 1]
    if target then
      for _, layer in ipairs(cur.layers or {}) do
        if layer.kind == "floating" then
          local keep = false
          for _, id in ipairs(leaves(layer.layout)) do
            if keeps_floating(labels[id] or "") then keep = true end
          end
          if keep then
            local moved = move_layer(sid, layer, target)
            if moved then
              rex.call("session.set_layer_state", { session_id = sid, layer_id = moved, state = "minimized" })
            end
          end
        end
      end
    end

    local _, err = rex.call("session.close_window", { session_id = sid, window_id = cur.window_id })
    if err ~= nil then error(err, 0) end
  end,
}

-- Agent jump (tmux: prefix + N, tmux-agent-notify jump): go to the oldest pane whose
-- agent finished or is waiting for you. Claude Code reports its state to Rex itself
-- (Program Status: working, idle, blocked, error, done). Rex doesn't tell the server
-- which pane you're looking at, so "seen" is tracked here: a report counts as seen
-- once this jump has taken you to it, or when you press the key from that pane. A
-- new report (the agent ran again) makes the pane count again.
local AGENT_SEEN = os.getenv("HOME") .. "/.local/state/rex-agent-seen.json"
local URGENCY = { blocked = 3, error = 2, done = 1, idle = 1 }

rex.action{
  name = "agent_jump",
  title = "Go to Waiting Agent",
  description = "Show the oldest pane whose agent finished or needs input, as tmux's prefix + N does.",
  run = function(ctx)
    local seen = {}
    local f = io.open(AGENT_SEEN)
    if f then
      local ok, t = pcall(rex.json.decode, f:read("*a"))
      f:close()
      if ok and type(t) == "table" then seen = t end
    end

    local T = "com.superlogical.terminal"
    local candidates, alive = {}, {}
    for _, s in ipairs(rex.call("session.list").sessions) do
      local att = rex.call("session.attach", { session_id = s.session_id })
      for _, w in ipairs(att and att.view and att.view.windows or {}) do
        local function walk(node)
          if not node then return end
          if node.block_id then
            local st = rex.block.call(T, "program_status", { session_id = s.session_id, block_id = node.block_id })
            local records = st and st.records or {}
            local busy, best, stamp = false, 0, ""
            for _, r in ipairs(records) do
              if r.state == "working" then busy = true end
              best = math.max(best, URGENCY[r.state] or 0)
              if r.updated_at > stamp then stamp = r.updated_at end
            end
            if #records > 0 then alive[node.block_id] = stamp end
            if not busy and best > 0 then
              candidates[#candidates + 1] = { sid = s.session_id, wid = w.window_id, bid = node.block_id, stamp = stamp }
            end
          end
          if node.split then walk(node.split.before); walk(node.split.after) end
        end
        for _, layer in ipairs(w.layers or {}) do walk(layer.layout) end
      end
    end

    -- The pane you pressed the key in counts as seen
    if ctx.block_id and alive[ctx.block_id] then seen[ctx.block_id] = alive[ctx.block_id] end

    local target
    for _, c in ipairs(candidates) do
      if c.bid ~= ctx.block_id and seen[c.bid] ~= c.stamp and (not target or c.stamp < target.stamp) then
        target = c
      end
    end

    -- Keep only panes that still exist
    local keep = {}
    for bid, stamp in pairs(seen) do if alive[bid] then keep[bid] = stamp end end
    if target then keep[target.bid] = target.stamp end
    f = io.open(AGENT_SEEN, "w")
    if f then f:write(rex.json.encode(keep)); f:close() end

    if not target then error("No agent notifications") end
    rex.call("session.focus_block", { session_id = target.sid, block_id = target.bid })
    rex.client.queue("session.select", { session_id = target.sid, window_id = target.wid })
  end,
}

-- --- Sessions (tmux: switch-client, choose-tree) -----------------------------------
rex.bind(P .. "shift+n", "agent_jump")
-- Rex's own session picker (the custom fzf menu, rex-session-menu, was retired
-- 2026-11-21; it's in git history if it's ever wanted back)
rex.bind(P .. "j", "session.switch")
rex.bind("cmd+k", "session.switch")
rex.bind(P .. "w", "session.switch")              -- tmux: choose-tree -Zw
rex.bind(P .. "s", "session.switch")              -- tmux: choose-tree -Zs (Rex's own picker)
rex.bind(P .. "shift+r", "goto_session", { label = "home" })
rex.bind(P .. "shift+w", "goto_session", { label = "snipe-it" })      -- web
rex.bind(P .. "shift+a", "goto_session", { label = "snipe-mobile" })  -- app
rex.bind(P .. "shift+v", "goto_session", { label = "home", tab = "garden" })  -- showcase
rex.bind(P .. "shift+9", "session.previous")      -- (
rex.bind(P .. "shift+0", "session.next")          -- )
rex.bind(P .. "shift+4", "session.rename")        -- $

-- --- Tabs (tmux windows) -------------------------------------------------------------
-- tmux numbers windows from 0, Rex tabs from 1: ctrl+a 0 is the first tab, as in tmux
for n = 0, 9 do
  rex.bind(P .. n, "client.tab.goto", { index = n + 1 })
end
rex.bind(P .. "n", "client.tab.next")
rex.bind(P .. "p", "client.tab.previous")
rex.bind(P .. "c", "client.tab.new")
rex.bind(P .. ",", "client.tab.rename")
rex.bind(P .. "shift+7", "tab_close_keep_floats") -- & (moves floating panes off first)
rex.bind("alt+cmd+right", "client.tab.next")      -- from Ghostty
rex.bind("alt+cmd+left", "client.tab.previous")
rex.bind("shift+cmd+left", "client.tab.move", { direction = "backward" })  -- from iTerm2
rex.bind("shift+cmd+right", "client.tab.move", { direction = "forward" })

-- --- Panes -----------------------------------------------------------------------------
rex.bind(P .. "shift+5", "pane.split.right")      -- %
rex.bind(P .. "shift+'", "pane.split.down")       -- "
for _, d in ipairs({ "left", "right", "up", "down" }) do
  rex.bind(P .. d, "pane.focus", { direction = d })
end
-- Home row: ctrl+a then ctrl+h/j/k/l (same in .tmux.conf)
rex.bind(P .. "ctrl+h", "pane.focus", { direction = "left" })
rex.bind(P .. "ctrl+j", "pane.focus", { direction = "down" })
rex.bind(P .. "ctrl+k", "pane.focus", { direction = "up" })
rex.bind(P .. "ctrl+l", "pane.focus", { direction = "right" })
rex.bind(P .. "o", "pane.focus_next")
rex.bind(P .. "z", "pane.zoom")
rex.bind(P .. "x", "pane.close")
rex.bind(P .. "shift+1", "pane.move_to_new_tab")  -- ! (break-pane)
-- tmux resizes by cells (C-arrow 1, M-arrow 5); Rex by percent of the split
for _, d in ipairs({ "left", "right", "up", "down" }) do
  rex.bind(P .. "ctrl+" .. d, "pane.resize", { direction = d, amount = 2 })
  rex.bind(P .. "alt+" .. d, "pane.resize", { direction = d, amount = 5 })
end

-- --- Other -----------------------------------------------------------------------------
rex.bind(P .. "f", "servers_toggle")             -- this session's floating servers
rex.bind(P .. "shift+;", "client.palette.toggle") -- : (tmux command prompt)
rex.bind(P .. "[", "pane.copy_mode.enter")       -- tmux: copy-mode
rex.bind(P .. "pageup", "client.scroll.page_up")  -- tmux: copy-mode -u
