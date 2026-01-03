return {
  'vimwiki/vimwiki',
  lazy = true,
  keys = {
    { "<leader>ww", ":VimwikiIndex 1<CR>", desc = "Open life wiki" },
    { "<leader>ee", ":VimwikiIndex 2<CR>", desc = "Open neuro wiki" },
  },
  ft = { "vimwiki", "markdown" },
  init = function()
    vim.g.vimwiki_list = {
      {
        path = '~/vimwiki/work-life/2026',
        syntax = 'markdown',
        ext = '.md'
      },

      {
        path = '~/repo/neuro/',
        syntax = 'markdown',
        ext = '.md'
      }
    }

    -- Register markdown for vimwiki in treesitter
    vim.treesitter.language.register('markdown', 'vimwiki')
  end,
}
