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
            { "<c-h>", "<cmd><C-U>TmuxNavigateLeft<cr>", mode = { "n", "i", "t" } },
            { "<c-j>", "<cmd><C-U>TmuxNavigateDown<cr>", mode = { "n", "i", "t" } },
            { "<c-k>", "<cmd><C-U>TmuxNavigateUp<cr>", mode = { "n", "i", "t" } },
            { "<c-l>", "<cmd><C-U>TmuxNavigateRight<cr>", mode = { "n", "i", "t" } },
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
