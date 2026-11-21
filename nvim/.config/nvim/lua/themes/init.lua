-- Palette-driven colorschemes. Each theme is one JSON file in ~/.config/theme/themes/
-- (the dotfiles `theme` package), shared with Rex/Ghostty, tmux, the session menu,
-- btop and cava through ~/.local/bin/theme. This module turns a palette into Neovim
-- highlights; colors/<id>.lua and lua/lualine/themes/<id>.lua are one-line stubs
-- that call it.
--
-- Which theme: $NVIM_THEME (used for previews), else the id in
-- ~/.config/theme/current (written by `theme set`), else none (LazyVim falls back
-- to kanagawa-dragon). Running nvims follow `theme set` through a file watcher.
local M = {}

local DIR = vim.fn.expand("~/.config/theme")

local function read(path)
  local f = io.open(path)
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

function M.current()
  local env = vim.env.NVIM_THEME
  if env and env ~= "" then return env end
  local id = read(DIR .. "/current")
  id = id and vim.trim(id) or ""
  if id ~= "" and vim.uv.fs_stat(DIR .. "/themes/" .. id .. ".json") then return id end
  return nil
end

local cache = {}
function M.palette(id)
  id = id or vim.g.colors_name
  if not id then return nil end
  if cache[id] then return cache[id] end
  local s = read(DIR .. "/themes/" .. id .. ".json")
  if not s then return nil end
  cache[id] = vim.json.decode(s)
  return cache[id]
end

-- Mix two #rrggbb colors; t = weight of a.
local function hex(c) return tonumber(c:sub(2, 3), 16), tonumber(c:sub(4, 5), 16), tonumber(c:sub(6, 7), 16) end
local function blend(a, b, t)
  local ar, ag, ab = hex(a)
  local br, bg, bb = hex(b)
  return string.format("#%02x%02x%02x", ar * t + br * (1 - t), ag * t + bg * (1 - t), ab * t + bb * (1 - t))
end
M.blend = blend

-- True when the active colorscheme comes from this module.
function M.active()
  local id = vim.g.colors_name
  return id ~= nil and M.palette(id) ~= nil and vim.g.themes_engine == id
end

