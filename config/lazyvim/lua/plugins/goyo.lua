return {
    { 'amix/vim-zenroom2' },
    { 
        'junegunn/goyo.vim',
        config = function()
            -- Goyo plugin settings
            vim.g.goyo_width = 100
            vim.g.goyo_margin_top = 2
            vim.g.goyo_margin_bottom = 2
            -- Goyo toggle
            vim.api.nvim_set_keymap('n', '<leader>g', ':Goyo<CR>', { noremap = true })
        end,
    },
}
