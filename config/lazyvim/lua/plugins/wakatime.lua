-- Use the wakatime-cli that Home Manager pins (modules/home/wakatime.nix).
-- Setting the path also stops vim-wakatime from downloading its own copy.
return {
  'wakatime/vim-wakatime',
  init = function()
    local cli = vim.fn.exepath('wakatime-cli')
    if cli ~= '' then
      vim.g.wakatime_CLIPath = cli
    end
  end,
}
