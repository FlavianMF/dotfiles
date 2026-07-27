-- Configure icons for nvim-web-devicons globally
require("nvim-web-devicons").setup({
  override = {
    lua = {
      icon = "󰢱",
      color = "#51a0cf",
      cterm_color = "59",
      name = "Lua"
    },
    py = {
      icon = "󰌠",
      color = "#3776ab",
      cterm_color = "32",
      name = "Python"
    },
    js = {
      icon = "󰌞",
      color = "#f1e05a",
      cterm_color = "185",
      name = "JavaScript"
    },
    ts = {
      icon = "󰛦",
      color = "#3178c6",
      cterm_color = "33",
      name = "TypeScript"
    },
    json = {
      icon = "󰘦",
      color = "#f9de2e",
      cterm_color = "226",
      name = "Json"
    },
    md = {
      icon = "󰍔",
      color = "#519aba",
      cterm_color = "67",
      name = "Markdown"
    },
    c = {
      icon = "󰙱",
      color = "#599eff",
      cterm_color = "111",
      name = "C"
    },
    h = {
      icon = "󰙱",
      color = "#599eff",
      cterm_color = "111",
      name = "Header"
    },
    cpp = {
      icon = "󰙲",
      color = "#004482",
      cterm_color = "24",
      name = "Cpp"
    },
    vim = {
      icon = "󰉢",
      color = "#019833",
      cterm_color = "28",
      name = "Vim"
    },
  },
  default = true,
  strict = false,
})

-- Enable icons globally in vim.fn and vim.g
vim.g.have_nerd_font = true
