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
      { '<leader>ef', vim.cmd.SopsEncrypt, desc = '[E]ncrypt [F]ile' },
      { '<leader>df', vim.cmd.SopsDecrypt, desc = '[D]ecrypt [F]ile' },
    },
  },
  {
    'sindrets/diffview.nvim',
    cmd = { 'DiffviewOpen', 'DiffviewFileHistory' },
    opts = {},
  },
}
