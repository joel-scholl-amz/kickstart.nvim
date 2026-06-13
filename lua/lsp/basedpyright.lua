-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.md#basedpyright
-- Auto-discovers .venv in the project root (uv compatible out of the box)
return {
  settings = {
    basedpyright = {
      analysis = {
        autoSearchPaths = true,
        useLibraryCodeForTypes = true,
        diagnosticMode = 'openFilesOnly',
      },
    },
  },
}
