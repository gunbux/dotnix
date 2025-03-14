{
  config,
  pkgs,
  lib,
  ...
}: {
  # Additional hyprland configs
  home.file.".config/hypr/monitors.conf" = lib.mkForce {
    source = ../../config/hypr/monitors.conf;
    force = true;
    mutable = true;
  };

  home.file.".config/hypr/userprefs.conf" = lib.mkForce {
    source = ../../config/hypr/userprefs.conf;
    force = true;
    mutable = true;
  };

  home.file.".config/hypr/keybindings.conf" = lib.mkForce {
    source = ../../config/hypr/keybindings.conf;
    force = true;
    mutable = true;
  };

  home.file.".config/waybar/config.ctl" = lib.mkForce {
    source = ../../config/waybar/config.ctl;
    force = true;
    mutable = true;
  };
}