function M.apply(id)
  local p = M.palette(id)
  if not p then
    vim.notify("theme: no palette named " .. tostring(id), vim.log.levels.ERROR)
    return
  end
  vim.cmd("highlight clear")
  if vim.fn.exists("syntax_on") == 1 then vim.cmd("syntax reset") end
  vim.o.termguicolors = true
  vim.o.background = p.appearance == "light" and "light" or "dark"
  vim.g.colors_name = id
  vim.g.themes_engine = id

  local u, s, d, g = p.ui, p.syntax, p.diag, p.git
  local NONE = "NONE"
  local function tint(c, amt) return blend(c, u.bg, amt or 0.18) end

  local hl = {}
  local function set(name, spec) hl[name] = spec end
  local function link(name, to) hl[name] = { link = to } end

  -- Editor UI. Normal and the panels have no bg so the terminal's glass shows
  -- through; floats keep it clear too and rely on rounded accent borders.
  set("Normal", { fg = u.fg, bg = NONE })
  set("NormalNC", { fg = u.fg_dim, bg = NONE })
  set("NormalFloat", { fg = u.fg, bg = NONE })
  set("FloatBorder", { fg = u.border_hi, bg = NONE })
  set("FloatTitle", { fg = u.border_hi, bg = NONE, bold = true })
  set("FloatFooter", { fg = u.fg_dim, bg = NONE })
  set("Cursor", { fg = u.bg, bg = u.cursor })
  link("lCursor", "Cursor")
  link("TermCursor", "Cursor")
  set("CursorLine", { bg = u.cursorline })
  set("CursorColumn", { bg = u.cursorline })
  set("ColorColumn", { bg = u.cursorline })
  set("CursorLineNr", { fg = u.linenr_cur, bold = true })
  set("LineNr", { fg = u.linenr })
  link("LineNrAbove", "LineNr")
  link("LineNrBelow", "LineNr")
  set("SignColumn", { bg = NONE })
  set("FoldColumn", { fg = u.linenr, bg = NONE })
  set("Folded", { fg = u.fg_dim, bg = u.surface })
  set("Visual", { bg = u.selection })
  set("VisualNOS", { bg = u.selection })
  set("Search", { fg = u.fg_bright, bg = tint(u.accent, 0.35) })
  set("IncSearch", { fg = u.bg, bg = u.accent })
  link("CurSearch", "IncSearch")
  set("Substitute", { fg = u.bg, bg = d.error })
  set("MatchParen", { fg = u.fg_bright, bg = u.surface_hi, bold = true })
  set("NonText", { fg = u.subtle })
  set("Whitespace", { fg = u.subtle })
  set("SpecialKey", { fg = u.subtle })
  set("EndOfBuffer", { fg = u.bg_alt })
  set("Conceal", { fg = u.fg_dim })
  set("Directory", { fg = s.func })
  set("Title", { fg = s.func, bold = true })
  set("ErrorMsg", { fg = d.error })
  set("WarningMsg", { fg = d.warn })
  set("MoreMsg", { fg = u.accent2 })
  set("ModeMsg", { fg = u.fg_dim })
  set("Question", { fg = u.accent })
  set("QuickFixLine", { bg = u.surface_hi })
  set("WinSeparator", { fg = u.border, bg = NONE })
  link("VertSplit", "WinSeparator")
  set("StatusLine", { fg = u.fg, bg = NONE })
  set("StatusLineNC", { fg = u.fg_dim, bg = NONE })
  set("TabLine", { fg = u.fg_dim, bg = u.bg_alt })
  set("TabLineFill", { bg = NONE })
  set("TabLineSel", { fg = u.fg_bright, bg = u.surface_hi, bold = true })
  set("WinBar", { fg = u.fg_dim, bg = NONE })
  set("WinBarNC", { fg = u.linenr, bg = NONE })
  set("Pmenu", { fg = u.fg, bg = u.surface })
  set("PmenuSel", { fg = u.fg_bright, bg = u.selection, bold = true })
  set("PmenuKind", { fg = s.func, bg = u.surface })
  set("PmenuKindSel", { fg = s.func, bg = u.selection })
  set("PmenuExtra", { fg = u.fg_dim, bg = u.surface })
  set("PmenuSbar", { bg = u.surface })
  set("PmenuThumb", { bg = u.surface_hi })
  set("WildMenu", { link = "PmenuSel" })
  set("SpellBad", { undercurl = true, sp = d.error })
  set("SpellCap", { undercurl = true, sp = d.warn })
  set("SpellRare", { undercurl = true, sp = d.info })
  set("SpellLocal", { undercurl = true, sp = d.hint })

  -- Syntax (legacy groups; treesitter links most captures here)
  set("Comment", { fg = s.comment, italic = true })
  set("Constant", { fg = s.constant, italic = true })
  set("String", { fg = s.string })
  set("Character", { fg = s.string })
  set("Number", { fg = s.number })
  set("Float", { fg = s.number })
  set("Boolean", { fg = s.keyword })
  set("Identifier", { fg = s.variable })
  set("Function", { fg = s.func })
  set("Statement", { fg = s.keyword })
  link("Conditional", "Statement")
  link("Repeat", "Statement")
  link("Label", "Statement")
  link("Keyword", "Statement")
  link("Exception", "Statement")
  set("Operator", { fg = s.operator })
  set("PreProc", { fg = s.meta })
  link("Include", "Statement")
  link("Define", "PreProc")
  link("Macro", "PreProc")
  link("PreCondit", "PreProc")
  set("Type", { fg = s.type })
  link("StorageClass", "Statement")
  link("Structure", "Type")
  link("Typedef", "Type")
  set("Special", { fg = s.special })
  set("SpecialChar", { fg = s.escape })
  set("Tag", { fg = s.tag })
  set("Delimiter", { fg = s.punct })
  set("SpecialComment", { fg = s.doc, italic = true })
  set("Debug", { fg = d.warn })
  set("Underlined", { underline = true })
  set("Error", { fg = d.error })
  set("Todo", { fg = s.todo, bold = true, italic = true })

  -- Treesitter
  local ts = {
    ["@variable"] = { fg = s.variable },
    ["@variable.builtin"] = { fg = s.keyword },
    ["@variable.parameter"] = { fg = s.param },
    ["@variable.parameter.builtin"] = { fg = s.keyword },
    ["@variable.member"] = { fg = s.field },
    ["@property"] = { fg = s.field },
    ["@constant"] = { fg = s.constant, italic = true },
    ["@constant.builtin"] = { fg = s.keyword },
    ["@constant.macro"] = { fg = s.meta },
    ["@module"] = { fg = s.namespace },
    ["@module.builtin"] = { fg = s.namespace },
    ["@label"] = { fg = s.meta },
    ["@string"] = { link = "String" },
    ["@string.documentation"] = { fg = s.doc, italic = true },
    ["@string.regexp"] = { fg = s.regex },
    ["@string.escape"] = { fg = s.escape },
    ["@string.special"] = { fg = s.escape },
    ["@string.special.symbol"] = { fg = s.constant },
    ["@string.special.url"] = { fg = u.accent, underline = true },
    ["@string.special.path"] = { fg = s.string },
    ["@character"] = { link = "Character" },
    ["@character.special"] = { fg = s.escape },
    ["@boolean"] = { fg = s.keyword },
    ["@number"] = { link = "Number" },
    ["@number.float"] = { link = "Number" },
    ["@type"] = { fg = s.type },
    ["@type.builtin"] = { fg = s.type_builtin },
    ["@type.definition"] = { fg = s.type },
    ["@attribute"] = { fg = s.meta },
    ["@attribute.builtin"] = { fg = s.meta },
    ["@function"] = { fg = s.func },
    ["@function.builtin"] = { fg = s.method },
    ["@function.call"] = { fg = s.method },
    ["@function.macro"] = { fg = s.meta },
    ["@function.method"] = { fg = s.func },
    ["@function.method.call"] = { fg = s.method },
    ["@constructor"] = { fg = s.type },
    ["@operator"] = { fg = s.operator },
    ["@keyword"] = { fg = s.keyword },
    ["@keyword.coroutine"] = { fg = s.keyword },
    ["@keyword.function"] = { fg = s.keyword },
    ["@keyword.operator"] = { fg = s.keyword },
    ["@keyword.import"] = { fg = s.keyword },
    ["@keyword.type"] = { fg = s.keyword },
    ["@keyword.modifier"] = { fg = s.keyword },
    ["@keyword.repeat"] = { fg = s.keyword },
    ["@keyword.return"] = { fg = s.keyword },
    ["@keyword.debug"] = { fg = d.warn },
    ["@keyword.exception"] = { fg = s.keyword },
    ["@keyword.conditional"] = { fg = s.keyword },
    ["@keyword.directive"] = { fg = s.meta },
    ["@punctuation.delimiter"] = { fg = s.punct },
    ["@punctuation.bracket"] = { fg = s.punct },
    ["@punctuation.special"] = { fg = s.special },
    ["@comment"] = { link = "Comment" },
    ["@comment.documentation"] = { fg = s.doc, italic = true },
    ["@comment.error"] = { fg = d.error, bold = true },
    ["@comment.warning"] = { fg = d.warn, bold = true },
    ["@comment.todo"] = { fg = s.todo, bold = true },
    ["@comment.note"] = { fg = d.info, bold = true },
    ["@markup.strong"] = { bold = true },
    ["@markup.italic"] = { italic = true },
    ["@markup.strikethrough"] = { strikethrough = true },
    ["@markup.underline"] = { underline = true },
    ["@markup.heading"] = { fg = s.func, bold = true },
    ["@markup.heading.1"] = { fg = s.func, bold = true },
    ["@markup.heading.2"] = { fg = s.keyword, bold = true },
    ["@markup.heading.3"] = { fg = s.string, bold = true },
    ["@markup.heading.4"] = { fg = s.field, bold = true },
    ["@markup.heading.5"] = { fg = s.number, bold = true },
    ["@markup.heading.6"] = { fg = s.meta, bold = true },
    ["@markup.quote"] = { fg = u.fg_dim, italic = true },
    ["@markup.math"] = { fg = s.number },
    ["@markup.link"] = { fg = u.accent },
    ["@markup.link.label"] = { fg = s.func },
    ["@markup.link.url"] = { fg = u.accent, underline = true },
    ["@markup.raw"] = { fg = s.string },
    ["@markup.list"] = { fg = s.keyword },
    ["@markup.list.checked"] = { fg = d.ok },
    ["@markup.list.unchecked"] = { fg = u.fg_dim },
    ["@diff.plus"] = { fg = g.add },
    ["@diff.minus"] = { fg = g.delete },
    ["@diff.delta"] = { fg = g.change },
    ["@tag"] = { fg = s.tag },
    ["@tag.builtin"] = { fg = s.tag },
    ["@tag.attribute"] = { fg = s.attribute },
    ["@tag.delimiter"] = { fg = s.punct },
    -- PHP: $this and variables keep the plain text color like PhpStorm
    ["@variable.builtin.php"] = { fg = s.keyword },
  }
  for k, v in pairs(ts) do hl[k] = v end

  -- LSP semantic tokens
  local lsp = {
    ["@lsp.type.class"] = "@type",
    ["@lsp.type.enum"] = "@type",
    ["@lsp.type.interface"] = "@type",
    ["@lsp.type.struct"] = "@type",
    ["@lsp.type.type"] = "@type",
    ["@lsp.type.typeParameter"] = "@type",
    ["@lsp.type.namespace"] = "@module",
    ["@lsp.type.parameter"] = "@variable.parameter",
    ["@lsp.type.property"] = "@property",
    ["@lsp.type.enumMember"] = "@constant",
    ["@lsp.type.function"] = "@function",
    ["@lsp.type.method"] = "@function.method",
    ["@lsp.type.macro"] = "@function.macro",
    ["@lsp.type.decorator"] = "@attribute",
    ["@lsp.type.keyword"] = "@keyword",
    ["@lsp.type.comment"] = "@comment",
    ["@lsp.typemod.function.defaultLibrary"] = "@function.builtin",
    ["@lsp.typemod.variable.defaultLibrary"] = "@variable.builtin",
    ["@lsp.typemod.variable.readonly"] = "@constant",
  }
  for k, v in pairs(lsp) do hl[k] = { link = v } end
  set("@lsp.type.variable", {}) -- let treesitter decide
  set("@lsp.mod.deprecated", { strikethrough = true })
  set("LspReferenceText", { bg = u.surface_hi })
  set("LspReferenceRead", { bg = u.surface_hi })
  set("LspReferenceWrite", { bg = u.surface_hi, underline = true })
  set("LspInlayHint", { fg = u.linenr, italic = true })
  set("LspCodeLens", { fg = u.linenr })
  set("LspSignatureActiveParameter", { fg = u.accent, bold = true })
  set("LspInfoBorder", { link = "FloatBorder" })

  -- Diagnostics
  for name, c in pairs({ Error = d.error, Warn = d.warn, Info = d.info, Hint = d.hint, Ok = d.ok }) do
    set("Diagnostic" .. name, { fg = c })
    set("DiagnosticVirtualText" .. name, { fg = c, bg = tint(c, 0.10), italic = true })
    set("DiagnosticUnderline" .. name, { undercurl = true, sp = c })
    set("DiagnosticFloating" .. name, { fg = c })
    set("DiagnosticSign" .. name, { fg = c })
  end
  set("DiagnosticUnnecessary", { fg = u.fg_dim })
  set("DiagnosticDeprecated", { strikethrough = true })

  -- Diff and git
  set("DiffAdd", { bg = tint(g.add, 0.16) })
  set("DiffChange", { bg = tint(g.change, 0.12) })
  set("DiffDelete", { fg = tint(g.delete, 0.5), bg = tint(g.delete, 0.12) })
  set("DiffText", { bg = tint(g.change, 0.30) })
  set("Added", { fg = g.add })
  set("Changed", { fg = g.change })
  set("Removed", { fg = g.delete })
  set("diffAdded", { fg = g.add })
  set("diffRemoved", { fg = g.delete })
  set("diffChanged", { fg = g.change })
  set("GitSignsAdd", { fg = g.add })
  set("GitSignsChange", { fg = g.change })
  set("GitSignsDelete", { fg = g.delete })
  set("GitSignsAddInline", { bg = tint(g.add, 0.30) })
  set("GitSignsDeleteInline", { bg = tint(g.delete, 0.30) })
  set("GitSignsChangeInline", { bg = tint(g.change, 0.30) })
  set("GitSignsCurrentLineBlame", { fg = u.linenr, italic = true })
  set("DiffviewFilePanelTitle", { fg = u.accent, bold = true })
  set("DiffviewFilePanelCounter", { fg = s.number })
  set("DiffviewFilePanelFileName", { fg = u.fg })
  set("DiffviewFolderSign", { fg = s.func })
  set("DiffviewNormal", { bg = NONE })
  set("DiffviewStatusAdded", { fg = g.add })
  set("DiffviewStatusModified", { fg = g.change })
  set("DiffviewStatusDeleted", { fg = g.delete })
  set("DiffviewStatusUntracked", { fg = d.ok })
  set("DiffviewDiffDeleteDim", { fg = u.subtle })

  -- Snacks (picker, explorer, dashboard, notifier, indent)
  set("SnacksNormal", { fg = u.fg, bg = NONE })
  set("SnacksNormalNC", { fg = u.fg_dim, bg = NONE })
  set("SnacksWinBar", { fg = u.fg_dim, bg = NONE })
  set("SnacksBackdrop", { bg = u.bg_alt })
  set("SnacksPickerBorder", { fg = u.border_hi, bg = NONE })
  set("SnacksPickerTitle", { fg = u.bg, bg = u.accent, bold = true })
  set("SnacksPickerPrompt", { fg = u.accent })
  set("SnacksPickerMatch", { fg = u.accent, bold = true })
  set("SnacksPickerSelected", { fg = s.keyword })
  set("SnacksPickerCursorLine", { bg = u.surface_hi })
  set("SnacksPickerListCursorLine", { bg = u.surface_hi })
  set("SnacksPickerDir", { fg = u.fg_dim })
  set("SnacksPickerFile", { fg = u.fg })
  set("SnacksPickerTree", { fg = u.subtle })
  set("SnacksPickerGitStatusModified", { fg = g.change })
  set("SnacksPickerGitStatusAdded", { fg = g.add })
  set("SnacksPickerGitStatusUntracked", { fg = d.ok })
  set("SnacksPickerGitStatusDeleted", { fg = g.delete })
  set("SnacksIndent", { fg = u.subtle })
  set("SnacksIndentScope", { fg = u.linenr })
  set("SnacksDashboardHeader", { fg = u.accent })
  set("SnacksDashboardIcon", { fg = s.keyword })
  set("SnacksDashboardKey", { fg = s.string })
  set("SnacksDashboardDesc", { fg = u.fg })
  set("SnacksDashboardFooter", { fg = u.fg_dim })
  set("SnacksDashboardSpecial", { fg = s.field })
  for name, c in pairs({ Info = d.info, Warn = d.warn, Error = d.error, Debug = d.hint, Trace = s.field }) do
    set("SnacksNotifier" .. name, { fg = u.fg, bg = NONE })
    set("SnacksNotifierBorder" .. name, { fg = blend(c, u.bg, 0.6), bg = NONE })
    set("SnacksNotifierIcon" .. name, { fg = c })
    set("SnacksNotifierTitle" .. name, { fg = c, bold = true })
  end

  -- Completion (blink.cmp)
  set("BlinkCmpMenu", { fg = u.fg, bg = u.surface })
  set("BlinkCmpMenuBorder", { fg = u.border, bg = u.surface })
  set("BlinkCmpMenuSelection", { bg = u.selection, bold = true })
  set("BlinkCmpLabelMatch", { fg = u.accent, bold = true })
  set("BlinkCmpLabelDeprecated", { fg = u.fg_dim, strikethrough = true })
  set("BlinkCmpLabelDetail", { fg = u.fg_dim })
  set("BlinkCmpLabelDescription", { fg = u.fg_dim })
  set("BlinkCmpSource", { fg = u.linenr })
  set("BlinkCmpGhostText", { fg = u.linenr, italic = true })
  set("BlinkCmpDoc", { fg = u.fg, bg = u.surface })
  set("BlinkCmpDocBorder", { fg = u.border, bg = u.surface })
  set("BlinkCmpSignatureHelp", { fg = u.fg, bg = u.surface })
  set("BlinkCmpSignatureHelpBorder", { fg = u.border, bg = u.surface })
  local kinds = {
    Text = u.fg, Method = s.func, Function = s.func, Constructor = s.type, Field = s.field,
    Variable = s.variable, Class = s.type, Interface = s.type, Module = s.namespace,
    Property = s.field, Unit = s.number, Value = s.number, Enum = s.type, Keyword = s.keyword,
    Snippet = s.string, Color = s.constant, File = u.fg, Reference = s.field, Folder = s.func,
    EnumMember = s.constant, Constant = s.constant, Struct = s.type, Event = s.meta,
    Operator = s.operator, TypeParameter = s.type, Copilot = u.accent2,
  }
  for k, c in pairs(kinds) do set("BlinkCmpKind" .. k, { fg = c }) end

  -- which-key, noice, flash, trouble, lazy, mason, mini.icons, todo, render-markdown
  set("WhichKey", { fg = s.keyword })
  set("WhichKeyGroup", { fg = s.func })
  set("WhichKeyDesc", { fg = u.fg })
  set("WhichKeySeparator", { fg = u.linenr })
  set("WhichKeyBorder", { fg = u.border_hi, bg = NONE })
  set("WhichKeyNormal", { bg = NONE })
  set("WhichKeyValue", { fg = u.fg_dim })
  set("NoiceCmdlinePopupBorder", { fg = u.border_hi })
  set("NoiceCmdlinePopupTitle", { fg = u.border_hi })
  set("NoiceCmdlineIcon", { fg = u.accent })
  set("NoiceCmdlinePopupBorderSearch", { fg = d.warn })
  set("NoiceCmdlineIconSearch", { fg = d.warn })
  set("NoiceMini", { fg = u.fg_dim, bg = NONE })
  set("FlashLabel", { fg = u.bg, bg = s.tag ~= u.fg and s.tag or u.accent, bold = true })
  set("FlashMatch", { fg = u.fg_bright, bg = u.surface_hi })
  set("FlashCurrent", { fg = u.bg, bg = u.accent2 })
  set("FlashBackdrop", { fg = u.linenr })
  set("TroubleNormal", { bg = NONE })
  set("TroubleNormalNC", { bg = NONE })
  set("LazyNormal", { bg = NONE })
  set("LazyButton", { bg = u.surface })
  set("LazyButtonActive", { fg = u.bg, bg = u.accent, bold = true })
  set("LazyH1", { fg = u.bg, bg = u.accent, bold = true })
  set("LazySpecial", { fg = u.accent })
  set("MasonNormal", { bg = NONE })
  set("MasonHeader", { fg = u.bg, bg = u.accent, bold = true })
  set("MasonHighlight", { fg = u.accent })
  set("MasonHighlightBlock", { fg = u.bg, bg = u.accent })
  set("MasonHighlightBlockBold", { fg = u.bg, bg = u.accent, bold = true })
  set("MiniIconsAzure", { fg = s.func })
  set("MiniIconsBlue", { fg = u.accent })
  set("MiniIconsCyan", { fg = s.number })
  set("MiniIconsGreen", { fg = s.string })
  set("MiniIconsGrey", { fg = u.fg_dim })
  set("MiniIconsOrange", { fg = s.keyword })
  set("MiniIconsPurple", { fg = s.field })
  set("MiniIconsRed", { fg = d.error })
  set("MiniIconsYellow", { fg = s.meta })
  set("TodoBgTODO", { fg = u.bg, bg = s.todo, bold = true })
  set("TodoFgTODO", { fg = s.todo })
  set("RenderMarkdownCode", { bg = u.bg_alt })
  set("RenderMarkdownCodeInline", { fg = s.string, bg = u.surface })
  for i, c in ipairs({ s.func, s.keyword, s.string, s.field, s.number, s.meta }) do
    set("RenderMarkdownH" .. i .. "Bg", { fg = c, bg = tint(c, 0.12), bold = true })
  end
  set("NeoTreeNormal", { bg = NONE })
  set("NeoTreeNormalNC", { bg = NONE })
  set("NeoTreeEndOfBuffer", { bg = NONE })
  set("TelescopeNormal", { bg = NONE })
  set("TelescopeBorder", { fg = u.border_hi, bg = NONE })
  set("TreesitterContext", { bg = u.bg_alt })
  set("TreesitterContextLineNumber", { fg = u.linenr, bg = u.bg_alt })
  set("TreesitterContextBottom", { underline = true, sp = u.border })
  set("IlluminatedWordText", { bg = u.surface_hi })
  set("IlluminatedWordRead", { bg = u.surface_hi })
  set("IlluminatedWordWrite", { bg = u.surface_hi })

  for name, spec in pairs(hl) do vim.api.nvim_set_hl(0, name, spec) end

  for i, c in ipairs(p.ansi) do vim.g["terminal_color_" .. (i - 1)] = c end
