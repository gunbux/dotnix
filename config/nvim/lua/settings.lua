-- Chun's General Neovim Settings
-- Table of Contents
-- 1 - General/Basic Settings
-- 2 - Vim User Interface
-- 3 - Colours and Fonts
-- 4 - Files, backups and undo
-- 5 - Text, tab and indent related
-- 6 - Visual Mode related
-- 7 - Moving around, tabs, windows and buffers
-- 8 - Status Line
--
-- A large part of this vim configuration was taken from amix, brodie, and
-- chrisatmachine.

-- 1. General/Basic Settings
vim.opt.encoding = 'utf-8'
vim.cmd('filetype plugin on')
vim.cmd('filetype indent on')
vim.opt.mouse = 'a'
vim.opt.clipboard:append('unnamedplus')
vim.opt.history = 500
vim.opt.autoread = true
vim.api.nvim_create_autocmd({'FocusGained', 'BufEnter'}, { command = 'checktime' })

-- Remember last edit position
vim.api.nvim_create_autocmd('BufReadPost', {
    callback = function()
        if vim.fn.line("'\"") > 0 and vim.fn.line("'\"") <= vim.fn.line("$") then
            vim.cmd('normal! g`"')
        end
    end,
})

-- Set mapleader
vim.g.mapleader = ' '

-- Quick save/quit options
vim.api.nvim_set_keymap('n', '<leader>w', ':w!<CR>', { noremap = true })
vim.api.nvim_set_keymap('n', '<leader>q', ':wq<CR>', { noremap = true })
vim.api.nvim_set_keymap('n', '<leader>e', ':q!<CR>', { noremap = true })
vim.cmd('cnoremap w!! w !sudo tee %')

-- Remove trailing whitespaces
vim.api.nvim_create_autocmd('BufWritePre', { command = '%s/\\s\\+$//e' })

-- Fix splitting
vim.opt.splitbelow = true
vim.opt.splitright = true

-- 2. Vim User Interface
vim.opt.wildmenu = true
vim.opt.wildmode = { 'longest', 'list', 'full' }
vim.opt.ruler = true
vim.opt.cmdheight = 1
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true
vim.opt.incsearch = true
vim.opt.lazyredraw = true
vim.opt.magic = true
vim.opt.showmatch = true
vim.opt.number = true

-- Center document when entering insert mode
vim.api.nvim_create_autocmd('InsertEnter', { command = 'norm zz' })

-- Goyo plugin settings
vim.g.goyo_width = 100
vim.g.goyo_margin_top = 2
vim.g.goyo_margin_bottom = 2

-- 3. Colours and Fonts
vim.cmd('syntax enable')
vim.opt.termguicolors = true
vim.opt.cursorline = true
vim.opt.cursorcolumn = true

-- 4. Files, Backups, and Undo
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.swapfile = false

-- Persistent undo
vim.opt.undodir = vim.fn.expand('~/.vim_runtime/temp_dirs/undodir')
vim.opt.undofile = true

-- 5. Text, Tab, and Indent Settings
vim.opt.expandtab = true
vim.opt.smarttab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.softtabstop = 2
vim.opt.autoindent = true
vim.opt.smartindent = true
vim.opt.wrap = true
vim.opt.linebreak = true
vim.opt.textwidth = 600

-- 6. Visual Mode Related
vim.api.nvim_set_keymap('v', '*', ':<C-u>call VisualSelection("", "")<CR>/<C-R>=@/<CR><CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('v', '#', ':<C-u>call VisualSelection("", "")<CR>?<C-R>=@/<CR><CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('v', '<', '<gv', { noremap = true })
vim.api.nvim_set_keymap('v', '>', '>gv', { noremap = true })

-- 7. Moving Around, Tabs, Windows, and Buffers
vim.api.nvim_set_keymap('n', '<leader><CR>', ':noh<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>bd', ':Bclose<CR>:tabclose<CR>gT', { noremap = true })
vim.api.nvim_set_keymap('n', '<leader>ba', ':bufdo bd<CR>', { noremap = true })
vim.api.nvim_set_keymap('n', '<leader>l', ':bnext<CR>', { noremap = true })
vim.api.nvim_set_keymap('n', '<leader>h', ':bprevious<CR>', { noremap = true })
vim.api.nvim_set_keymap('n', '<TAB>', ':bnext<CR>', { noremap = true })
vim.api.nvim_set_keymap('n', '<S-TAB>', ':bprevious<CR>', { noremap = true })

-- Window navigation
vim.api.nvim_set_keymap('n', '<C-j>', '<C-W>j', { noremap = true })
vim.api.nvim_set_keymap('n', '<C-k>', '<C-W>k', { noremap = true })
vim.api.nvim_set_keymap('n', '<C-h>', '<C-W>h', { noremap = true })
vim.api.nvim_set_keymap('n', '<C-l>', '<C-W>l', { noremap = true })

-- Resize windows
vim.api.nvim_set_keymap('n', '<M-j>', ':resize -2<CR>', { noremap = true })
vim.api.nvim_set_keymap('n', '<M-k>', ':resize +2<CR>', { noremap = true })
vim.api.nvim_set_keymap('n', '<M-h>', ':vertical resize -2<CR>', { noremap = true })
vim.api.nvim_set_keymap('n', '<M-l>', ':vertical resize +2<CR>', { noremap = true })

-- Tab management
vim.api.nvim_set_keymap('n', '<leader>tn', ':tabnew<CR>', { noremap = true })
vim.api.nvim_set_keymap('n', '<leader>to', ':tabonly<CR>', { noremap = true })
vim.api.nvim_set_keymap('n', '<leader>tc', ':tabclose<CR>', { noremap = true })
vim.api.nvim_set_keymap('n', '<leader>tm', ':tabmove', { noremap = true })

-- Buffer path tabedit
vim.api.nvim_set_keymap('n', '<leader>te', ':tabedit %:p:h<CR>', { noremap = true })
vim.api.nvim_set_keymap('n', '<leader>cd', ':cd %:p:h<CR>:pwd<CR>', { noremap = true })

-- 8. Status Line
vim.opt.laststatus = 2
vim.g.lightline = { colorscheme = 'dracula' }
vim.opt.statusline = [[ %{HasPaste()}%F%m%r%h %w CWD:%r%{getcwd()} Line:%l Column:%c ]]

-- 9. Spell Checking
vim.api.nvim_set_keymap('n', '<leader>ss', ':setlocal spell!<CR>', { noremap = true })

-- 10. Miscellaneous
vim.api.nvim_set_keymap('n', '<leader>n', ':e ~/buffer<CR>', { noremap = true })
vim.api.nvim_set_keymap('n', '<leader>x', ':e ~/buffer.md<CR>', { noremap = true })

-- 11. Helper Functions
function HasPaste()
    return vim.o.paste and 'PASTE MODE  ' or ''
end

