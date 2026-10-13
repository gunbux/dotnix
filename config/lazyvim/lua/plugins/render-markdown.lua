return {
  'MeanderingProgrammer/render-markdown.nvim',
  dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-mini/mini.nvim' }, -- if you use the mini.nvim suite
  ft = { 'markdown', 'vimwiki', 'Avante' },
  opts = {
    file_types = { 'markdown', 'vimwiki', 'Avante' },
    pipe_table = { preset = 'round' },
    checkbox = {
      custom = {
        important = { raw = '[~]', rendered = '󰓎 ', highlight = 'DiagnosticWarn' },
      },
    },
  },
}