end

-- bufferline highlights for the active theme (custom.lua passes this to bufferline
-- as a function, so it re-runs on every ColorScheme). nil when the active scheme
-- isn't from this module.
function M.bufferline()
  if not M.active() then return nil end
  local u, d = M.palette().ui, M.palette().diag
  -- The active tab is a solid accent-tinted block: a plain lighter gray all but
  -- disappears against Rex's glass. Inactive tabs sit on the glass in dim text.
  local sel = blend(u.accent, u.bg, 0.24)
  local h = {
    fill = { bg = "NONE" },
    background = { fg = u.fg_dim, bg = "NONE", italic = false },
    buffer = { fg = u.fg_dim, bg = "NONE", italic = false },
    buffer_visible = { fg = u.fg, bg = "NONE", italic = false },
    buffer_selected = { fg = u.fg_bright, bg = sel, bold = true, italic = false },
    tab = { fg = u.fg_dim, bg = "NONE" },
    tab_selected = { fg = u.fg_bright, bg = sel, bold = true },
    tab_separator = { fg = u.bg_alt, bg = "NONE" },
    tab_separator_selected = { fg = u.bg_alt, bg = sel },
    separator = { fg = u.bg_alt, bg = "NONE" },
    separator_visible = { fg = u.bg_alt, bg = "NONE" },
    separator_selected = { fg = u.bg_alt, bg = sel },
    close_button = { fg = u.linenr, bg = "NONE" },
    close_button_visible = { fg = u.linenr, bg = "NONE" },
    close_button_selected = { fg = u.fg_dim, bg = sel },
    modified = { fg = d.warn, bg = "NONE" },
    modified_visible = { fg = d.warn, bg = "NONE" },
    modified_selected = { fg = d.warn, bg = sel },
    indicator_selected = { fg = u.accent, bg = sel },
    indicator = { fg = u.bg_alt, bg = "NONE" },
    indicator_visible = { fg = u.bg_alt, bg = "NONE" },
    duplicate = { fg = u.linenr, bg = "NONE", italic = true },
    duplicate_selected = { fg = u.fg_dim, bg = sel, italic = true },
    numbers = { fg = u.linenr, bg = "NONE" },
    numbers_selected = { fg = u.fg_dim, bg = sel },
    offset_separator = { fg = u.border, bg = "NONE" },
    trunc_marker = { fg = u.linenr, bg = "NONE" },
  }
  for _, k in ipairs({ "hint", "info", "warning", "error" }) do
    h[k] = { bg = "NONE" }
    h[k .. "_visible"] = { bg = "NONE" }
    h[k .. "_selected"] = { bg = sel, bold = true, italic = false }
    h[k .. "_diagnostic"] = { bg = "NONE" }
    h[k .. "_diagnostic_visible"] = { bg = "NONE" }
    h[k .. "_diagnostic_selected"] = { bg = sel }
  end
  return h
