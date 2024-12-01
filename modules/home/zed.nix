{
  programs.zed-editor = {
    enable = true;

    userSettings = {
      # Important Core Settings
      base_keymap = "JetBrains";
      vim_mode = true;

      # AI Assistant settings
      assistant = {
        default_model = {
          provider = "copilot_chat";
          model = "claude-3-5-sonnet";
        };
        version = "2";
      };

      # Theme settings
      theme = {
        mode = "system";
        light = "One Light";
        dark = "Catppuccin Mocha";
      };

      # Font settings
      ui_font_size = 16;
      buffer_font_size = 16;
      buffer_font = "JetBrainsMono Nerd Font";

      # Editor settings
      autosave = "on_focus_change";
      tab_size = 2;
      file_icons = true;
      git_status = true;
      load_direnv = "shell_hook";
      soft_wrap = "none";
      cursor_blink = false;
      format_on_save = "on";
    };

    # Add custom keymaps
    # TODO: Fix Pane context
    userKeymaps = [
      {
        context = "Pane";
        bindings = {
          ctrl-shift-w = "pane::CloseActiveItem"; 
          alt-1 = "file_finder::Toggle";
          alt-4 = "workspace::NewTerminal";
        };
      }
      {
        context = "Editor";
        bindings = {
          "j k" = ["workspace::SendKeystrokes" "escape"];
          ctrl-d = "editor::MovePageDown";
        };
      }
    ];

  };
}
