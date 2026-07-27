-- lua/plugins/treesitter.lua
return {
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate", -- Keep build command, just in case
  opts = function(_, opts)
    opts.ensure_installed = opts.ensure_installed or {}
    -- Ensure jsonc is in the list and force reinstallation
    if not vim.list_contains(opts.ensure_installed, "jsonc") then
      table.insert(opts.ensure_installed, "jsonc")
    end
    if not vim.list_contains(opts.ensure_installed, "c") then
      table.insert(opts.ensure_installed, "c")
    end

    -- Explicitly set parser_install_dir to a known path if not already set by LazyVim
    -- This might help if Neovim is looking in the wrong place
    -- LazyVim typically sets this, but being explicit won't hurt.
    -- Assuming stdpath('data') as the base
    opts.parser_install_dir = opts.parser_install_dir or vim.fn.stdpath('data') .. '/treesitter'

    -- Ensure jsonc is enabled for highlighting
    opts.highlight = opts.highlight or {}
    opts.highlight.enable = true -- Ensure highlighting is enabled
    opts.highlight.additional_languages = opts.highlight.additional_languages or {}
    if not vim.list_contains(opts.highlight.additional_languages, "jsonc") then
      table.insert(opts.highlight.additional_languages, "jsonc")
    end

    -- Ensure jsonc is enabled for incremental selection if it's used
    opts.incremental_selection = opts.incremental_selection or {}
    opts.incremental_selection.enable = opts.incremental_selection.enable or false
    opts.incremental_selection.enabled_filetypes = opts.incremental_selection.enabled_filetypes or {}
    if not vim.list_contains(opts.incremental_selection.enabled_filetypes, "jsonc") then
      table.insert(opts.incremental_selection.enabled_filetypes, "jsonc")
    end

    -- Ensure jsonc is enabled for indent if it's used
    opts.indent = opts.indent or {}
    opts.indent.enable = opts.indent.enable or false
    opts.indent.enabled_filetypes = opts.indent.enabled_filetypes or {}
    if not vim.list_contains(opts.indent.enabled_filetypes, "jsonc") then
      table.insert(opts.indent.enabled_filetypes, "jsonc")
    end

    -- Add this to force re-installation of parsers during build if they are missing or outdated
    -- This essentially makes `build = ":TSUpdate"` more aggressive.
    opts.update_parsers = true
  end,
}