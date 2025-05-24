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
    {
        "yetone/avante.nvim",
        event = "BufReadPre",
        lazy = false,
        enabled = false,
        version = false,
        disable_tools = false,
        config = function()
            require("avante").setup({
                provider = "openrouter",
                vendors = {
                    openrouter = {
                        __inherited_from = "openai",
                        endpoint = "https://openrouter.ai/api/v1",
                        api_key_name = "OPENROUTER_API_KEY",
                        model = "anthropic/claude-sonnet-4",
                        max_tokens = 8192,
                    },
                    openrouter_deepseek = {
                        __inherited_from = "openai",
                        endpoint = "https://openrouter.ai/api/v1",
                        api_key_name = "OPENROUTER_API_KEY",
                        model = "deepseek/deepseek-coder-33b-instruct",
                        max_tokens = 8192,
                    },
                },
                behaviour = {
                    auto_suggestions = false,
                    auto_set_highlight_group = true,
                    auto_set_keymaps = true,
                    auto_apply_diff_after_generation = false,
                    support_paste_from_clipboard = true,
                    minimize_diff = false,
                },
                copilot = {
                    model = "claude-3.5-sonnet",
                    temperature = 0,
                    max_tokens = 8192,
                },
                gemini = {
                    model = "gemini-2.0-flash",
                    temperature = 0,
                    max_tokens = 8192,
                },
            })
        end,
        build = "make",
        dependencies = {
            "stevearc/dressing.nvim",
            "nvim-lua/plenary.nvim",
            "MunifTanjim/nui.nvim",
            --- The below dependencies are optional,
            "echasnovski/mini.pick", -- for file_selector provider mini.pick
            "nvim-telescope/telescope.nvim", -- for file_selector provider telescope
            "hrsh7th/nvim-cmp", -- autocompletion for avante commands and mentions
            "ibhagwan/fzf-lua", -- for file_selector provider fzf
            "nvim-tree/nvim-web-devicons", -- or echasnovski/mini.icons
            "zbirenbaum/copilot.lua", -- for providers='copilot'
            {
                "HakonHarnes/img-clip.nvim",
                event = "VeryLazy",
                opts = {
                    default = {
                        embed_image_as_base64 = false,
                        prompt_for_file_name = false,
                        drag_and_drop = { insert_mode = true },
                        use_absolute_path = true,
                    },
                    keys = {
                        {
                            "<leader>p",
                            "<cmd>ImagePaster<cr>",
                            mode = { "n", "v" },
                        },
                    },
                },
            },
            {
                "MeanderingProgrammer/render-markdown.nvim",
                opts = { file_types = { "Avante" } },
                ft = { "Avante" },
            },
        },
    },
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

