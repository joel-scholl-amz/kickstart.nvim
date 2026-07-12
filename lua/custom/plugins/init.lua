-- You can add your own plugins here or in other files in this directory!
--  I promise not to create any merge conflicts in this directory :)
--
-- See the kickstart.nvim README for more information
return {
  {
    'prismatic-koi/nvim-sops',
    event = 'BufRead',
    opts = {},
    keys = {
      -- { '<leader>ef', vim.cmd.SopsEncrypt, desc = '[E]ncrypt [F]ile' },
      -- { '<leader>df', vim.cmd.SopsDecrypt, desc = '[D]ecrypt [F]ile' },
    },
  },
  {
    'sindrets/diffview.nvim',
    cmd = { 'DiffviewOpen', 'DiffviewFileHistory' },
    opts = {
      enhanced_diff_hl = true,
    },
  },
  {
    'joel-scholl-amz/nvim-k8s-crd',
    event = { 'BufReadPre', 'BufNewFile' },
    dependencies = {
      'neovim/nvim-lspconfig',
      'nvim-lua/plenary.nvim',
    },
    opts = {
      cache_dir = '$HOME/.cache/k8s-schemas/',
      k8s = {
        file_mask = '*.yaml',
      },
    },
  },
  {
    'NeogitOrg/neogit',
    lazy = true,
    dependencies = {
      'nvim-lua/plenary.nvim', -- required
      'sindrets/diffview.nvim', -- optional - Diff integration
      'nvim-telescope/telescope.nvim', -- optional
    },
    cmd = 'Neogit',
    keys = {
      { '<leader>gg', '<cmd>Neogit<cr>', desc = 'Show Neogit UI' },
    },
  },
  { 'christoomey/vim-tmux-navigator' },
  {
    'iamcco/markdown-preview.nvim',
    cmd = { 'MarkdownPreviewToggle', 'MarkdownPreview', 'MarkdownPreviewStop' },
    ft = { 'markdown' },
    keys = {
      { '<leader>mpt', ':MarkdownPreviewToggle<CR>', desc = 'Markdown Preview' },
    },
    build = 'cd app && yarn install',
    config = function()
      vim.g.mkdp_auto_close = 0 -- Don't close preview when switching buffers
      -- vim.g.mkdp_theme = 'dark' -- or 'light'

      -- WSL: the plugin opens the browser by spawning a bare `cmd.exe`, but this
      -- WSL has the Windows PATH append disabled, so `cmd.exe` isn't resolvable
      -- and the spawn fails with ENOENT ("Can not open browser by using cmd.exe").
      -- Bypass the plugin's opener entirely with mkdp_browserfunc and launch Edge
      -- ourselves via its full path.
      if vim.fn.has 'wsl' == 1 then
        local edge = '/mnt/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'
        vim.cmd(string.format(
          [[
          function! OpenMarkdownPreviewWSL(url) abort
            call jobstart([%s, a:url])
          endfunction
        ]],
          vim.fn.string(edge)
        ))
        vim.g.mkdp_browserfunc = 'OpenMarkdownPreviewWSL'
      else
        vim.g.mkdp_browser = 'msedge'
      end
    end,
  },
  {
    'obsidian-nvim/obsidian.nvim',
    version = '*', -- use latest release, remove to use latest commit
    ft = 'markdown',
    keys = {
      {
        '<leader>odl',
        function()
          require 'obsidian' -- ensure the plugin (and global `Obsidian`) is loaded
          local daily = Obsidian.opts.daily_notes
          local notes_dir = vim.fs.joinpath(tostring(Obsidian.workspace.path), daily.folder)
          local today = os.date(daily.date_format) --[[@as string]]

          -- find the most recent daily note file dated before today
          local prev = nil
          if vim.uv.fs_stat(notes_dir) then
            for name, type in vim.fs.dir(notes_dir) do
              local stem = name:match '^(.+)%.md$'
              if type == 'file' and stem and stem < today and (prev == nil or stem > prev) then
                prev = stem
              end
            end
          end

          local prev_win = nil
          if prev then
            vim.cmd('edit ' .. vim.fn.fnameescape(vim.fs.joinpath(notes_dir, prev .. '.md')))
            -- this window stays on the left with the previous note; capture it
            -- before the split so we can preview it later (belowright vsplit
            -- makes the new right window current).
            prev_win = vim.api.nvim_get_current_win()
            vim.cmd 'belowright vsplit'
          end
          -- everything below runs once today's note is actually open in the
          -- right pane. `:Obsidian today` opens the note via vim.schedule (async),
          -- so it lands in whatever window is focused on the *next* tick -- and the
          -- preview step refocuses the left pane first, which is how today's note
          -- ended up on the left. Open it synchronously and continue in a callback.
          local function after_today()
            local today_win = vim.api.nvim_get_current_win()

            -- today's note is the active (right) pane now: pull the sprint tasks
            -- into it (same as <leader>odp). pull() is async but captures this
            -- buffer, so the split preview below updates live when it lands.
            require('custom.polarion_daily').pull()

            -- open a live browser preview (Edge tab) for each pane, so you get one
            -- tab for the previous note and one for today (same as <leader>mpt).
            --
            -- markdown-preview previews whichever buffer is *focused* when it
            -- opens the browser, and the very first preview does that
            -- asynchronously: firing `:MarkdownPreview` only starts its node
            -- server, which then opens the focused buffer once it has fully
            -- initialised. So we focus a pane, fire the preview, and must not move
            -- focus until that pane's tab has actually opened -- otherwise the
            -- server opens the *next* pane's buffer and the first tab is lost.
            --
            -- The reliable "ready" signal is g:mkdp_clients_active (a browser has
            -- connected): the server's RPC channel connects much earlier, before
            -- the server can open anything, so gating on that races and drops a
            -- tab. Once the first tab is up the server is fully ready, so the
            -- remaining pane's preview opens immediately.
            local queue = {}
            if prev_win then
              queue[#queue + 1] = prev_win -- previous note pane (left)
            end
            queue[#queue + 1] = today_win -- today

            local function preview_pane(i)
              local win = queue[i]
              if not win then
                if vim.api.nvim_win_is_valid(today_win) then
                  vim.api.nvim_set_current_win(today_win) -- leave focus on today's note
                end
                return
              end
              if not vim.api.nvim_win_is_valid(win) then
                return preview_pane(i + 1)
              end
              vim.api.nvim_set_current_win(win)
              vim.cmd 'MarkdownPreview'
              -- last pane: server is already up, so its preview opens right away.
              if i == #queue then
                return preview_pane(i + 1)
              end
              -- otherwise wait until this pane's tab has connected before moving
              -- on (cap ~10s so a browser that never connects can't hang us).
              local tries = 0
              local function wait()
                tries = tries + 1
                if (vim.g.mkdp_clients_active or 0) == 1 or tries > 100 then
                  preview_pane(i + 1)
                else
                  vim.defer_fn(wait, 100)
                end
              end
              vim.defer_fn(wait, 100)
            end
            preview_pane(1)
          end

          local daily_note = require('obsidian.daily').today()
          if daily_note then
            if not daily_note:exists() then
              daily_note:write() -- create from template if missing (as `:Obsidian today` does)
            end
            daily_note:open { sync = true, callback = after_today }
          else
            after_today()
          end
        end,
        desc = 'Open daily notes split (previous | today) with previews',
      },
      {
        '<leader>or',
        function()
          require 'obsidian' -- ensure the plugin (and global `Obsidian`) is loaded
          local root = tostring(Obsidian.workspace.path)

          -- recursively collect markdown files with their mtime
          local files = {}
          local md = vim.fs.find(function(n)
            return n:match '%.md$'
          end, { path = root, type = 'file', limit = math.huge })
          for _, abspath in ipairs(md) do
            local stat = vim.uv.fs_stat(abspath)
            if stat then
              table.insert(files, { path = abspath, mtime = stat.mtime.sec })
            end
          end

          -- most recently edited first
          table.sort(files, function(a, b)
            return a.mtime > b.mtime
          end)

          local pickers = require 'telescope.pickers'
          local finders = require 'telescope.finders'
          local conf = require('telescope.config').values
          local entry_display = require 'telescope.pickers.entry_display'

          local displayer = entry_display.create {
            separator = '  ',
            items = { { width = 19 }, { remaining = true } },
          }

          pickers
            .new({}, {
              prompt_title = 'Obsidian — Recently Edited',
              finder = finders.new_table {
                results = files,
                entry_maker = function(entry)
                  local rel = vim.fs.relpath(root, entry.path) or entry.path
                  return {
                    value = entry.path,
                    path = entry.path,
                    ordinal = rel,
                    display = function()
                      return displayer {
                        os.date('%Y-%m-%d %H:%M', entry.mtime),
                        rel,
                      }
                    end,
                  }
                end,
              },
              sorter = conf.generic_sorter {},
              previewer = conf.file_previewer {},
            })
            :find()
        end,
        desc = 'Obsidian recently edited notes',
      },
    },
    ---@module 'obsidian'
    ---@type obsidian.config
    opts = {
      legacy_commands = false, -- this will be removed in the next major release
      ui = { enable = false },
      workspaces = {
        {
          name = 'work',
          path = '/home/schollj/Documents/dev/obsidian-notes',
        },
      },
      -- the Obsidian app's vault root is the Notes/ subfolder of the workspace
      -- path above, so app-relative folders get an extra Notes/ prefix here
      daily_notes = {
        folder = 'Notes/Notes/Team/Scrum/Daily',
        date_format = '%Y-%m-%d Daily',
        template = 'Daily Template.md',
        default_tags = {},
      },
      templates = {
        folder = 'Notes/Various/Templates',
      },
      frontmatter = {
        -- app-created daily notes carry no frontmatter; keep new ones consistent
        enabled = function(fname)
          return not (fname and fname:match 'Team/Scrum/Daily')
        end,
      },
    },
  },
  {
    'joel-scholl-amz/obsidian-tasks.nvim',
    -- dir is the plugin's source location; the vault path is configured
    -- in obsidian.nvim's workspaces above
    -- dir = '~/Documents/dev/obsidian-tasks.nvim',
    cmd = 'ObsidianTasks',
    keys = {
      { '<leader>oo', '<cmd>ObsidianTasks<cr>', desc = 'Obsidian task board' },
    },
    dependencies = { 'obsidian-nvim/obsidian.nvim' },
    -- everything in opts is passed to the plugin's setup();
    -- fields outside opts are lazy.nvim spec fields and reach the plugin only if lazy knows them
    opts = {
      folders = {
        -- vault-relative; empty = scan the whole vault
        include = { 'Notes/ToDos' },
      },
      new_task_file = 'Notes/ToDos/Triage_Todos.md',
      show_filename = true,
      upcoming_days = 7,
      sort = { 'priority', 'due' }, -- primary, secondary; also: "file", "text"
      -- defaults: m = (m)ove to next panel, s/S = (s)elect / clear selection
    },
  },
  {
    'greggh/claude-code.nvim',
    dependencies = {
      'nvim-lua/plenary.nvim', -- Required for git operations
    },
    config = function()
      require('claude-code').setup()
    end,
  },
  {
    'Ramilito/kubectl.nvim',
    opts = {},
    cmd = { 'Kubectl', 'Kubectx', 'Kubens' },
    keys = {
      { '<leader>k', '<cmd>lua require("kubectl").toggle()<cr>' },
      { '<C-k>', '<Plug>(kubectl.kill)', ft = 'k8s_*' },
      { '7', '<Plug>(kubectl.view_nodes)', ft = 'k8s_*' },
      { '8', '<Plug>(kubectl.view_overview)', ft = 'k8s_*' },
      { '<C-t>', '<Plug>(kubectl.view_top)', ft = 'k8s_*' },
    },
  },
  {
    'nosduco/remote-sshfs.nvim',
    dependencies = { 'nvim-telescope/telescope.nvim', 'nvim-lua/plenary.nvim' },
    opts = {},
  },
}
