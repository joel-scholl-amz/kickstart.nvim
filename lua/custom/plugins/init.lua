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
      { '<leader>mp', ':MarkdownPreviewToggle<CR>', desc = 'Markdown Preview' },
    },
    build = 'cd app && yarn install',
    config = function()
      vim.g.mkdp_auto_close = 0 -- Don't close preview when switching buffers
      -- vim.g.mkdp_theme = 'dark' -- or 'light'
      -- Browser command for WSL:
      -- vim.g.mkdp_browser = '/mnt/c/Program Files/Google/Chrome/Application/chrome.exe'
      -- Or for Edge:
      -- vim.g.mkdp_browser = '/mnt/c/Windows/System32/cmd.exe /c start msedge'
      vim.g.mkdp_browser = 'firefox'
    end,
  },
  {
    'obsidian-nvim/obsidian.nvim',
    version = '*', -- use latest release, remove to use latest commit
    ft = 'markdown',
    ---@module 'obsidian'
    ---@type obsidian.config
    opts = {
      legacy_commands = false, -- this will be removed in the next major release
      workspaces = {
        {
          name = 'work',
          path = '/mnt/c/users/SchollJ/Documents/notes/obsidian',
        },
        {
          name = 'personal',
          path = '~/vaults/personal',
        },
      },
    },
  },
  {
    'obsidian-tasks.nvim',
    -- dir is the plugin's source location; the vault path is configured
    -- in obsidian.nvim's workspaces above
    dir = '~/Documents/dev/obsidian-tasks.nvim',
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
