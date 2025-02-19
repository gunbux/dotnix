return {
  "folke/snacks.nvim",
  opts = {
    image = { enabled = true, inline = true },
  },
  keys = {
    { "<leader>r", LazyVim.pick("grep"), desc = "Ripgrep (Root Dir)" },
    { "<leader>/", LazyVim.pick("files"), desc = "Find Files (Root Dir)" },
    { "<leader><space>", false }
  },
}
