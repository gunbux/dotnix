-- Ensure 'lazy.nvim' is installed
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({
        'git',
        'clone',
        '--filter=blob:none',
        'https://github.com/folke/lazy.nvim.git',
        '--branch=stable', -- latest stable release
        lazypath
    })
end
vim.opt.rtp:prepend(lazypath)

-- Configure plugins using lazy.nvim
require('lazy').setup({
    -- Plugin list
    { 'lervag/vimtex' },
    { 'Raimondi/delimitMate' },
    { 'itchyny/lightline.vim' },
    -- { 'liuchengxu/eleline.vim' },  -- Uncomment if needed
    { 'junegunn/goyo.vim' },
    { 'amix/vim-zenroom2' },
    { 'mattn/emmet-vim' },
    { 'preservim/nerdtree' },
    { 'easymotion/vim-easymotion' },
    { 'Vimjas/vim-python-pep8-indent' },
    { 'tpope/vim-commentary' },
    {
        'junegunn/fzf',
        build = function() vim.fn['fzf#install']() end,
    },
    { 'junegunn/fzf.vim' },
    { 'ryanoasis/vim-devicons' },
    { 'wakatime/vim-wakatime' },
    {
      "iamcco/markdown-preview.nvim",
      cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
      ft = { "markdown" },
      build = function() vim.fn["mkdp#util#install"]() end,
    },
    {
    'MeanderingProgrammer/render-markdown.nvim',
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.nvim' }, -- if you use the mini.nvim suite
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.icons' }, -- if you use standalone mini plugins
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' }, -- if you prefer nvim-web-devicons
    ---@module 'render-markdown'
    ---@type render.md.UserConfig
    opts = {},
    },
    { 'dracula/vim', name = 'dracula' },
    { 'github/copilot.vim' },
    { 'vimwiki/vimwiki' },
    -- { 'itchyny/calendar.vim' },  -- Uncomment if needed
    { 'wuelnerdotexe/vim-astro' },
    { 'OmniSharp/omnisharp-vim' },
    { 'dense-analysis/ale' },
    { 'neoclide/coc.nvim', branch = 'release' },
    {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function ()
      local configs = require("nvim-treesitter.configs")

      configs.setup({
          ensure_installed = {
            "astro",
            "bash",
            "c",
            "c_sharp",
            "cmake",
            "cuda",
            "gitcommit",
            "gitignore",
            "go",
            "html",
            "java",
            "javascript",
            "latex",
            "lua",
            "nix",
            "ocaml",
            "query",
            "tmux",
            "typescript",
            "vim",
            "vimdoc",
            "zig" },
          sync_install = false,
          highlight = { enable = true },
          indent = { enable = true },
        })
      end,
    },
})

-- Set the colorscheme
vim.cmd('colorscheme dracula')

