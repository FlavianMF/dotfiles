-- return {
--     {
--         "https://codeberg.org/esensar/nvim-dev-container",
--         dependencies = "nvim-treesitter/nvim-treesitter",
--         config = function()
--             require("devcontainer").setup({
--                 autocommands = {
--                     init = true,
--                     clean = true,
--                     update = true,
--                 },
--                 attach_mounts = {
--                     neovim_config = {
--                         enabled = true,
--                         options = { "readonly" },
--                     },
--                 },
--             })
--         end,
--     },
-- }
--
return {
  {
    "https://codeberg.org/esensar/nvim-dev-container",
    dependencies = "nvim-treesitter/nvim-treesitter",
  },
}
