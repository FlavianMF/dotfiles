return {
    {
        "rcarriga/nvim-notify",
        opts = {
            timeout = 10000,
        },
    },
    {
        "nvim-mini/mini.animate",
        event = "VeryLazy",
        opts = function(_, opts)
            opts.scroll = {
                enable = false,
            }
        end,
    },

    {
        "folke/snacks.nvim",
        ---@type snacks.Config
        opts = {
            dashboard = {
                -- your dashboard configuration comes here
                -- or leave it empty to use the default settings
                -- refer to the configuration section below
                preset = {
                    header = [[
███████╗██╗    ██╗   ██╗    ███╗   ██╗██╗   ██╗██╗███╗   ███╗
██╔════╝██║    ██║   ██║    ████╗  ██║██║   ██║██║████╗ ████║
█████╗  ██║    ██║   ██║    ██╔██╗ ██║██║   ██║██║██╔████╔██║
██╔══╝  ██║    ╚██╗ ██╔╝    ██║╚██╗██║╚██╗ ██╔╝██║██║╚██╔╝██║
██║     ███████╗╚████╔╝     ██║ ╚████║ ╚████╔╝ ██║██║ ╚═╝ ██║
╚═╝     ╚══════╝ ╚═══╝      ╚═╝  ╚═══╝  ╚═══╝  ╚═╝╚═╝     ╚═╝
]],
                },
                sections = {
                    { section = "header" },
                    { pane = 2, title = "Sessions", padding = 1 },
                    { pane = 2, section = "projects", padding = 1 },
                    { section = "keys", gap = 1, padding = 1 },
                    {
                        pane = 2,
                        icon = " ",
                        title = "Recent Files",
                        section = "recent_files",
                        indent = 2,
                        padding = 1,
                    },
                    { pane = 2, icon = " ", title = "Projects", section = "projects", indent = 2, padding = 1 },
                    {
                        pane = 2,
                        icon = " ",
                        title = "Git Status",
                        section = "terminal",
                        enabled = function()
                            return Snacks.git.get_root() ~= nil
                        end,
                        cmd = "git status --short --branch --renames",
                        height = 5,
                        padding = 1,
                        ttl = 5 * 60,
                        indent = 3,
                    },
                    { section = "startup" },
                },
            },
        },
    },

    {
        "numToStr/Comment.nvim",
        opts = {
            -- add any options here
        },
    },
    {
        "folke/snacks.nvim",
        opts = {
            lazygit = {
                configure = true, -- set to false to disable automatic theme
            },
        },
    },
}
