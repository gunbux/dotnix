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
        bindings = {
          ctrl-shift-w = "pane::CloseActiveItem";
          alt-1 = "workspace::ToggleLeftDock";
          alt-4 = "workspace::ToggleBottomDock";
        };
      }
      {
        context = "Editor";
        bindings = {
          "j k" = ["workspace::SendKeystrokes" "escape"];
          ctrl-d = "editor::MovePageDown";
        };
      }
      {
        context = "Workspace";
        bindings = {
          ctrl-1 = ["workspace::ActivatePane" 0];
          ctrl-2 = ["workspace::ActivatePane" 1];
          ctrl-3 = ["workspace::ActivatePane" 2];
          ctrl-4 = ["workspace::ActivatePane" 3];
          ctrl-5 = ["workspace::ActivatePane" 4];
          ctrl-6 = ["workspace::ActivatePane" 5];
          ctrl-7 = ["workspace::ActivatePane" 6];
          ctrl-8 = ["workspace::ActivatePane" 7];
          ctrl-9 = ["workspace::ActivatePane" 8];
        };
      }
    ];

  };
}
