return {
  "delphinus/md-render.nvim",
  version = "^3.11.2",
  ft = { "markdown", "vimwiki" },
  cmd = "MdRender",
  keys = {
    { "<leader>ma", "<cmd>MdRender auto toggle<cr>", desc = "Markdown auto render (toggle)" },
    { "<leader>mr", "<cmd>MdRender toggle<cr>", desc = "Markdown source/render (toggle)" },
    { "<leader>ms", "<cmd>vert MdRender split<cr>", desc = "Markdown source/render split" },
    { "<leader>md", "<cmd>MdRender demo<cr>", desc = "Markdown render demo" },
  },
  init = function()
    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("markdown_auto_render", { clear = true }),
      pattern = { "markdown", "vimwiki" },
      callback = function(event)
        -- Wait for lazy loading and file/cursor restoration before swapping buffers.
        vim.schedule(function()
          if vim.api.nvim_get_current_buf() == event.buf and vim.bo[event.buf].buftype == "" then
            vim.cmd("MdRender auto on")
          end
        end)
      end,
    })
  end,
}
