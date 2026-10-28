return {
  -- Additional treesitter parsers for web/PHP/Laravel development
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      -- Register blade parser (new API: vim.treesitter.language.register or parsers table)
      local ok, parsers = pcall(require, "nvim-treesitter.parsers")
      if ok and parsers.get_parser_configs then
        -- older nvim-treesitter (pre-0.9)
        parsers.get_parser_configs().blade = {
          install_info = {
            url = "https://github.com/EmranMR/tree-sitter-blade",
            files = { "src/parser.c" },
            branch = "main",
          },
          filetype = "blade",
        }
      else
        -- nvim-treesitter 0.9+
        require("nvim-treesitter").define_modules = require("nvim-treesitter").define_modules
        local configs = require("nvim-treesitter.config")
        if configs and configs.add_parser then
          configs.add_parser("blade", {
            install_info = {
              url = "https://github.com/EmranMR/tree-sitter-blade",
              files = { "src/parser.c" },
              branch = "main",
            },
            filetype = "blade",
          })
        end
      end

      -- Filetype detection
      vim.filetype.add({
        pattern = { [".*%.blade%.php"] = "blade" },  -- Laravel Blade
        extension = { js = "javascriptreact" },       -- Expo/RN uses .js with JSX
      })

      vim.list_extend(opts.ensure_installed, {
        "php",
        "phpdoc",
        "html",
        "css",
        "less",          -- snipe-it uses LESS (not SCSS)
        "javascript",
        "typescript",
        "tsx",
        "json",
        "yaml",
        "bash",
        "lua",
        "sql",
        "regex",
        "blade",
        "kotlin",        -- RN native modules (android/)
        "swift",         -- RN native modules (ios/)
      })
    end,
  },

  -- LSP: ensure intelephense (PHP) and other servers are installed
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      vim.list_extend(opts.ensure_installed, {
        "intelephense",       -- PHP LSP
        "kotlin-lsp",         -- Kotlin LSP (JetBrains, ships its own JBR — no JDK needed)
        "prettierd",          -- JS/TS/CSS/HTML formatter
        "eslint_d",           -- JS/TS linter
      })
    end,
  },

  -- Theme: Catppuccin (kept for reference/fallback)
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    opts = {
      flavour = "mocha",
      integrations = {
        neo_tree = true,
        telescope = { enabled = true },
        which_key = true,
        diffview = true,
      },
    },
  },

  -- Theme: Kanagawa — dragon variant closest to JetBrains Dark (neutral warm-dark bg, muted palette)
  {
    "rebelot/kanagawa.nvim",
    priority = 1000,
    opts = {
      theme = "dragon",
    },
  },

  -- Active colorscheme: tokyonight-night (closest color-role match to JetBrains Dark)
  -- Swap to "kanagawa-dragon" if you want a more muted/neutral feel
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "kanagawa-dragon",
    },
  },

  -- Auto-close and rename JSX/HTML tags (essential for React/RN)
  {
    "windwp/nvim-ts-autotag",
    event = "InsertEnter",
    opts = {},
  },

  -- Language servers
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- Disable phpactor — conflicts with intelephense (two PHP LSPs = duplicate errors)
        phpactor = { enabled = false, mason = false, autostart = false },

        -- Laravel LSP (first-party, laravel/lsp on Packagist). Framework-aware:
        -- route names, config keys, view paths, translation strings, middleware.
        -- Runs alongside intelephense, which handles general PHP.
        -- Installed with: composer global require laravel/lsp
        laravel_lsp = {
          mason = false, -- not a mason package; composer-global binary
          cmd = { vim.fn.expand("~/.composer/vendor/bin/laravel-lsp") },
          filetypes = { "php", "blade" },
          -- Only start inside a Laravel project — the server rejects any other root
          root_dir = function(bufnr, on_dir)
            local root = vim.fs.root(bufnr, "artisan")
            if root then
              on_dir(root)
            end
          end,
          init_options = {
            -- Must NOT be "auto": auto probes Herd first via `herd which-php`,
            -- which hangs on this machine, so initialize never returns and the
            -- server never attaches. "local" uses `php` from $PATH (Herd's 8.3).
            phpEnvironment = "local",
          },
        },

        -- Kotlin LSP (JetBrains official, IntelliJ-based). Alpha.
        -- Mason's binary is `intellij-server`, not `kotlin-lsp`.
        kotlin_lsp = {
          mason = false, -- installed via mason.nvim's ensure_installed above
          cmd = { vim.fn.stdpath("data") .. "/mason/bin/intellij-server", "--stdio" },
        },

        -- Swift/ObjC via sourcekit-lsp — ships with the Xcode toolchain,
        -- nothing to install. Also serves the ObjC side of RN native modules.
        sourcekit = {
          mason = false,
          cmd = { "/usr/bin/sourcekit-lsp" },
        },
      },
    },
  },

  -- PHPStan: inline static analysis diagnostics (like PHPStorm's inspections)
  -- Runs on save only (not on every keystroke — PHPStan is slow on large codebases)
  {
    "mfussenegger/nvim-lint",
    opts = function(_, opts)
      opts.linters_by_ft = opts.linters_by_ft or {}
      opts.linters_by_ft.php = { "phpstan" }
    end,
    config = function(_, opts)
      local lint = require("lint")

      -- Prefer vendor/bin/phpstan over global install
      local phpstan = lint.linters.phpstan
      if phpstan then
        local original_cmd = phpstan.cmd
        phpstan.cmd = function()
          local local_bin = vim.fn.getcwd() .. "/vendor/bin/phpstan"
          if vim.fn.filereadable(local_bin) == 1 then
            return local_bin
          end
          return type(original_cmd) == "function" and original_cmd() or original_cmd
        end
      end

      -- markdownlint: use base config from the nvim dir (disables MD013 line-length)
      local mdlint = lint.linters["markdownlint-cli2"]
      if mdlint then
        mdlint.args = { "--config", vim.fn.stdpath("config") .. "/.markdownlint-cli2.yaml", "-" }
      end

      lint.linters_by_ft = vim.tbl_deep_extend("force", lint.linters_by_ft or {}, opts.linters_by_ft)

      -- Lint on save and when opening a file
      vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost" }, {
        callback = function()
          lint.try_lint()
        end,
      })
    end,
  },

  -- diffview: git diff panel (like PHPStorm's Local Changes)
  {
    "sindrets/diffview.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
    opts = {
      -- Vim marks any line missing from the other buffer as DiffAdd, so on the left
      -- (old revision) pane the lines a commit *deleted* come out green. This remaps
      -- the left window's DiffAdd to DiffviewDiffAddAsDelete (red) and dims the ╱
      -- filler rows to Comment gray instead of a red block.
      enhanced_diff_hl = true,
      -- The diff buffers are unlisted, so bufferline shows whatever real file was
      -- last open instead of the file being diffed. Turn on diffview's own winbar
      -- so each pane is titled with its revision and path ("<sha>:path" on the left,
      -- "WORKING TREE - path" or the newer commit on the right).
      view = {
        default = { winbar_info = true },
        file_history = { winbar_info = true },
      },
    },
    config = function(_, opts)
      require("diffview").setup(opts)
      -- Review marks wrap diffview's panel class, so they can only be installed
      -- once it has loaded — requiring the module at startup would pull diffview
      -- out of lazy loading for every session.
      require("config.review_marks").setup()
      require("config.commit_details").setup()
    end,
  },

  -- bufferline: hide the empty "[No Name]" scratch buffer that nvim starts with
  -- when launched without a file argument (every tmux pane here) — it otherwise
  -- lingers as a stray tab once real buffers are open.
  {
    "akinsho/bufferline.nvim",
    opts = {
      options = {
        -- LazyVim sets this false, which hides the whole bar until a second buffer
        -- is open and makes the row appear/disappear as buffers come and go.
        always_show_bufferline = true,
        custom_filter = function(bufnr)
          return vim.api.nvim_buf_get_name(bufnr) ~= "" or vim.bo[bufnr].modified
        end,
      },
      -- the unsaved-buffer dot defaults to the String highlight's fg, which under
      -- Kanagawa Dragon is the same green as string literals. Pin it to carpYellow
      -- so "modified" reads as its own signal instead of matching syntax colors.
      -- fg only: the bg for each tab state is inherited from bufferline's defaults.
      highlights = {
        -- Tabpage indicators (the numbers at the right edge). Kanagawa draws the
        -- *selected* one as #282727 on #181616 — all but invisible — while the
        -- unselected ones get a bright #737C73, so the tabpage you are actually in
        -- reads as the inactive one. Mirror the buffer_selected treatment below.
        tab = { fg = "#625e5a", bg = "#121010" },
        tab_selected = { fg = "#DCD7BA", bg = "#282727", bold = true },
        tab_separator = { fg = "#0D0C0C", bg = "#121010" },
        tab_separator_selected = { fg = "#0D0C0C", bg = "#282727" },

        modified = { fg = "#E6C384" },
        modified_visible = { fg = "#E6C384" },
        modified_selected = { fg = "#E6C384" },

        -- Active tab. By default the selected buffer differs from the rest only by
        -- fg (dragonWhite vs comment gray) on an identical background, which is hard
        -- to pick out in a row of tabs. Give it a lighter block, full-strength text,
        -- and drop the default italic so the name stays crisp.
        buffer_selected = {
          fg = "#DCD7BA",
          bg = "#282727",
          bold = true,
          italic = false,
        },
        -- A buffer carrying a diagnostic has its name drawn with the matching
        -- severity group rather than buffer_selected, and every one of those
        -- defaults to bg = Normal (#181616 under Dragon). On the active tab that
        -- paints the filename onto near-black inside an otherwise #282727 block,
        -- so the name sits in a dark patch with the icon and close button around
        -- it. Match the active background; fg stays at the severity color.
        hint_selected = { bg = "#282727" },
        info_selected = { bg = "#282727" },
        warning_selected = { bg = "#282727" },
        error_selected = { bg = "#282727" },
        -- Same for the indicator text appended after the name. LazyVim only
        -- renders one for errors and warnings, but pin all four so the two that
        -- do show up cannot drift from the tab they sit on.
        hint_diagnostic_selected = { bg = "#282727" },
        info_diagnostic_selected = { bg = "#282727" },
        warning_diagnostic_selected = { bg = "#282727" },
        error_diagnostic_selected = { bg = "#282727" },

        -- The ▎ bar on the left edge of the active tab, in the same crystalBlue
        -- accent used for float borders.
        indicator_selected = {
          fg = "#7E9CD8",
          bg = "#282727",
        },
        -- Push the inactive tabs further down so the contrast with the active one
        -- comes from both directions.
        background = { fg = "#625e5a" },
        buffer_visible = { fg = "#7a8382" },
      },
    },
  },

  -- render-markdown: by default the line under the cursor drops back to raw markdown
  -- (backticks, table pipes) so it can be edited. Turn that off for unlisted buffers,
  -- which covers the <leader>? cheat sheet popup (Snacks.win opens it via bufadd(), which
  -- leaves it unlisted) and LSP hover docs, while files opened for editing keep it.
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = {
      overrides = {
        buflisted = {
          [false] = { anti_conceal = { enabled = false } },
        },
      },
    },
  },

  -- neo-tree: widen the file explorer panel slightly
  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = {
      window = { width = 35 },
      filesystem = {
        filtered_items = {
          visible = true,   -- show hidden files (dimmed), like PHPStorm
          hide_dotfiles = false,
          hide_gitignored = false,
        },
      },
    },
  },

  -- snacks: show hidden and gitignored files (.github, .env, etc.) everywhere,
  -- both in the file explorer (tree view) and the fuzzy finder ("files" picker),
  -- like PHPStorm's project view. Smooth scroll is halved from snacks' default
  -- 200 ms, so jumping to a definition far down a file doesn't drag.
  {
    "folke/snacks.nvim",
    opts = {
      scroll = {
        animate = {
          duration = { step = 10, total = 100 },
        },
      },
      picker = {
        sources = {
          explorer = {
            hidden = true,
            ignored = true,
            -- The sidebar preset defaults to 40 columns with min_width 40, so
            -- min_width has to drop too or the width setting is clamped back up.
            layout = { layout = { width = 32, min_width = 32 } },
          },
          files = {
            hidden = true,
            ignored = true,
          },
        },
      },
    },
  },
}
