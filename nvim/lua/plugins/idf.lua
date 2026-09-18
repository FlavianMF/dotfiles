-- Requires `get_idf` sourced in the shell nvim was launched from (see zsh/.zshrc)
-- `<C-e>b` finds the activation script itself since it spawns a sibling tmux pane
-- (child of the tmux server, not of nvim) that doesn't inherit nvim's env.
--
-- `idf.py build` (<C-e>b) regenera compile_commands.json pra toolchain GCC,
-- que quebra clangd (go-to-def, diagnostics, etc). Rodar <C-e>r (:ESPReconfigure)
-- uma vez após clone novo ou `idf.py set-target` regenera com IDF_TOOLCHAIN=clang.
-- <C-e>i (:ESPInfo) diagnostica se esp-clangd foi achado e qual toolchain o
-- compile_commands.json atual usa.
local function find_idf_activate_script()
  local matches = vim.fn.glob(vim.fn.expand("$HOME/.espressif/tools/activate_idf_*.sh"), false, true)
  return matches[1]
end

-- `:ESPReconfigure`/`:ESPInfo` (<C-e>r/<C-e>i) spawn idf.py themselves via a
-- Snacks terminal/vim.env, inheriting nvim's own process env — unlike <C-e>b's
-- tmux pane, they don't get a fresh shell where get_idf could run. If nvim
-- itself was launched without get_idf sourced, idf.py isn't found. Source the
-- activate script into nvim's own env once, lazily, so they work either way.
local idf_env_ready = false

local function ensure_idf_env()
  if idf_env_ready or vim.env.IDF_PATH then
    idf_env_ready = true
    return
  end

  local activate_script = find_idf_activate_script()
  if not activate_script then
    return
  end

  -- Plain `env`, not `env -0`: nvim's system() swaps NUL and NL bytes in
  -- captured output, so a NUL-separated dump arrives as one giant unsplit
  -- blob here. Newline-separated is what actually survives the round trip.
  local out = vim.fn.system(". " .. vim.fn.shellescape(activate_script) .. " >/dev/null 2>&1 && env")
  if vim.v.shell_error ~= 0 then
    return
  end

  for _, line in ipairs(vim.split(out, "\n", { plain = true })) do
    local key, value = line:match("^([^=]+)=(.*)$")
    if key then
      vim.env[key] = value
    end
  end

  idf_env_ready = true
end

-- Reuse one tmux pane for builds instead of spawning a new one every time,
-- identified by a pane title marker so it survives across window switches.
local IDF_BUILD_PANE_TITLE = "esp-idf-build"

local function find_idf_build_pane()
  local out = vim.fn.system("tmux list-panes -s -F '#{pane_id} #{window_id} #{pane_title}'") .. "\n"
  for pane_id, window_id, title in out:gmatch("(%S+) (%S+) (.-)\n") do
    if title == IDF_BUILD_PANE_TITLE then
      return pane_id, window_id
    end
  end
  return nil
end

local function run_in_idf_build_pane(command)
  local pane_id, window_id = find_idf_build_pane()
  if pane_id then
    vim.fn.system(string.format("tmux select-window -t %s", window_id))
  else
    pane_id = vim.fn.system("tmux split-window -P -F '#{pane_id}'"):gsub("%s+$", "")
    vim.fn.system(string.format("tmux select-pane -t %s -T %s", pane_id, IDF_BUILD_PANE_TITLE))
  end
  vim.fn.system(string.format("tmux send-keys -t %s C-c", pane_id))
  vim.fn.system(string.format("tmux send-keys -t %s %s Enter", pane_id, vim.fn.shellescape(command)))
  vim.fn.system(string.format("tmux select-pane -t %s", pane_id))
end

return {
  {
    "Aietes/esp32.nvim",
    opts = {
      -- custom build dir
      build_dir = "build",
    },
    keys = {
      {
        "<leader>em",
        function()
          require("esp32").pick("monitor")
        end,
        desc = "ESP32: Pick & Monitor",
      },
      {
        "<C-e>b",
        function()
          local activate_script = find_idf_activate_script()
          local command = activate_script and (". " .. activate_script .. " && idf.py build") or "idf.py build"
          if vim.fn.exists("$TMUX") == 1 then
            run_in_idf_build_pane(command)
          else
            -- Fallback for non-tmux environments
            require("esp32").command("build")
          end
        end,
        desc = "IDF: Build Project",
      },
      {
        "<C-e>r",
        function()
          ensure_idf_env()
          require("esp32").reconfigure()
        end,
        desc = "IDF: Reconfigure (regen compile_commands.json p/ clangd)",
      },
      {
        "<C-e>f",
        function()
          require("esp32").command("flash")
        end,
        desc = "IDF: Flash Project",
      },
      {
        "<C-e>m",
        function()
          require("esp32").command("monitor")
        end,
        desc = "IDF: Monitor Device",
      },
      {
        "<C-e>a",
        function()
          require("esp32").command("flash monitor")
        end,
        desc = "IDF: Flash & Monitor",
      },
      {
        "<C-e>c",
        function()
          require("esp32").command("menuconfig")
        end,
        desc = "IDF: Menuconfig",
      },
      {
        "<C-e>x",
        function()
          require("esp32").command("clean")
        end,
        desc = "IDF: Clean Project",
      },
      {
        "<C-e>i",
        function()
          ensure_idf_env()
          require("esp32").info()
        end,
        desc = "IDF: Info (diagnóstico esp-clangd / compile_commands.json)",
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      local esp32 = require("esp32")
      opts.servers = opts.servers or {}
      opts.servers.clangd = esp32.lsp_config()
      return opts
    end,
  },
}
