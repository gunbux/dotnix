{
  config,
  pkgs,
  lib,
  ...
}: {
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
