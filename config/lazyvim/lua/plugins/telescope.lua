return {
  "nvim-telescope/telescope.nvim",
  keys = {
    { "<leader>r", LazyVim.pick("live_grep"), desc = "Ripgrep (Root Dir)" },
    { "<leader>/", LazyVim.pick("files"), desc = "Find Files (Root Dir)" },
    { "<leader><space>", false },
  }
}
