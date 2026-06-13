-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.md#yamlls
return {
  settings = {
    yaml = {
      schemas = {
        ['https://json.schemastore.org/kustomization.json'] = 'kustomization.yaml',
        kubernetes = { '*.yaml', '!kustomization.yaml' },
        ['https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json'] = 'docker-compose*.yaml',
      },
      schemaStore = { enable = true },
      validate = true,
      completion = true,
      hover = true,
    },
  },
}
