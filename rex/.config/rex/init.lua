-- Rex config migrated from tmux, Ghostty and iTerm2 (2026-11-02)

-- tmux (~/.tmux.conf), prefix ctrl+a
rex.bind("ctrl+a>ctrl+a", "pane.send_key", { key = "ctrl+a" })
rex.bind("ctrl+a>shift+r", "session.switch")
rex.bind("ctrl+a>shift+s", "session.switch")
rex.bind("ctrl+a>shift+w", "session.switch")
rex.bind("ctrl+a>shift+a", "session.switch")

-- Ghostty (~/Library/Application Support/com.mitchellh.ghostty/config)
rex.bind("alt+cmd+right", "client.tab.next")
rex.bind("alt+cmd+left", "client.tab.previous")

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
rex.bind("cmd+k", "session_menu")
rex.bind("ctrl+a>j", "session_menu")

-- iTerm2 (GlobalKeyMap)
rex.bind("shift+cmd+left", "client.tab.move", { direction = "backward" })
rex.bind("shift+cmd+right", "client.tab.move", { direction = "forward" })
