return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = {
    window = {
      mappings = {
        -- <C-b> fecha a árvore também dentro dela (o padrão rola o preview)
        ["<C-b>"] = "close_window",
      },
    },
  },
}
