return {
  'MeanderingProgrammer/render-markdown.nvim',
  enabled = false,
  dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-mini/mini.nvim' }, -- if you use the mini.nvim suite
  config = function()
    require('render-markdown').setup({
      file_types = { 'markdown', 'vimwiki' },
      checkbox = {
        custom = {
          important = { raw = '[~]', rendered = '󰓎 ', highlight = 'DiagnosticWarn' },
        },
      }
    })
  end,
  opts = {},
}
