{
  config,
  pkgs,
  lib,
  ...
}: {
  ## NOTE: These are old and kept for archival purposes only

  # home.file.".config/hypr/monitors.conf" = lib.mkForce {
  #   source = ../../config/hypr/monitors.conf;
  #   force = true;
  #   mutable = true;
  # };

  # home.file.".config/hypr/userprefs.conf" = lib.mkForce {
  #   source = ../../config/hypr/userprefs.conf;
  #   force = true;
  #   mutable = true;
  # };

  # home.file.".config/hypr/hyde.conf" = lib.mkForce {
  #   source = ../../config/hypr/hyde.conf;
  #   force = true;
  #   mutable = true;
  # };

  # home.file.".config/hypr/hypridle.conf" = lib.mkForce {
  #   source = ../../config/hypr/hypridle.conf;
  #   force = true;
  #   mutable = true;
  # };

  # home.file.".config/waybar/config.ctl" = lib.mkForce {
  #   source = ../../config/waybar/config.ctl;
  #   force = true;
  #   mutable = true;
  # };

  home.file.".config/hypr/keybindings.conf" = lib.mkForce {
    source = ../../config/hypr/keybindings.conf;
    force = true;
    mutable = true;
  };

  home.file.".config/hypr/shaders/paper-custom.frag" = lib.mkForce {
    source = ../../config/hypr/shaders/paper-custom.frag;
    force = true;
    mutable = true;
  };

  home.file.".config/hypr/shaders.conf" = lib.mkForce {
    source = ../../config/hypr/shaders.conf;
    force = true;
    mutable = true;
  };
}
