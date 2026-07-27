-- vim.cmd.colorscheme("vesper")

-- require("vesper").setup({
--     transparent = false, -- Boolean: Sets the background to transparent
--     italics = {
--         comments = true, -- Boolean: Italicizes comments
--         keywords = true, -- Boolean: Italicizes keywords
--         functions = true, -- Boolean: Italicizes functions
--         strings = true, -- Boolean: Italicizes strings
--         variables = true, -- Boolean: Italicizes variables
--     },
--     overrides = {}, -- A dictionary of group names, can be a function returning a dictionary or a table.
--     palette_overrides = {},
-- })
--
return {
  -- {
  --   "craftzdog/solarized-osaka.nvim",
  --   lazy = false,
  --   priority = 1000,
  --   opts = function()
  --     return {
  --       transparent = true,
  --     }
  --   end,
  -- },
  -- {
  --     "sainnhe/sonokai",
  --     lazy = false,
  --     priority = 1000,
  --     config = function()
  --         -- Optionally configure and load the colorscheme
  --         -- directly inside the plugin declaration.
  --         vim.g.sonokai_enable_italic = true
  --         vim.g.sonokai_style = "andromeda"
  --         vim.g.sonokai_transparent_background = 1
  --         vim.cmd.colorscheme("sonokai")
  --     end,
  -- },
  {
    "loctvl842/monokai-pro.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("monokai-pro").setup({
        transparent_background = true,
        filter = "spectrum",
        background_clear = {
          "telescope",
          "which-key",
          "nvim-tree",
          "bufferline",
          "float_win",
          "renamer",
          "toggleterm",
          "blink",
        },
        override = function()
          return {
            Pmenu = { bg = "NONE" },
            PmenuThumb = { bg = "NONE" },
            BlinkCmpMenu = { bg = "NONE" },
            CursorLine = { bg = "#2d2a2e" },
            LineNr = { fg = "#626262" },
            CursorLineNr = { fg = "#ffd866" },
          }
        end,
      })
      vim.cmd([[colorscheme monokai-pro-spectrum]])
    end,
  },
  { "datsfilipe/vesper.nvim" },
}