end

-- lualine theme: mode shown as a colored pill, everything else on the glass.
function M.lualine(id)
  local p = M.palette(id or M.current())
  if not p then return "auto" end
  local u, s, d = p.ui, p.syntax, p.diag
  local function mode(c)
    return {
      a = { fg = u.bg, bg = c, gui = "bold" },
      b = { fg = c, bg = u.surface },
      c = { fg = u.fg_dim, bg = "NONE" },
    }
  end
  return {
    normal = mode(u.accent),
    insert = mode(s.string),
    visual = mode(s.field),
    replace = mode(d.error),
    command = mode(s.keyword),
    terminal = mode(s.number),
    inactive = {
      a = { fg = u.fg_dim, bg = "NONE" },
      b = { fg = u.fg_dim, bg = "NONE" },
      c = { fg = u.linenr, bg = "NONE" },
    },
  }
end

-- Follow `theme set` in running nvims: watch ~/.config/theme/current and switch
-- when the id changes. Skipped when $NVIM_THEME pins a theme.
function M.watch()
  if vim.env.NVIM_THEME and vim.env.NVIM_THEME ~= "" then return end
  if M._watcher then return end
  local w = vim.uv.new_fs_event()
  if not w then return end
  M._watcher = w
  local function on_change()
    vim.schedule(function()
      local id = M.current()
      if id and id ~= vim.g.colors_name then
        cache[id] = nil
        vim.cmd.colorscheme(id)
        pcall(function() require("lualine").setup({ options = { theme = M.lualine(id) } }) end)
      elseif not id and M.active() then
        vim.cmd.colorscheme("kanagawa-dragon")
      end
    end)
  end
  -- watch the directory: `theme set` replaces the file, which a file watch would lose
  w:start(DIR, {}, function(err, fname)
    if not err and (fname == "current" or fname == nil) then on_change() end
  end)
end

return M
