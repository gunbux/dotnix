return {
  'dense-analysis/ale',
  config = function()
    vim.g.ale_fix_on_save = 1
    vim.g.ale_linters = { zig = { 'zls' }, qml = { 'qmllint' }, rust = {} }
    vim.g.ale_fixers = { nix = { 'alejandra' }, zig = { 'zigfmt' }, qml = { 'qmlfmt' } }
  end
}
