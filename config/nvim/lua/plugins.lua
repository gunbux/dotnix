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
    { 'amix/vim-zenroom2' },
    { 'dense-analysis/ale' },
    { 'dracula/vim', name = 'dracula' },
    { 'easymotion/vim-easymotion' },
    { 'github/copilot.vim' },
    { 'itchyny/lightline.vim' },
    -- { 'itchyny/calendar.vim' },  -- Uncomment if needed
    { 'junegunn/fzf',
      build = function() vim.fn['fzf#install']() end,
    },
    { 'junegunn/fzf.vim' },
    { 'junegunn/goyo.vim' },
    { 'lervag/vimtex' },
    { 'mattn/emmet-vim' },
    { 'MeanderingProgrammer/render-markdown.nvim',
      dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.nvim' }, -- if you use the mini.nvim suite
      config = function()
        require('render-markdown').setup({
          file_types = { 'markdown', 'vimwiki' },
        })
      end,
      ---@module 'render-markdown'
      ---@type render.md.UserConfig
      opts = {},
    },
    { 'neoclide/coc.nvim', branch = 'release' },
    { 'OmniSharp/omnisharp-vim' },
    { 'preservim/nerdtree' },
    { 'Raimondi/delimitMate' },
    { 'ryanoasis/vim-devicons' },
    { 'tpope/vim-commentary' },
    { 'Vimjas/vim-python-pep8-indent' },
    { 'vimwiki/vimwiki',
      init = function()
        vim.g.vimwiki_list = {
          {
            path = '~/vimwiki/',
            syntax = 'markdown',
            ext = '.md'
          }
        }
      end,
    },
    { 'wakatime/vim-wakatime' },
    { 'wuelnerdotexe/vim-astro' },
    { "nvim-treesitter/nvim-treesitter",
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

