-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.opt.relativenumber = true
vim.opt.number = true
vim.opt.numberwidth = 4
vim.opt.signcolumn = "yes:2"

-- Terminal and visual improvements
vim.opt.termguicolors = true
vim.opt.background = "dark"

-- Icon support
vim.g.have_nerd_font = true

-- Completion and editor
vim.opt.completeopt = "menu,menuone,noselect"
vim.opt.pumblend = 10
vim.opt.winblend = 0

-- Conceal settings
vim.cmd([[
  set conceallevel=0
  set concealcursor=""
]])

-- Improve display
vim.opt.smoothscroll = true
vim.opt.splitkeep = "screen"

-- Status line improvements
vim.opt.laststatus = 3
vim.opt.showcmdloc = "tabline"
