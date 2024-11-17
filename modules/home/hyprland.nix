{ config, pkgs, lib, ... }:
{
  wayland.windowManager.hyprland = {
    enable = true;
    settings = {
      "$mod" = "SUPER";
      
      monitor = [
        "eDP-1,preferred,auto,1"
        "eDP-2,preferred,auto,1.5"
        ",preferred,auto,1"
      ];

      exec-once = [
        "waybar"
        "dunst"
        "swww init"
        "hyprlock"
        # "~/.config/hypr/scripts/wallpaper.sh"
      ];

      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
        "col.active_border" = "rgba(33ccffee) rgba(00ff99ee) 45deg";
        "col.inactive_border" = "rgba(595959aa)";
        layout = "dwindle";
      };

      decoration = {
        rounding = 10;
        blur = {
          enabled = true;
          size = 10;
          passes = 3;
          new_optimizations = true;
          ignore_opacity = true;
        };
        shadow = {
          enabled = true;
          range = 14;
          render_power = 3;
          scale = 0.30;
        };
      };

      animations = {
        enabled = true;
        bezier = [
          "smoothOut, 0.25, 0, 0.4, -0.3" # Made curve steeper and shorter
          "smoothIn, 0.2, 0.8, 0.3, 0.9"  # Reduced curve duration
          "overshot, 0.1, 0.8, 0.2, 1.05" # Reduced overshoot and made faster
        ];
        animation = [
          "windows, 1, 4, smoothOut, slide"
          "windowsOut, 1, 7, smoothIn, slide"
          "border, 1, 10, default"
          "fade, 1, 7, smoothIn"
          "workspaces, 1, 6, overshot, slidevert"
        ];
      };

      dwindle = {
        pseudotile = true;
        preserve_split = true;
      };

      input = {
        kb_options = "caps:swapescape";
        touchpad = {
          natural_scroll = true;
        };
      };

      # Keybindings
      bind = [
        "$mod, Return, exec, kitty"
        "$mod, Q, killactive,"
        "$mod, F, exec, nautilus"
        "$mod, V, togglefloating,"
        "$mod, J, togglesplit,"
        "$mod, F, fullscreen, 1"
        "$mod, SPACE, exec, rofi -show drun"
        # "$mod, N, exec, networkmanager_dmenu"
        # "$mod, R, exec, rofi -show calc"
        # Lock screen
        # "$mod, L, exec, hyprlock"
        # Color picker
        "$mod, C, exec, hyprpicker --autocopy"

        # Move focus with vim keys
        "$mod, h, movefocus, l"
        "$mod, l, movefocus, r" 
        "$mod, k, movefocus, u"
        "$mod, j, movefocus, d"

        # Resize windows
        "$mod CTRL, h, resizeactive, -20 0"
        "$mod CTRL, l, resizeactive, 20 0"
        "$mod CTRL, k, resizeactive, 0 -20"
        "$mod CTRL, j, resizeactive, 0 20"

        # Switch workspaces
        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod, 6, workspace, 6"
        "$mod, 7, workspace, 7"
        "$mod, 8, workspace, 8"
        "$mod, 9, workspace, 9"
        "$mod, 0, workspace, 10"

        # Move active window to workspace
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        "$mod SHIFT, 6, movetoworkspace, 6"
        "$mod SHIFT, 7, movetoworkspace, 7"
        "$mod SHIFT, 8, movetoworkspace, 8"
        "$mod SHIFT, 9, movetoworkspace, 9"
        "$mod SHIFT, 0, movetoworkspace, 10"

        # Application shortcuts
        "$mod, E, exec, nautilus"
        "$mod, M, exec, spotify" 
        "$mod, D, exec, discord"
        "$mod, B, exec, vivaldi"
      ];

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];
    };
  };

  # Configure waybar
  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        modules-left = ["hyprland/workspaces"];
        modules-center = ["clock"];
        modules-right = ["pulseaudio" "network" "battery"];
        font-family = "JetBrainsMono Nerd Font";
        font-size = 13;
      };
    };
  };

  # Add rofi configuration
  programs.rofi = {
    enable = true;
    package = pkgs.rofi-wayland;
    plugins = with pkgs; [
      rofi-calc
      rofi-emoji
    ];
    extraConfig = {
      modi = "run,drun,window";
      show-icons = true;
      terminal = "kitty";
      drun-display-format = "{icon} {name}";
      location = 0;
      disable-history = false;
      hide-scrollbar = true;
      display-drun = "   Apps ";
      display-run = "   Run ";
      display-window = " 﩯  Window";
      display-Network = " 󰤨  Network";
      sidebar-mode = true;
    };
  };

  # Copy the theme files to the correct location
  # home.file = {
  #   ".config/rofi" = {
  #     source = "${rofi-catppuccin}/deathemonic";
  #     recursive = true;
  #   };
  # };
}