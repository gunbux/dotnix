return {
  "folke/snacks.nvim",
  opts = {
    image = { enabled = true, inline = true },
  },
  keys = {
    { "<leader>t", function() Snacks.terminal() end, desc = "Terminal (cwd)" },
    { "<leader><space>", false },
    { "<leader>uz", false },
  },
}
