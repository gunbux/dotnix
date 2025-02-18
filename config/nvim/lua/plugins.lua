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
    { "catppuccin/nvim", name = "catppuccin", priority = 1000 },
    { 'dense-analysis/ale' },
    { 'easymotion/vim-easymotion' },
    { 'github/copilot.vim' },
    { 'itchyny/lightline.vim',
      init = function()
        vim.g.lightline = { colorscheme = 'catppuccin' }
      end,
    },
    { 'itchyny/calendar.vim' },
    { 'junegunn/goyo.vim' },
    { 'joshuavial/aider.nvim',
      opts = {
        auto_manage_context = true, -- automatically manage buffer context
        default_bindings = true,    -- use default <leader>A keybindings
        debug = false,              -- enable debug logging
      },
    },
    {
      "kdheepak/lazygit.nvim",
      lazy = true,
      cmd = {
          "LazyGit",
          "LazyGitConfig",
          "LazyGitCurrentFile",
          "LazyGitFilter",
          "LazyGitFilterCurrentFile",
      },
      -- optional for floating window border decoration
      dependencies = {
          "nvim-lua/plenary.nvim",
      },
      -- setting the keybinding for LazyGit with 'keys' is recommended in
      -- order to load the plugin when the command is run for the first time
      keys = {
          { "<leader>k", "<cmd>LazyGit<cr>", desc = "LazyGit" }
      }
    },
    { 'lervag/vimtex' },
    { 'mattn/emmet-vim' },
    { 'MeanderingProgrammer/render-markdown.nvim',
      dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.nvim' }, -- if you use the mini.nvim suite
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
    },
    { "mistricky/codesnap.nvim", build = "make" },
    {
      'nvimdev/dashboard-nvim',
      event = 'VimEnter',
      config = function()
        require('dashboard').setup {
          theme = 'hyper'
        }
      end,
      dependencies = { {'nvim-tree/nvim-web-devicons'}}
    },
    { 'neoclide/coc.nvim', branch = 'release' },
    {
    'nvim-telescope/telescope.nvim', tag = '0.1.8',
      dependencies = { 'nvim-lua/plenary.nvim', 'nvim-tree/nvim-web-devicons' }
    },
    { 'preservim/nerdtree' },
    { 'ryanoasis/vim-devicons' },
    { 'Raimondi/delimitMate' },
    { 'tpope/vim-commentary' },
    { 'Vimjas/vim-python-pep8-indent' },
    { 'vimwiki/vimwiki',
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
vim.cmd('colorscheme catppuccin')

