return {
  'vimwiki/vimwiki',
  init = function()
    vim.g.vimwiki_list = {
      {
        path = '~/vimwiki/',
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

    -- Set up keymaps
    vim.api.nvim_set_keymap('n', '<leader>ww', ':VimwikiIndex 1<CR>', { noremap = true })
    vim.api.nvim_set_keymap('n', '<leader>ee', ':VimwikiIndex 2<CR>', { noremap = true })
  end,
}
