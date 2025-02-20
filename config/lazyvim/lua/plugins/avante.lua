return {
  "yetone/avante.nvim",
  event = "VeryLazy",
  lazy = true,
  version = false,
  disable_tools = false,
  config = function()
      require("avante").setup({
          provider = "copilot",
          vendors = {
              deepseek = {
                  __inherited_from = "openai",
                  endpoint = "https://openrouter.ai/api/v1",
                  api_key_name = "OPENROUTER_API_KEY",
                  model = "deepseek:deepseek-r1:free",
                  max_tokens = 8192,
              },
              openrouter = {
                  __inherited_from = "openai",
                  endpoint = "https://openrouter.ai/api/v1",
                  api_key_name = "OPENROUTER_API_KEY",
                  model = "anthropic/claude-3.5-sonnet:beta",
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
      -- "zbirenbaum/copilot.lua", -- for providers='copilot'
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
  keys = {
    { "<leader>ai", "<cmd>AvanteAsk<CR>", desc = "Open Avante" }
  }
}
