-- Remap 0 to go to the first non-blank character
vim.api.nvim_set_keymap('n', '0', '^', { noremap = true })

-- Escape shortcuts in insert mode
vim.api.nvim_set_keymap('i', 'jk', '<Esc>', { noremap = true })
vim.api.nvim_set_keymap('i', 'kj', '<Esc>', { noremap = true })
vim.api.nvim_set_keymap('i', 'jj', '<Esc>', { noremap = true })
vim.api.nvim_set_keymap('i', 'kk', '<Esc>', { noremap = true })

-- Shell command shortcuts
vim.api.nvim_set_keymap('n', '<leader>d', ':!mkdir ', { noremap = true })
vim.api.nvim_set_keymap('n', '<leader>m', ':!mv % ', { noremap = true })

-- Better split navigation
vim.api.nvim_set_keymap('n', '<C-h>', '<C-w>h', { noremap = true })
vim.api.nvim_set_keymap('n', '<C-j>', '<C-w>j', { noremap = true })
vim.api.nvim_set_keymap('n', '<C-k>', '<C-w>k', { noremap = true })
vim.api.nvim_set_keymap('n', '<C-l>', '<C-w>l', { noremap = true })

-- Calling splits
vim.api.nvim_set_keymap('n', '<leader>h', ':split ', { noremap = true })
vim.api.nvim_set_keymap('n', '<leader>v', ':vsplit ', { noremap = true })

-- Toggle highlighting
vim.api.nvim_set_keymap('n', '<leader>o', ':setlocal nohlsearch<CR>', { noremap = true })

-- Toggle comments
-- Uncomment these if needed
-- vim.api.nvim_set_keymap('n', '<leader>c', ':setlocal formatoptions-=cro<CR>', { noremap = true })
-- vim.api.nvim_set_keymap('n', '<leader>C', ':setlocal formatoptions=cro<CR>', { noremap = true })

-- Plugin Specific Mappings

-- Calendar.vim
-- Enable Google Calendar integration
-- vim.cmd('source ~/.cache/calendar.vim/credentials.vim')
-- vim.g.calendar_google_calendar = 1
--
-- -- Hotkey for opening Calendar in days view, with a vertical split on the right
-- vim.api.nvim_set_keymap('n', '<leader>c', ':Calendar -view=days -split=vertical -position=right<CR>', { noremap = true })
--
-- -- Helper function to prefix a zero to single-digit numbers
-- local function prefix_zero(num)
--     return num < 10 and '0' .. num or tostring(num)
-- end
--
-- -- Callback function for Calendar.vim, integrated with Vimwiki's diary feature
-- function DiaryDay(day, month, year, week, dir, wnum)
--     day = prefix_zero(day)
--     month = prefix_zero(month)
--
--     local link = year .. '-' .. month .. '-' .. day
--     if vim.fn.winnr('#') == 0 then
--         if dir == 'V' then
--             vim.cmd('vsplit')
--         else
--             vim.cmd('split')
--         end
--     else
--         vim.cmd('wincmd p')
--         if not vim.o.hidden and vim.bo.modified then
--             vim.cmd('new')
--         end
--     end
--
--     vim.fn['vimwiki#diary#make_note'](wnum, 0, link)
-- end
--
-- -- Autocommand to bind <CR> to open the diary entry in Calendar.vim
-- vim.cmd([[
--   autocmd FileType calendar nmap <leader><buffer> <CR> :lua DiaryDay(
--     b:calendar.day().get_day(),
--     b:calendar.day().get_month(),
--     b:calendar.day().get_year(),
--     b:calendar.day().week(),
--     "V",
--     v:count1
--   )<CR>
-- ]])


-- nvim-telescope
local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>/', builtin.find_files, { desc = 'Telescope find files' })
vim.keymap.set('n', '<leader>r', builtin.live_grep, { desc = 'Telescope live grep' })

-- RenderMarkdown with vimwiki
vim.treesitter.language.register('markdown', 'vimwiki')

-- Vimwiki settings
vim.api.nvim_set_keymap('n', '<C-Space>', ':VimwikiIndex<CR>', { noremap = true })
vim.api.nvim_set_keymap('n', '<leader>ww', ':VimwikiIndex<CR>', { noremap = true })

-- Copilot settings
vim.api.nvim_set_keymap('i', '<C-Space>', 'copilot#Accept("\\<CR>")', { expr = true, noremap = true })
vim.g.copilot_no_tab_map = true

-- Goyo toggle
vim.api.nvim_set_keymap('n', '<leader>g', ':Goyo<CR>', { noremap = true })

-- Markdown Preview toggle
vim.api.nvim_set_keymap('n', '<F11>', '<plug>MarkdownPreviewToggle', {})

-- vimtex compile and view
vim.api.nvim_set_keymap('n', '<leader>\\', '<plug>(vimtex-compile)', {})
vim.api.nvim_set_keymap('n', '<F12>', '<plug>(vimtex-view)', {})

-- NERDTree keybinds and auto-open
vim.api.nvim_set_keymap('n', '<leader>f', ':NERDTreeToggle<CR>', { noremap = true })

-- Helper to enavle NERDTree if no file is passed. The telescope workflow is much faster.
-- vim.cmd([[
--   autocmd StdinReadPre * let s:std_in=1
--   autocmd VimEnter * if argc() == 0 && !exists("s:std_in") | NERDTree | endif
--   autocmd StdinReadPre * let s:std_in=1
--   autocmd VimEnter * if argc() == 0 && !exists("s:std_in") && v:this_session == "" | NERDTree | endif
--   autocmd StdinReadPre * let s:std_in=1
--   autocmd VimEnter * if argc() == 1 && isdirectory(argv()[0]) && !exists("s:std_in") | exe 'NERDTree' argv()[0] | wincmd p | ene | exe 'cd '.argv()[0] | endif
--   autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif
-- ]])

-- Easymotion keybinds
vim.api.nvim_set_keymap('n', ',', '<Plug>(easymotion-prefix)', {})

