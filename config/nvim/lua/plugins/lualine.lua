return {
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    event = "VeryLazy",
    config = function()
      local icons = {
        diagnostics = {
          Error = " ",
          Warn = " ",
          Hint = " ",
          Info = " ",
        },
        git = {
          added = "  ",
          modified = "  ",
          removed = "  ",
        },
      }

      local colors = {
        bg = "#221f22",
        fg = "#fcfcfa",
        yellow = "#ffd866",
        cyan = "#78dce8",
        darkblue = "#221f22",
        green = "#a9dc76",
        orange = "#ff9671",
        violet = "#ab9df2",
        magenta = "#ff5f87",
        blue = "#78dce8",
        red = "#ff6188",
      }

      local conditions = {
        buffer_not_empty = function()
          return vim.fn.empty(vim.fn.expand("%:t")) == 0
        end,
        hide_in_width = function()
          return vim.fn.winwidth(0) > 80
        end,
        check_git_workspace = function()
          local filepath = vim.fn.expand("%:p:h")
          local gitdir = vim.fn.finddir(".git", filepath .. ";")
          return gitdir and #gitdir > 0
        end,
      }

      require("lualine").setup({
        options = {
          icons_enabled = true,
          theme = "monokai-pro",
          component_separators = { left = "", right = "" },
          section_separators = { left = "", right = "" },
          disabled_filetypes = {},
          always_divide_middle = true,
        },
        sections = {
          lualine_a = {
            {
              function()
                return " 󰣇 "
              end,
              padding = 0,
              color = { fg = colors.magenta, bg = colors.darkblue },
              separator = { left = "", right = "" },
            },
          },
          lualine_b = {
            {
              "branch",
              icons_enabled = true,
              icon = "",
              color = { fg = colors.violet, bg = colors.darkblue },
            },
            {
              "diff",
              symbols = icons.git,
              diff_color = {
                added = { fg = colors.green },
                modified = { fg = colors.orange },
                removed = { fg = colors.red },
              },
              cond = conditions.hide_in_width,
            },
          },
          lualine_c = {
            {
              "filename",
              cond = conditions.buffer_not_empty,
              color = { fg = colors.cyan },
              path = 1,
            },
          },
          lualine_x = {
            {
              "diagnostics",
              sources = { "nvim_diagnostic" },
              symbols = icons.diagnostics,
              color_error = colors.red,
              color_warn = colors.yellow,
              color_info = colors.blue,
              color_hint = colors.cyan,
            },
            {
              "encoding",
              cond = conditions.hide_in_width,
              color = { fg = colors.cyan },
            },
            {
              "fileformat",
              symbols = {
                unix = "󰌽",
                dos = " ",
                mac = " ",
              },
              cond = conditions.hide_in_width,
              color = { fg = colors.cyan },
            },
          },
          lualine_y = {
            {
              "filetype",
              icons_enabled = true,
              color = { fg = colors.blue },
            },
          },
          lualine_z = {
            {
              "progress",
              color = { fg = colors.yellow, bg = colors.darkblue },
              separator = { left = "", right = "" },
            },
            {
              "location",
              color = { fg = colors.magenta, bg = colors.darkblue },
              separator = { left = "", right = "" },
            },
          },
        },
        inactive_sections = {
          lualine_a = {},
          lualine_b = {},
          lualine_c = { "filename" },
          lualine_x = { "location" },
          lualine_y = {},
          lualine_z = {},
        },
        tabline = {},
        extensions = { "nvim-tree", "toggleterm" },
      })
    end,
  },
}
