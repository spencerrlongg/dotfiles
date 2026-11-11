-- Rex config. Keys follow ~/.tmux.conf (prefix ctrl+a) so the same fingers work in
-- both; when a tmux binding changes, change it here too. tmux windows are Rex tabs,
-- tmux panes are Rex panes (blocks).

local P = "ctrl+a>"

-- ctrl+a twice sends ctrl+a to the program (tmux: bind C-a send-prefix)
rex.bind(P .. "ctrl+a", "pane.send_key", { key = "ctrl+a" })

-- --- Actions ---------------------------------------------------------------------

-- Show a session by label, optionally on a tab by label. R S W A V below use it, like
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

-- Session menu: ~/.local/bin/rex-session-menu (fzf; j/k move, / searches, 0-9 jump)
-- in a floating pane over the current tab. It closes itself when you pick or press Esc.
rex.action{
  name = "session_menu",
  title = "Session Menu",
  description = "Pick a session or tab with vim keys (j/k, / to search, 0-9 to jump).",
  run = function(ctx)
    local command = { os.getenv("HOME") .. "/.local/bin/rex-session-menu" }
    if ctx.client_id then table.insert(command, ctx.client_id) end
    local _, err = rex.session.new_layer{
      session_id = ctx.session_id,
      bounds = { 0.15, 0.1, 0.7, 0.8 },
      focus = true,
      layout = rex.layout.block{
        flavor = "com.superlogical.terminal.shell",
        -- started directly, skipping the login shell; the script sets its own PATH
        options = { command = command, shell = "none" },
      },
    }
    if err then error(err) end
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
rex.bind(P .. "j", "session_menu")
rex.bind("cmd+k", "session_menu")
rex.bind(P .. "w", "session_menu")                -- tmux: choose-tree -Zw
rex.bind(P .. "s", "session.switch")              -- tmux: choose-tree -Zs (Rex's own picker)
rex.bind(P .. "shift+r", "goto_session", { label = "home" })
rex.bind(P .. "shift+s", "goto_session", { label = "servers" })
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
rex.bind(P .. "shift+7", "client.tab.close")      -- &
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
rex.bind(P .. "shift+;", "client.palette.toggle") -- : (tmux command prompt)
rex.bind(P .. "pageup", "client.scroll.page_up")  -- tmux: copy-mode -u
