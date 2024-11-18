{ config, lib, ... }:
let
  mod = "SUPER";
in
{
  wayland.windowManager.hyprland.settings = {
    bind = [
      "ALT, Tab, cyclenext"
      "${mod}, Return, exec, kitty"
      "${mod}, Q, killactive,"
      "${mod}, F, exec, nautilus"
      # "${mod}, V, togglefloating,"
      "${mod}, J, togglesplit,"
      "${mod}, F, fullscreen, 1"
      "${mod}, SPACE, exec, rofi -show drun"
      ", SUPER, exec, rofi -show drun"
      "${mod}, C, exec, hyprpicker --autocopy"
      "${mod}, E, exec, nautilus"
      "${mod}, M, exec, spotify"
      "${mod}, D, exec, discord"
      "${mod}, B, exec, vivaldi"
      "${mod}, I, exec, XDG_CURRENT_DESKTOP=\"gnome\" gnome-control-center"

      # Move focus with vim keys
      "${mod}, h, movefocus, l"
      "${mod}, l, movefocus, r" 
      "${mod}, k, movefocus, u"
      "${mod}, j, movefocus, d"

      # Resize windows
      "${mod} CTRL, h, resizeactive, -20 0"
      "${mod} CTRL, l, resizeactive, 20 0"
      "${mod} CTRL, k, resizeactive, 0 -20"
      "${mod} CTRL, j, resizeactive, 0 20"

      # Switch workspaces
      "${mod}, 1, workspace, 1"
      "${mod}, 2, workspace, 2"
      "${mod}, 3, workspace, 3"
      "${mod}, 4, workspace, 4"
      "${mod}, 5, workspace, 5"
      "${mod}, 6, workspace, 6"
      "${mod}, 7, workspace, 7"
      "${mod}, 8, workspace, 8"
      "${mod}, 9, workspace, 9"
      "${mod}, 0, workspace, 10"

      # Move active window to workspace
      "${mod} SHIFT, 1, movetoworkspace, 1"
      "${mod} SHIFT, 2, movetoworkspace, 2"
      "${mod} SHIFT, 3, movetoworkspace, 3"
      "${mod} SHIFT, 4, movetoworkspace, 4"
      "${mod} SHIFT, 5, movetoworkspace, 5"
      "${mod} SHIFT, 6, movetoworkspace, 6"
      "${mod} SHIFT, 7, movetoworkspace, 7"
      "${mod} SHIFT, 8, movetoworkspace, 8"
      "${mod} SHIFT, 9, movetoworkspace, 9"
      "${mod} SHIFT, 0, movetoworkspace, 10"

      # Clipboard History and Emoji Picker
      "${mod}, V, exec, pkill fuzzel || cliphist list | fuzzel  --match-mode fzf --dmenu | cliphist decode | wl-copy"
      "${mod}, Period, exec, pkill fuzzel || ~/.local/bin/fuzzel-emoji"

      # Screenshot and OCR
      "${mod} SHIFT, S, exec, grim -g \"$(slurp)\" - | wl-copy"
      "${mod} SHIFT, T, exec, grim -g \"$(slurp $SLURP_ARGS)\" \"tmp.png\" && tesseract -l eng \"tmp.png\" - | wl-copy && rm \"tmp.png\""
      "${mod} SHIFT, C, exec, hyprpicker -a"
      ", Print, exec, grim - | wl-copy"

      # Lock and Suspend
      "${mod} SHIFT, L, exec, loginctl lock-session"
      # "${mod} SHIFT, L, exec, sleep 0.1 && systemctl suspend || loginctl suspend"
    ];

    bindl = [
      ", XF86AudioMute, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 0%"
      "Super+Shift, M, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 0%"
    ];

    bindle = [
      ", XF86AudioRaiseVolume, exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"
      ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
      ", XF86MonBrightnessUp, exec, brightnessctl set '12.75+'"
      ", XF86MonBrightnessDown, exec, brightnessctl set '12.75-'"
    ];

    bindm = [
      "${mod}, mouse:272, movewindow"
      "${mod}, mouse:273, resizewindow"
    ];
 };
}