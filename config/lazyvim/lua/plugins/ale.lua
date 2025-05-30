return {
  'dense-analysis/ale',
  config = function()
    vim.g.ale_fix_on_save = 1
    vim.g.ale_linters = { zig = { 'zls' } }
    vim.g.ale_fixers = { nix = { 'alejandra' }, zig = { 'zigfmt' } }
  end
}
