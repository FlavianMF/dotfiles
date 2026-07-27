-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

vim.api.nvim_create_autocmd({ "FileType" }, {
  pattern = { "json", "jsonc" },
  callback = function()
    vim.wo.conceallevel = 0
  end,
})

-- Open dashboard on startup if no file is opened
vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("DashboardAutocmd", { clear = true }),
  callback = function()
    if vim.fn.argc() == 0 and vim.api.nvim_buf_get_name(0) == "" then
      vim.cmd("Dashboard")
    end
  end,
})

-- Autocommand to insert header guard on new C/C++ header files
vim.api.nvim_create_autocmd("BufNewFile", {
  group = vim.api.nvim_create_augroup("HeaderGuardBufNewFile", { clear = true }),
  pattern = { "*.h", "*.hpp", "*.c" },
  callback = function()
    -- Get the file name and convert it to an uppercase include guard style
    local filename = vim.fn.expand("%:t")
    local guard_name = string.gsub(string.upper(filename), "[^0-9a-zA-Z_]", "_") .. "_H"

    -- Insert the header guard content
    vim.api.nvim_buf_set_lines(0, 0, 0, false, {
      "#ifndef " .. guard_name,
      "#define " .. guard_name,
      "",
      "", -- Leave a blank line for content
      "#endif -- " .. guard_name,
    })

    -- Move the cursor to the blank line
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
  end,
})

-- Autocommand to insert header guard on newly opened empty C/C++ header files (e.g., created by an explorer)
vim.api.nvim_create_autocmd("BufReadPost", {
  group = vim.api.nvim_create_augroup("HeaderGuardBufReadPost", { clear = true }),
  pattern = { "*.h", "*.hpp" },
  callback = function()
    -- Check if the buffer is empty (e.g., newly created empty file by an explorer)
    -- Check line count and if the only line is empty
    if vim.api.nvim_buf_line_count(0) == 1 and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "" then
      local filename = vim.fn.expand("%:t")
      local guard_name = string.gsub(string.upper(filename), "[^0-9a-zA-Z_]", "_") .. "__"

      vim.api.nvim_buf_set_lines(0, 0, 0, false, {
        "#ifndef " .. guard_name,
        "#define " .. guard_name,
        "",
        "", -- Leave a blank line for content
        "#endif // " .. guard_name,
      })

      -- Move the cursor to the blank line
      vim.api.nvim_win_set_cursor(0, { 4, 0 })
    end
  end,
})

-- vim.api.nvim_create_autocmd("BufNewFile", {
--   pattern = "*.{h,hpp}",
--   callback = function()
--     local filename = vim.fn.expand("%:t")
--     local guard = filename:gsub("[^A-Za-z0-9]", "_"):upper() .. "_H"
--     local lines = {
--       "#ifndef " .. guard,
--       "#define " .. guard,
--       "",
--       "#endif // " .. guard,
--     }
--     vim.api.nvim_buf_set_lines(0, 0, 0, false, lines)
--     -- Move cursor to line 3
--     vim.api.nvim_win_set_cursor(0, { 3, 0 })
--   end,
-- })
