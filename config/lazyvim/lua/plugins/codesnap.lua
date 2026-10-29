return {
    "mistricky/codesnap.nvim",
    keys = {
        { "<leader>ss", "<Esc><cmd>CodeSnap<cr>",      mode = 'x', desc = "Copy code snapshot to clipboard" },
        { "<leader>sa", "<Esc><cmd>CodeSnapASCII<cr>", mode = 'x', desc = "Copy ASCII code snapshot to clipboard" },
    },
    opts = {
        show_line_number = true,
        snapshot_config = {
            code_config = { breadcrumbs = { enable = true } },
            watermark = { content = "" },
        },
    },
}
