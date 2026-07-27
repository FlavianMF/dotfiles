return {
  {
    "mikavilpas/yazi.nvim",
    event = "VeryLazy",
    -- Optional: configure keymaps or other settings here
    config = function()
      -- set up your configuration here if needed
      -- Example keymap to open Yazi in the current working directory
      vim.api.nvim_set_keymap("n", "<leader>yz", ":Yazi<CR>", { noremap = true, silent = true })
    end,
  },
}
