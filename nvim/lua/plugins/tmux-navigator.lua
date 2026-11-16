local function nav(vim_dir, herdr_dir, tmux_cmd)
    return function()
        if vim.env.TMUX and vim.env.TMUX ~= "" then
            vim.cmd(tmux_cmd)
            return
        end

        local mode = vim.api.nvim_get_mode().mode
        if mode:sub(1, 1) == "t" then
            vim.cmd("stopinsert")
        end

        local win_before = vim.api.nvim_get_current_win()
        vim.cmd("wincmd " .. vim_dir)
        local win_after = vim.api.nvim_get_current_win()

        -- Seamless edge navigation into Herdr panes
        if win_before == win_after and vim.env.HERDR_ENV == "1" then
            vim.fn.system({ "herdr", "pane", "focus", "--direction", herdr_dir, "--current" })
        end
    end
end

return {
    {
        "christoomey/vim-tmux-navigator",
        lazy = false,
        cmd = {
            "TmuxNavigateLeft",
            "TmuxNavigateDown",
            "TmuxNavigateUp",
            "TmuxNavigateRight",
            "TmuxNavigatePrevious",
            "TmuxNavigatorProcessList",
        },
        keys = {
            { "<c-h>", nav("h", "left", "TmuxNavigateLeft"), mode = { "n", "i", "t" }, desc = "Navigate Left (Vim/Tmux/Herdr)" },
            { "<c-j>", nav("j", "down", "TmuxNavigateDown"), mode = { "n", "i", "t" }, desc = "Navigate Down (Vim/Tmux/Herdr)" },
            { "<c-k>", nav("k", "up", "TmuxNavigateUp"), mode = { "n", "i", "t" }, desc = "Navigate Up (Vim/Tmux/Herdr)" },
            { "<c-l>", nav("l", "right", "TmuxNavigateRight"), mode = { "n", "i", "t" }, desc = "Navigate Right (Vim/Tmux/Herdr)" },
        },
        init = function()
            vim.g.tmux_navigator_no_mappings = false
            vim.g.tmux_navigator_save_on_switch = 2
            vim.g.tmux_navigator_disable_when_zoomed = 1
        end,
    },
    {
        "aserowy/tmux.nvim",
        lazy = false,
        config = function()
            require("tmux").setup({
                copy_sync = {
                    enable = true,
                    redirect_to_clipboard = true,
                    sync_clipboard = true,
                    sync_registers = true,
                },
                navigation = {
                    enable_default_keybindings = false,
                },
                resize = {
                    enable_default_keybindings = false,
                },
            })
        end,
    },
}
