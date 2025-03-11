{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    # Hyprland
    ./hyprland/keybinds.nix
    ./hyprland/rules.nix
    ./rofi.nix
    ./waybar.nix
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    settings = {
      "$mod" = "SUPER";

      monitor = [
        "eDP-1,highrr,auto,1"
        "eDP-2,highrr,auto,1.5"
        ",highrr,auto,1"
      ];

      env = [
        "NIXOS_OZONE_WL,1"
        "NIXPKGS_ALLOW_UNFREE,1"
        "XDG_CURRENT_DESKTOP,Hyprland"
        "XDG_SESSION_TYPE,wayland"
        "XDG_SESSION_DESKTOP,Hyprland"
        "GDK_BACKEND,wayland"
        "CLUTTER_BACKEND,wayland"
        "QT_QPA_PLATFORM,wayland"
        "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
        "QT_AUTO_SCREEN_SCALE_FACTOR,1"
        "MOZ_ENABLE_WAYLAND,1"
      ];

      exec-once = [
        "waybar"
        "dunst"
        "swww init"
        "hyprlock"
        "wl-paste --type text --watch cliphist store"
        "wl-paste --type image --watch cliphist store"
        "wl-clip-persist --clipboard both"
        "hyprctl setcursor Nordzy-cursors-white 30"
        "kitty & [workspace 1]"
        "vivaldi & [workspace 2]"
        "spotify & [workspace 3]"
        "cursor & [workspace 4]"
      ];

      gestures = {
        workspace_swipe = true;
        workspace_swipe_fingers = 3;
      };

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
          size = 3;
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
          "linear, 0, 0, 1, 1"
          "md3_standard, 0.2, 0, 0, 1"
          "md3_decel, 0.05, 0.7, 0.1, 1"
          "md3_accel, 0.3, 0, 0.8, 0.15"
          "overshot, 0.05, 0.9, 0.1, 1.1"
          "crazyshot, 0.1, 1.5, 0.76, 0.92"
          "hyprnostretch, 0.05, 0.9, 0.1, 1.0"
          "menu_decel, 0.1, 1, 0, 1"
          "menu_accel, 0.38, 0.04, 1, 0.07"
          "easeInOutCirc, 0.85, 0, 0.15, 1"
          "easeOutCirc, 0, 0.55, 0.45, 1"
          "easeOutExpo, 0.16, 1, 0.3, 1"
          "softAcDecel, 0.26, 0.26, 0.15, 1"
          "md2, 0.4, 0, 0.2, 1"
        ];
        animation = [
          "windows, 1, 3, md3_decel, popin 60%"
          "windowsIn, 1, 3, md3_decel, popin 60%"
          "windowsOut, 1, 3, md3_accel, popin 60%"
          "border, 1, 10, default"
          "fade, 1, 3, md3_decel"
          "layersIn, 1, 3, menu_decel, slide"
          "layersOut, 1, 1.6, menu_accel"
          "fadeLayersIn, 1, 2, menu_decel"
          "fadeLayersOut, 1, 4.5, menu_accel"
          "workspaces, 1, 7, menu_decel, slide"
          "specialWorkspace, 1, 3, md3_decel, slidevert"
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
        sensitivity = -0.5;
        accel_profile = "flat";
      };
    };
  };
}
