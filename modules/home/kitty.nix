{
  config,
  pkgs,
  lib,
  ...
}: {
  home.file.".config/kitty/kitty.conf" = lib.mkForce {
    source = ../../config/kitty/kitty.conf;
    force = true;
  };
}
